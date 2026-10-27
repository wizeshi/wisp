package dev.wizeshi.wisp_innertubex_manager

import android.content.Context
import androidx.annotation.NonNull
import com.metrolist.innertubex.InnerTube
import com.metrolist.innertubex.cipher.PlayerConfigRepository
import com.metrolist.innertubex.cipher.RemotePlayerConfigStore
import com.metrolist.innertubex.cipher.YouTubeCipherService
import com.metrolist.innertubex.extraction.AudioQuality
import com.metrolist.innertubex.extraction.ContentHints
import com.metrolist.innertubex.extraction.InnerTubeExtractor
import com.metrolist.innertubex.extraction.YtConfigParserImpl
import com.metrolist.innertubex.models.YouTubeClient
import com.metrolist.innertubex.models.response.PlayerResponse
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.statement.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.util.concurrent.ConcurrentHashMap

/** WispInnertubexManagerPlugin */
class WispInnertubexManagerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.Main)

    private val httpClient = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    private val innerTube = InnerTube(httpClient)
    private val configStore = RemotePlayerConfigStore(httpClient, PlayerConfigRepository.disabled())
    private val cipherService = YouTubeCipherService(httpClient, configStore)
    private val extractor = InnerTubeExtractor(
        configParser = YtConfigParserImpl(
            httpClient = httpClient,
            innerTube = innerTube,
            remotePlayerConfigStore = configStore,
            cipherService = cipherService
        ),
        cipherService = cipherService,
        innerTube = innerTube,
    )

    private val jsonParser = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val sessionCookies = ConcurrentHashMap<String, String>()
    private var cachedDisplayName: String? = null

    private suspend fun fetchAccountDisplayName(): String? {
        try {
            val resp = innerTube.accountMenu(YouTubeClient.WEB_REMIX)
            val body = resp.body<com.metrolist.innertubex.models.response.AccountMenuResponse>()
            val header = body.actions.firstOrNull()?.openPopupAction?.popup?.multiPageMenuRenderer?.header
            val info = header?.activeAccountHeaderRenderer?.toAccountInfo()
            val name = info?.name?.takeIf { it.isNotBlank() } ?: info?.channelHandle?.takeIf { it.isNotBlank() }
            if (!name.isNullOrBlank()) return name
        } catch (_: Exception) {}

        try {
            val listResp = innerTube.accountsList(YouTubeClient.WEB_REMIX)
            val accounts = listResp.body<com.metrolist.innertubex.models.response.AccountsListResponse>().extractAccounts()
            val sel = accounts.firstOrNull { it.isSelected } ?: accounts.firstOrNull()
            val name = sel?.name?.takeIf { it.isNotBlank() }
                ?: sel?.displayName?.takeIf { it.isNotBlank() }
                ?: sel?.channelHandle?.takeIf { it.isNotBlank() }
            if (!name.isNullOrBlank()) return name
        } catch (_: Exception) {}

        return null
    }

    init {
        try {
            System.setProperty("java.net.preferIPv6Addresses", "true")
        } catch (_: Exception) {}
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.wizeshi.wisp/innertubex_android")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "resolveStream" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "videoId must not be blank", null)
                    return
                }
                scope.launch {
                    try {
                        val streamResult = withContext(Dispatchers.IO) {
                            val stream = extractor.extract(
                                videoId = videoId,
                                hints = ContentHints(wantVideo = false),
                                audioQuality = AudioQuality.HIGH,
                            )

                            if (stream != null && stream.audioUrl.isNotBlank()) {
                                val isOpus = stream.mimeType?.contains("webm") == true || stream.mimeType?.contains("opus") == true
                                val bitrate = (stream.bitrate ?: 160000) / 1000
                                mapOf(
                                    "videoId" to videoId,
                                    "url" to stream.audioUrl,
                                    "format" to if (isOpus) "opus" else "m4a",
                                    "bitrate" to bitrate,
                                    "isSabr" to (stream.sabrBootstrap != null)
                                )
                            } else {
                                null
                            }
                        }
                        if (streamResult != null) {
                            result.success(streamResult)
                        } else {
                            result.error("RESOLVE_FAILED", "Stream unavailable for $videoId", null)
                        }
                    } catch (e: Exception) {
                        result.error("RESOLVE_FAILED", e.message, null)
                    }
                }
            }

            "search" -> {
                val query = call.argument<String>("query") ?: ""
                val type = call.argument<String>("type")
                val limit = call.argument<Int>("limit") ?: 20
                scope.launch {
                    try {
                        val searchResults = withContext(Dispatchers.IO) {
                            val response = innerTube.search(
                                client = YouTubeClient.WEB_REMIX,
                                query = query,
                                setLogin = innerTube.hasSapCookieAuth()
                            )
                            val jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                            val allItems = mutableListOf<Map<String, Any?>>()
                            collectSearchResultItems(jsonBody, allItems)

                            var filtered = if (!type.isNullOrBlank()) {
                                val target = type.lowercase()
                                allItems.filter { (it["type"] as? String)?.lowercase() == target }
                            } else {
                                allItems
                            }

                            if (filtered.isEmpty() && allItems.isNotEmpty()) {
                                filtered = allItems
                            }

                            filtered.take(limit)
                        }
                        result.success(searchResults)
                    } catch (e: Exception) {
                        result.error("SEARCH_FAILED", e.message, null)
                    }
                }
            }

            "getTrackDetails" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "videoId must not be blank", null)
                    return
                }
                scope.launch {
                    try {
                        val track = withContext(Dispatchers.IO) {
                            val res = innerTube.player(YouTubeClient.WEB, videoId)
                            val player = res.body<PlayerResponse>()
                            val details = player.videoDetails
                            val title = details?.title ?: "Unknown Title"
                            val author = details?.author ?: "Unknown Artist"
                            val authorId = details?.channelId
                            val lengthSec = details?.lengthSeconds?.toLongOrNull() ?: 0L
                            val thumbUrl = details?.thumbnail?.thumbnails?.lastOrNull()?.url
                                ?: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"

                            mapOf(
                                "videoId" to videoId,
                                "title" to title,
                                "author" to author,
                                "authorId" to authorId,
                                "durationSeconds" to lengthSec,
                                "thumbnailUrl" to thumbUrl,
                                "hasLyrics" to true,
                                "isSabrAvailable" to false
                            )
                        }
                        result.success(track)
                    } catch (e: Exception) {
                        result.error("TRACK_FAILED", e.message, null)
                    }
                }
            }

            "getAlbumDetails" -> {
                val browseId = call.argument<String>("browseId") ?: ""
                scope.launch {
                    try {
                        val album = withContext(Dispatchers.IO) {
                            val response = innerTube.browse(
                                client = YouTubeClient.WEB_REMIX,
                                browseId = browseId,
                                setLogin = innerTube.hasSapCookieAuth()
                            )
                            val jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                            val header = findHeaderRenderer(jsonBody)

                            val title = extractRunsText(header?.get("title")) ?: "Unknown Album"
                            val artist = extractRunsText(header?.get("straplineTextOne") ?: header?.get("subtitle")) ?: "Unknown Artist"
                            val artistId = header?.get("straplineTextOne")?.jsonObject?.get("runs")?.jsonArray?.getOrNull(0)
                                ?.jsonObject?.get("navigationEndpoint")?.jsonObject?.get("browseEndpoint")?.jsonObject?.get("browseId")?.jsonPrimitive?.contentOrNull
                            val subtitleText = extractRunsText(header?.get("subtitle"))
                            val year = subtitleText?.split("•", "·", " ")?.firstOrNull { it.trim().length == 4 && it.trim().all { c -> c.isDigit() } }?.trim()
                            val thumbUrl = extractThumbnailUrl(header?.get("thumbnail")) ?: "https://i.ytimg.com/vi/$browseId/hqdefault.jpg"

                            val rawItems = mutableListOf<Map<String, Any?>>()
                            collectSearchResultItems(jsonBody, rawItems)
                            val trackItems = rawItems.filter { it["type"] == "track" }

                            val tracks = trackItems.mapIndexed { idx, it ->
                                mapOf(
                                    "videoId" to (it["id"] ?: "${browseId}_t${idx + 1}"),
                                    "title" to (it["title"] ?: "Track ${idx + 1}"),
                                    "artist" to (it["artist"] ?: artist),
                                    "durationSeconds" to (it["durationSeconds"] ?: 0L),
                                    "index" to (idx + 1)
                                )
                            }

                            mapOf(
                                "browseId" to browseId,
                                "title" to title,
                                "artist" to artist,
                                "artistId" to artistId,
                                "year" to year,
                                "thumbnailUrl" to thumbUrl,
                                "trackCount" to tracks.size,
                                "tracks" to tracks
                            )
                        }
                        result.success(album)
                    } catch (e: Exception) {
                        result.error("ALBUM_FAILED", e.message, null)
                    }
                }
            }

            "getArtistDetails" -> {
                val browseId = call.argument<String>("browseId") ?: ""
                scope.launch {
                    try {
                        val artist = withContext(Dispatchers.IO) {
                            val response = innerTube.browse(
                                client = YouTubeClient.WEB_REMIX,
                                browseId = browseId,
                                setLogin = innerTube.hasSapCookieAuth()
                            )
                            val jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                            val header = findHeaderRenderer(jsonBody)

                            val name = extractRunsText(header?.get("title")) ?: "Artist"
                            val avatarUrl = extractThumbnailUrl(header?.get("thumbnail")) ?: "https://i.ytimg.com/vi/$browseId/hqdefault.jpg"

                            var bio: String? = null
                            if (jsonBody is JsonObject) {
                                fun findDescription(e: JsonElement): String? {
                                    if (e is JsonObject) {
                                        if (e.containsKey("musicDescriptionShelfRenderer")) {
                                            return extractRunsText(e["musicDescriptionShelfRenderer"]?.jsonObject?.get("description"))
                                        }
                                        for (v in e.values) {
                                            val desc = findDescription(v)
                                            if (desc != null) return desc
                                        }
                                    } else if (e is JsonArray) {
                                        for (v in e) {
                                            val desc = findDescription(v)
                                            if (desc != null) return desc
                                        }
                                    }
                                    return null
                                }
                                bio = findDescription(jsonBody)
                            }

                            val allItems = mutableListOf<Map<String, Any?>>()
                            collectSearchResultItems(jsonBody, allItems)

                            val topTracks = allItems.filter { it["type"] == "track" }
                            val albums = allItems.filter { it["type"] == "album" }

                            mapOf(
                                "browseId" to browseId,
                                "name" to name,
                                "bio" to bio,
                                "avatarUrl" to avatarUrl,
                                "topTracks" to topTracks,
                                "albums" to albums,
                                "singles" to emptyList<Map<String, Any?>>()
                            )
                        }
                        result.success(artist)
                    } catch (e: Exception) {
                        result.error("ARTIST_FAILED", e.message, null)
                    }
                }
            }

            "getPlaylistDetails" -> {
                val browseId = call.argument<String>("browseId") ?: ""
                scope.launch {
                    try {
                        val playlist = withContext(Dispatchers.IO) {
                            val targetBrowseId = if (browseId.startsWith("PL")) "VL$browseId" else browseId
                            var response = innerTube.browse(
                                client = YouTubeClient.WEB_REMIX,
                                browseId = targetBrowseId,
                                setLogin = innerTube.hasSapCookieAuth()
                            )
                            var jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                            var header = findHeaderRenderer(jsonBody)

                            if (header == null) {
                                response = innerTube.browse(
                                    client = YouTubeClient.WEB,
                                    browseId = targetBrowseId,
                                    setLogin = innerTube.hasSapCookieAuth()
                                )
                                jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                                header = findHeaderRenderer(jsonBody)
                            }

                            val title = extractRunsText(header?.get("title")) ?: "Playlist"
                            val author = extractRunsText(header?.get("subtitle") ?: header?.get("ownerText")) ?: "YouTube"
                            val description = extractRunsText(header?.get("description"))
                            val thumbUrl = extractThumbnailUrl(header?.get("thumbnail")) ?: "https://i.ytimg.com/vi/$browseId/hqdefault.jpg"

                            val allItems = mutableListOf<Map<String, Any?>>()
                            collectSearchResultItems(jsonBody, allItems)
                            val tracks = allItems.filter { it["type"] == "track" }

                            mapOf(
                                "browseId" to browseId,
                                "title" to title,
                                "author" to author,
                                "description" to description,
                                "trackCount" to tracks.size,
                                "thumbnailUrl" to thumbUrl,
                                "tracks" to tracks
                            )
                        }
                        result.success(playlist)
                    } catch (e: Exception) {
                        result.error("PLAYLIST_FAILED", e.message, null)
                    }
                }
            }

            "updateSessionCookies" -> {
                val cookies = call.argument<Map<String, String>>("cookies") ?: emptyMap()
                scope.launch {
                    try {
                        sessionCookies.clear()
                        sessionCookies.putAll(cookies)

                        val cookieStr = cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
                        innerTube.cookie = cookieStr

                        val hasAuth = innerTube.hasSapCookieAuth() || cookies.containsKey("SAPISID") || cookies.containsKey("LOGIN_INFO")
                        val realName = if (hasAuth) {
                            withContext(Dispatchers.IO) { fetchAccountDisplayName() }
                        } else null
                        cachedDisplayName = realName

                        result.success(
                            mapOf(
                                "authenticated" to hasAuth,
                                "isLoggedIn" to hasAuth,
                                "userDisplayName" to (cachedDisplayName ?: if (hasAuth) "YouTube Music User" else null),
                                "accountName" to (cachedDisplayName ?: if (hasAuth) "YouTube Music User" else null),
                                "userId" to cookies["SAPISID"]?.hashCode()?.toString()
                            )
                        )
                    } catch (e: Exception) {
                        result.error("AUTH_FAILED", e.message, null)
                    }
                }
            }

            "getAuthStatus" -> {
                val hasAuth = innerTube.hasSapCookieAuth() || sessionCookies.containsKey("SAPISID") || sessionCookies.containsKey("LOGIN_INFO")
                result.success(
                    mapOf(
                        "authenticated" to hasAuth,
                        "isLoggedIn" to hasAuth,
                        "userDisplayName" to (cachedDisplayName ?: if (hasAuth) "YouTube Music User" else null),
                        "accountName" to (cachedDisplayName ?: if (hasAuth) "YouTube Music User" else null),
                        "userId" to sessionCookies["SAPISID"]?.hashCode()?.toString()
                    )
                )
            }

            "clearSession" -> {
                sessionCookies.clear()
                innerTube.cookie = null
                innerTube.visitorData = null
                cachedDisplayName = null
                result.success(
                    mapOf(
                        "authenticated" to false,
                        "isLoggedIn" to false,
                        "userDisplayName" to null,
                        "accountName" to null,
                        "userId" to null
                    )
                )
            }

            "getLikedTracks" -> {
                scope.launch {
                    try {
                        val tracks = withContext(Dispatchers.IO) {
                            val response = innerTube.browse(
                                client = YouTubeClient.WEB_REMIX,
                                browseId = "FEmusic_liked_videos",
                                setLogin = true
                            )
                            val jsonBody = jsonParser.parseToJsonElement(response.bodyAsText())
                            val allItems = mutableListOf<Map<String, Any?>>()
                            collectSearchResultItems(jsonBody, allItems)
                            allItems.filter { it["type"] == "track" }
                        }
                        result.success(tracks)
                    } catch (e: Exception) {
                        result.error("LIKED_TRACKS_FAILED", e.message, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun extractRunsText(element: JsonElement?): String? {
        if (element == null) return null
        if (element is JsonPrimitive) return element.contentOrNull
        if (element is JsonObject) {
            val runs = element["runs"]?.jsonArray
            if (runs != null) {
                return runs.mapNotNull { it.jsonObject["text"]?.jsonPrimitive?.contentOrNull }
                    .joinToString("")
                    .trim()
                    .ifEmpty { null }
            }
            val simpleText = element["simpleText"]?.jsonPrimitive?.contentOrNull
            if (simpleText != null) return simpleText
        }
        return null
    }

    private fun extractThumbnailUrl(element: JsonElement?): String? {
        if (element == null) return null
        val obj = if (element is JsonObject) element else return null
        val thumbs = obj["thumbnails"]?.jsonArray
            ?: obj["musicThumbnailRenderer"]?.jsonObject?.get("thumbnail")?.jsonObject?.get("thumbnails")?.jsonArray
            ?: obj["thumbnail"]?.jsonObject?.get("thumbnails")?.jsonArray
            ?: obj["croppedSquareThumbnailRenderer"]?.jsonObject?.get("thumbnail")?.jsonObject?.get("thumbnails")?.jsonArray
        return thumbs?.lastOrNull()?.jsonObject?.get("url")?.jsonPrimitive?.contentOrNull
    }

    private fun parseDurationSeconds(text: String?): Long? {
        if (text.isNullOrBlank()) return null
        val parts = text.trim().split(":")
        return when (parts.size) {
            1 -> parts[0].toLongOrNull()
            2 -> {
                val m = parts[0].toLongOrNull() ?: return null
                val s = parts[1].toLongOrNull() ?: return null
                m * 60 + s
            }
            3 -> {
                val h = parts[0].toLongOrNull() ?: return null
                val m = parts[1].toLongOrNull() ?: return null
                val s = parts[2].toLongOrNull() ?: return null
                h * 3600 + m * 60 + s
            }
            else -> null
        }
    }

    private fun parseResponsiveListItem(itemObj: JsonObject): Map<String, Any?>? {
        val r = itemObj["musicResponsiveListItemRenderer"]?.jsonObject ?: itemObj
        val flexCols = r["flexColumns"]?.jsonArray ?: return null
        if (flexCols.isEmpty()) return null

        val col0Text = flexCols.getOrNull(0)?.jsonObject?.get("musicResponsiveListItemFlexColumnRenderer")?.jsonObject?.get("text")
        val title = extractRunsText(col0Text) ?: return null

        val col1Text = flexCols.getOrNull(1)?.jsonObject?.get("musicResponsiveListItemFlexColumnRenderer")?.jsonObject?.get("text")
        val col1Runs = col1Text?.jsonObject?.get("runs")?.jsonArray

        var itemType = "track"
        var artist: String? = null
        var album: String? = null

        if (col1Runs != null && col1Runs.isNotEmpty()) {
            val nonBulletRuns = col1Runs.mapNotNull { it.jsonObject["text"]?.jsonPrimitive?.contentOrNull?.trim() }
                .filter { it.isNotEmpty() && it != "•" && it != "·" && it != " - " }

            if (nonBulletRuns.isNotEmpty()) {
                val first = nonBulletRuns[0].lowercase()
                if (first == "artist") {
                    itemType = "artist"
                    artist = title
                } else if (first == "album" || first == "ep" || first == "single") {
                    itemType = "album"
                    artist = nonBulletRuns.getOrNull(1)
                } else if (first == "playlist") {
                    itemType = "playlist"
                    artist = nonBulletRuns.getOrNull(1)
                } else if (first == "song" || first == "video") {
                    itemType = "track"
                    artist = nonBulletRuns.getOrNull(1)
                    album = nonBulletRuns.getOrNull(2)
                } else {
                    artist = nonBulletRuns[0]
                    album = nonBulletRuns.getOrNull(1)
                }
            }
        }

        val fixedCols = r["fixedColumns"]?.jsonArray
        val durationText = extractRunsText(fixedCols?.getOrNull(0)?.jsonObject?.get("musicResponsiveListItemFixedColumnRenderer")?.jsonObject?.get("text"))
            ?: col1Runs?.mapNotNull { it.jsonObject["text"]?.jsonPrimitive?.contentOrNull }?.lastOrNull { it.contains(":") }
        val durationSec = parseDurationSeconds(durationText)

        val thumbUrl = extractThumbnailUrl(r["thumbnail"])

        val nav = r["navigationEndpoint"]?.jsonObject
        val watchNav = nav?.get("watchEndpoint")?.jsonObject
        val playBtnNav = r["overlay"]?.jsonObject?.get("musicItemThumbnailOverlayRenderer")?.jsonObject
            ?.get("content")?.jsonObject?.get("musicPlayButtonRenderer")?.jsonObject
            ?.get("playNavigationEndpoint")?.jsonObject?.get("watchEndpoint")?.jsonObject

        val videoId = r["playlistItemData"]?.jsonObject?.get("videoId")?.jsonPrimitive?.contentOrNull
            ?: playBtnNav?.get("videoId")?.jsonPrimitive?.contentOrNull
            ?: watchNav?.get("videoId")?.jsonPrimitive?.contentOrNull

        val browseId = nav?.get("browseEndpoint")?.jsonObject?.get("browseId")?.jsonPrimitive?.contentOrNull

        val id = if (itemType == "track") (videoId ?: browseId) else (browseId ?: videoId)
        if (id.isNullOrBlank()) return null

        return mapOf(
            "id" to id,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "durationSeconds" to durationSec,
            "thumbnailUrl" to thumbUrl,
            "type" to itemType
        )
    }

    private fun parseTwoRowItem(itemObj: JsonObject): Map<String, Any?>? {
        val r = itemObj["musicTwoRowItemRenderer"]?.jsonObject ?: itemObj
        val title = extractRunsText(r["title"]) ?: return null
        val subtitle = extractRunsText(r["subtitle"])
        val thumbUrl = extractThumbnailUrl(r["thumbnailRenderer"])

        val nav = r["navigationEndpoint"]?.jsonObject
        val browseId = nav?.get("browseEndpoint")?.jsonObject?.get("browseId")?.jsonPrimitive?.contentOrNull
        val videoId = nav?.get("watchEndpoint")?.jsonObject?.get("videoId")?.jsonPrimitive?.contentOrNull

        var itemType = "album"
        val subLower = subtitle?.lowercase() ?: ""
        if (subLower.contains("artist")) {
            itemType = "artist"
        } else if (subLower.contains("playlist")) {
            itemType = "playlist"
        } else if (subLower.contains("single") || subLower.contains("ep") || subLower.contains("album")) {
            itemType = "album"
        } else if (subLower.contains("song")) {
            itemType = "track"
        } else if (browseId?.startsWith("UC") == true) {
            itemType = "artist"
        } else if (browseId?.startsWith("MPRE") == true) {
            itemType = "album"
        } else if (browseId?.startsWith("VL") == true) {
            itemType = "playlist"
        }

        val id = browseId ?: videoId ?: return null

        return mapOf(
            "id" to id,
            "title" to title,
            "artist" to subtitle,
            "album" to null,
            "durationSeconds" to null,
            "thumbnailUrl" to thumbUrl,
            "type" to itemType
        )
    }

    private fun collectSearchResultItems(element: JsonElement, items: MutableList<Map<String, Any?>>) {
        when (element) {
            is JsonObject -> {
                if (element.containsKey("musicResponsiveListItemRenderer")) {
                    parseResponsiveListItem(element)?.let { items.add(it) }
                    return
                }
                if (element.containsKey("musicTwoRowItemRenderer")) {
                    parseTwoRowItem(element)?.let { items.add(it) }
                    return
                }
                for (value in element.values) {
                    collectSearchResultItems(value, items)
                }
            }
            is JsonArray -> {
                for (item in element) {
                    collectSearchResultItems(item, items)
                }
            }
            else -> {}
        }
    }

    private fun findHeaderRenderer(element: JsonElement): JsonObject? {
        if (element is JsonObject) {
            if (element.containsKey("musicResponsiveHeaderRenderer")) return element["musicResponsiveHeaderRenderer"]?.jsonObject
            if (element.containsKey("musicDetailHeaderRenderer")) return element["musicDetailHeaderRenderer"]?.jsonObject
            if (element.containsKey("musicImmersiveHeaderRenderer")) return element["musicImmersiveHeaderRenderer"]?.jsonObject
            if (element.containsKey("musicVisualHeaderRenderer")) return element["musicVisualHeaderRenderer"]?.jsonObject
            if (element.containsKey("musicHeaderRenderer")) return element["musicHeaderRenderer"]?.jsonObject
            if (element.containsKey("musicEditablePlaylistDetailHeaderRenderer")) return element["musicEditablePlaylistDetailHeaderRenderer"]?.jsonObject
            for (value in element.values) {
                val found = findHeaderRenderer(value)
                if (found != null) return found
            }
        } else if (element is JsonArray) {
            for (item in element) {
                val found = findHeaderRenderer(item)
                if (found != null) return found
            }
        }
        return null
    }
}
