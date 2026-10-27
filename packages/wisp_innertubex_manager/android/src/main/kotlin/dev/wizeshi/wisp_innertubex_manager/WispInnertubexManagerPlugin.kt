package dev.wizeshi.wisp_innertubex_manager

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** WispInnertubexManagerPlugin */
class WispInnertubexManagerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.Main)

    private val sessionCookies = mutableMapOf<String, String>()

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
                            // High bitrate fallback / format resolution on Android
                            mapOf(
                                "url" to "https://rr---sn-4g5ednss.googlevideo.com/videoplayback?id=$videoId",
                                "format" to "opus",
                                "bitrate" to 160000,
                                "isSabr" to false
                            )
                        }
                        result.success(streamResult)
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
                            listOf<Map<String, Any?>>()
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
                            mapOf(
                                "id" to videoId,
                                "title" to "Unknown Track",
                                "artist" to "Unknown Artist",
                                "duration" to 0L,
                                "thumbnails" to emptyList<String>()
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
                            mapOf(
                                "browseId" to browseId,
                                "title" to "",
                                "artist" to "",
                                "tracks" to emptyList<Map<String, Any?>>()
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
                            mapOf(
                                "browseId" to browseId,
                                "name" to "",
                                "topTracks" to emptyList<Map<String, Any?>>()
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
                            mapOf(
                                "browseId" to browseId,
                                "title" to "",
                                "tracks" to emptyList<Map<String, Any?>>()
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
                sessionCookies.clear()
                sessionCookies.putAll(cookies)
                val isLoggedIn = sessionCookies.containsKey("SAPISID") || sessionCookies.containsKey("SSID")
                result.success(
                    mapOf(
                        "isLoggedIn" to isLoggedIn,
                        "accountName" to if (isLoggedIn) "YouTube Music User" else null
                    )
                )
            }

            "getAuthStatus" -> {
                val isLoggedIn = sessionCookies.containsKey("SAPISID") || sessionCookies.containsKey("SSID")
                result.success(
                    mapOf(
                        "isLoggedIn" to isLoggedIn,
                        "accountName" to if (isLoggedIn) "YouTube Music User" else null
                    )
                )
            }

            "clearSession" -> {
                sessionCookies.clear()
                result.success(
                    mapOf(
                        "isLoggedIn" to false,
                        "accountName" to null
                    )
                )
            }

            "getLikedTracks" -> {
                result.success(emptyList<Map<String, Any?>>())
            }

            else -> result.notImplemented()
        }
    }
}
