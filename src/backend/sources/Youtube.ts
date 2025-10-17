import fetch from 'node-fetch'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { URLSearchParams } from 'node:url'
import { youtubeAccessType, youtubeSavedCredentials } from '../utils/types'
import { spawn } from 'node:child_process'
import { mainWindow } from '../../main'
// eslint-disable-next-line import/no-unresolved
import { Innertube, ClientType, YTNodes } from 'youtubei.js'
import { loadCredentials } from '../Credentials'
import { ytDlpManager } from '../utils/YtDlpManager'
import { GenericExtractor } from './Generic'
import { queryCache } from '../QueryCache'
import { GenericSimpleAlbum, GenericSimpleArtist, GenericSimpleUser, GenericSong, GenericUser } from '../../common/types/SongTypes'
import { GenericSearch } from '../../common/types/SourcesTypes'

const SONG_CACHE_DIR = path.join(app.getPath('userData'), 'Cache', 'Downloads', 'Songs', 'youtube')
const TOKEN_FILE_PATH = path.join(app.getPath('userData'), 'youtube_tokens.json')
const REDIRECT_URI = "http://127.0.0.1:8080/callback"

export type YoutubeSongType = {
    etag: string,
    id: {
        kind: "youtube#video",
        videoId: string,
    },
    kind: "youtube#searchResult",
    snippet: YoutubeSnippetType
}

export type YoutubeSnippetType = {
    channelId: string,
    channelTitle: string,
    description: string,
    liveBroadcastContent: string,
    publishTime: string,
    publishedAt: string,
    thumbnails: {
        default: YoutubeThumbnailType,
        high: YoutubeThumbnailType,
        medium: YoutubeThumbnailType,
    },
    title: string
}

export type YoutubeThumbnailType = {
    height: number,
    url: string,
    width: number
}

export type YoutubeSearchType = {
    etag: string,
    items: YoutubeSongType[],
    kind: string,
    nextPageToken: string,
    pageInfo: {
        resultsPerPage: number,
        totalResults: number
    },
    regionCode: string
}

export type YoutubeChannelType = {
    kind: "youtube#channelListResponse",
    etag: string,
    pageInfo: {
        totalResults: number,
        resultsPerPage: number
    },
    items: [
        {
            kind: "youtube#channel",
            etag: string,
            id: string,
            snippet: {
                title: string,
                description: string,
                customUrl: string,
                publishedAt: string,
                thumbnails: {
                    default: YoutubeThumbnailType,
                    medium: YoutubeThumbnailType,
                    high: YoutubeThumbnailType
                },
                localized: {
                    title: string,
                    description: string
                },
                country: string
            }
        }
    ]
}

type SearchResult = 
    | { source: 'api', data: YoutubeSearchType }
    | { source: 'innertube', data: InnertubeSearchResult }

type InnertubeSearchResult = Awaited<ReturnType<YoutubeExtractor['innertubeSearch']>>

class YoutubeExtractor extends GenericExtractor {
    private clientId: string;
    private clientSecret: string;
    private innertube: Innertube | undefined;
    private initPromise: Promise<void>;

    constructor() {
        super()
        this.initPromise = this.initialize()
    }

    private async initialize() {
        const credentials = await loadCredentials()
        if (!credentials || !credentials.youtubeClientId || !credentials.youtubeClientSecret) {
            throw new Error('YouTube credentials not found')
        }
        this.clientId = credentials.youtubeClientId
        this.clientSecret = credentials.youtubeClientSecret

        // Initialize Innertube
        this.innertube = await Innertube.create({
            client_type: ClientType.WEB,
            device_category: "desktop",
            user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            player_id: "0004de42"
        })
    }

    private async ensureInitialized() {
        await this.initPromise
    }

    async getAccess(code: string): Promise<youtubeAccessType> {
        await this.ensureInitialized()

        const response = await fetch('https://oauth2.googleapis.com/token', {
            method: "POST",
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                code,
                client_id: this.clientId,
                client_secret: this.clientSecret,
                redirect_uri: REDIRECT_URI,
                grant_type: 'authorization_code'
            }),
        })

        const data = await response.json() as youtubeAccessType
        
        // Save tokens immediately after getting them
        if (data.access_token) {
            await this.saveTokens(data)
        }

        return data
    }

    private async refreshAccess(): Promise<string> {
        await this.ensureInitialized()

        const credentials = await this.loadTokens()
        const response = await fetch('https://oauth2.googleapis.com/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                client_id: this.clientId,
                client_secret: this.clientSecret,
                refresh_token: credentials.refresh_token,
                grant_type: 'refresh_token'
            })
        })

        const data = await response.json() as youtubeAccessType

        if (data.access_token) {
            if (!data.refresh_token) {
                data.refresh_token = credentials.refresh_token
            }
            await this.saveTokens(data)
        }

        return data.access_token
    }

    async saveTokens(tokens: youtubeAccessType) {
        const data: youtubeSavedCredentials = {
            ...tokens,
            expires_at: Date.now() + tokens.expires_in * 1000
        }

        await fs.promises.writeFile(TOKEN_FILE_PATH, JSON.stringify(data, null, 2))
    }

    private async getValidAccessToken(): Promise<string> {
        const credentials = await this.loadTokens()
        if (!credentials) {
            throw new Error("No Youtube credentials found")
        }
        
        if (credentials.expires_at <= Date.now()) {
            return await this.refreshAccess()
        }
        
        return credentials.access_token
    }

    async loadTokens(): Promise<youtubeSavedCredentials> {
        try {
            const data = await fs.promises.readFile(TOKEN_FILE_PATH, 'utf-8');
            return JSON.parse(data)
        } catch(err) {
            return null
        }
    }

    async isLoggedIn(): Promise<{ loggedIn: boolean, expired: boolean}> {
        const data = await this.loadTokens()
        if (!data || !data.access_token || !data.refresh_token) {
            return { loggedIn: false, expired: true }
        }
        
        const now = Date.now()
        const expired = data.expires_at <= now
        
        return { loggedIn: true, expired }
    }

    private async youtubeApiSearch(searchQuery: string): Promise<YoutubeSearchType> {
        const type = "video"
        const maxResults = 10

        const access_token = await this.getValidAccessToken()
        const searchUrl = `https://www.googleapis.com/youtube/v3/search?part=snippet&q=${encodeURIComponent(searchQuery)}&type=${encodeURIComponent(type)}&maxResults=${encodeURIComponent(maxResults)}`

        const response = await fetch(searchUrl, {
            headers: {
                'Authorization': `Bearer ${access_token}`,
                'Accept': 'application/json'
            }
        });

        if (response.status === 403) {
            throw new Error(response.statusText)
        }

        return await response.json() as YoutubeSearchType
    }

    private async innertubeSearch(searchQuery: string) {
        await this.ensureInitialized()
        return await this.innertube.search(searchQuery, { type: "video" })
    }

    private async downloadSearch(searchQuery: string): Promise<SearchResult> {
        try {
            const results = await this.youtubeApiSearch(searchQuery)
            return { source: 'api', data: results }
        } catch (error) {
            console.log('Youtube Data API failed, falling back to Innertube:', error.code)
            const results = await this.innertubeSearch(searchQuery)
            return { source: 'innertube', data: results }
        }
    }

    async search(searchQuery: string): Promise<GenericSearch> {
        try {
            const results = await this.youtubeApiSearch(searchQuery)

            const songs: GenericSong[] = results.items.map(item => {
                return new GenericSong(
                    item.snippet.title,
                    [new GenericSimpleArtist(item.snippet.channelId, `youtube`, item.snippet.channelTitle, item.snippet.thumbnails?.high?.url || '')],
                    false,
                    0,
                    "youtube",
                    item.id.videoId,
                    item.snippet.thumbnails.high?.url || '',
                )
            })

            return {
                songs: songs
            }
        } catch (error) {
            console.log('Youtube Data API failed, falling back to Innertube:', error.code)
            const results = await this.innertubeSearch(searchQuery)
            const searchArray = results.results.filterType(YTNodes.Video)
            const songs: GenericSong[] = searchArray.map(item => (
                new GenericSong(
                    item.title.toString(),
                    [new GenericSimpleArtist(item.author.id, `youtube`, item.author.name, item.author.thumbnails?.[0]?.url || '')],
                    false,
                    item.duration?.seconds || 0,
                    "youtube",
                    item.video_id,
                    item.best_thumbnail.url || '',
                )
            ))

            return {
                songs: songs
            }
        }
    }

    private isTitleMatch(query: string, title: string): boolean {
        const songName = query.toLowerCase().split("-")[0].trim()

        if (songName === title.toLowerCase()) {
            return true
        }

        const normalize = (str: string) =>
            str.toLowerCase().replace(/[^a-z0-9 ]/gi, '').split(' ').filter(Boolean);
        
        const queryWords = normalize(query);
        const titleWords = normalize(title);
        
        const matchCount = queryWords.filter(word => titleWords.includes(word)).length;
        
        return matchCount >= Math.max(1, Math.floor(queryWords.length * 0.7)); // 70% match
    }

    private isValidMusicVideo(title: string, channel: string, description: string): boolean {
        const titleLower = title.toLowerCase()
        const channelLower = channel.toLowerCase()
        const descriptionLower = description.toLowerCase()

        if (descriptionLower.includes("official audio") ||
            // Most reliable indicator that the audio is official
            descriptionLower.includes("provided to youtube by")) {
            return true
        }

        if (descriptionLower.includes("perform")) {
            return false
        }

        // Avoid live, cover, remix, etc.
        const excludeTerms = ["live", "remix", "cover", "performance", 
                              "old version", "single version", "unreleased", "official video"]
        if (excludeTerms.some(term => titleLower.includes(term))) {
            return false
        }

        // Prefer official audio/topic/artist channels
        if (titleLower.includes("official audio") || 
            channelLower.includes("topic") || 
            channelLower.includes("official")) {
            return true
        }

        return true
    }

    async downloadAudio(type: "url" | "terms", url: string) {
        const originalSearchTerms = url
        let downloadId = ""
        
        switch (type) {
            case "url": {
                downloadId = url
                break
            }
            default:
            case "terms": {
                // Check cache first
                const cachedId = await queryCache.get(url)
                if (cachedId) {
                    downloadId = cachedId
                    console.log(`Using cached YouTube ID for "${url}": ${downloadId}`)
                    break
                }

                // Cache miss - perform search
                const searchResults = await this.downloadSearch(url)

                switch (searchResults.source) {
                    case "api": {
                        const probableSongs = searchResults.data.items.filter(item => {
                            // Must be a video
                            if (item.id.kind !== "youtube#video") return false;
                            
                            const title = item.snippet.title;
                            const channel = item.snippet.channelTitle;
                            const description = item.snippet.description;

                            // Title must match query
                            if (!this.isTitleMatch(url, title)) return false;
        
                            // Check if it's a valid music video
                            return this.isValidMusicVideo(title, channel, description)
                        });
        
                        // Pick the best match or fallback to first item
                        const bestSong = probableSongs[0] || searchResults.data.items[0];
                        if (bestSong?.id?.videoId) {
                            downloadId = bestSong.id.videoId;
                        }
                        break
                    }
                    case 'innertube': {
                        const searchArray = searchResults.data.results.filterType(YTNodes.Video)

                        const probableSongs = searchArray.filter((item) => {
                            const title = item.title.toString();
                            const channel = item.author.name;
                            const description = item.description || "";
            
                            // Title must match query
                            if (!this.isTitleMatch(url, title)) return false;
            
                            // Check if it's a valid music video
                            return this.isValidMusicVideo(title, channel, description)
                        });
            
                        // Pick the best match or fallback to first item
                        const bestSong = probableSongs[0] || searchArray[0];
                        if (bestSong?.video_id) {
                            downloadId = bestSong.video_id;
                        }
                        break
                    }
                }
                break
            }
        }

        const downloadPath = path.join(SONG_CACHE_DIR, `${downloadId}.ogg`)
        console.log(downloadPath)

        let alreadyDownloaded = false;
        if (fs.existsSync(downloadPath)) {
            alreadyDownloaded = true;

            // Cache this mapping if it was a search query
            if (type === "terms") {
                try {
                    await queryCache.set(originalSearchTerms, downloadId)
                } catch (error) {
                    console.error('Failed to cache query:', error)
                }
            }

            mainWindow.webContents.send('youtube-download-status', {
                status: 'done',
                downloadPath: downloadPath,
                downloadId: downloadId,
                searchTerms: originalSearchTerms,
                message: `was already downloaded`,
            });
        } else {
            let ytDlpPath: string
            let ffmpegPath: string
            let binDir: string
            
            try {
                const paths = await ytDlpManager.ensureBoth()
                ytDlpPath = paths.ytDlpPath
                ffmpegPath = paths.ffmpegPath
                binDir = ytDlpManager.getBinDir()
                console.log(`Using yt-dlp at: ${ytDlpPath}`)
                console.log(`Using ffmpeg at: ${ffmpegPath}`)
            } catch (error) {
                console.error('Failed to get yt-dlp/ffmpeg:', error)
                mainWindow.webContents.send('youtube-download-status', {
                    status: 'error',
                    downloadPath,
                    downloadId,
                    searchTerms: originalSearchTerms,
                    message: `Failed to initialize yt-dlp/ffmpeg: ${error.message}`,
                });
                return { downloaded: false, downloadPath }
            }

            // Set up environment to include our bin directory in PATH
            const env = { ...process.env }
            const pathSeparator = process.platform === 'win32' ? ';' : ':'
            env.PATH = `${binDir}${pathSeparator}${env.PATH || ''}`

            const ytdlp = spawn(ytDlpPath, [
                '-P', SONG_CACHE_DIR,
                '-o', '%(id)s.%(ext)s',
                `https://www.youtube.com/watch?v=${downloadId}`,
                '-f', 'ba',
                '-S', 'acodec:opus',
                '--remux-video', 'ogg',
                '--ffmpeg-location', ffmpegPath
            ], { env });

            ytdlp.stdout.on('data', (data) => {
                mainWindow.webContents.send('youtube-download-status', {
                    status: 'downloading',
                    downloadId,
                    searchTerms: originalSearchTerms,
                    downloadPath,
                    message: data.toString(),
                });
                console.log(`yt-dlp: ${data}`);
            });

            ytdlp.stderr.on('data', (data) => {
                mainWindow.webContents.send('youtube-download-status', {
                    status: 'error',
                    downloadId,
                    searchTerms: originalSearchTerms,
                    downloadPath,
                    message: data.toString(),
                });
                console.log(`yt-dlp error: ${data}`);
            });

            ytdlp.on('close', async (code) => {
                // On successful download (code 0), cache the search terms -> video ID mapping
                if (code === 0 && type === "terms") {
                    try {
                        await queryCache.set(originalSearchTerms, downloadId)
                    } catch (error) {
                        console.error('Failed to cache query:', error)
                    }
                }

                mainWindow.webContents.send('youtube-download-status', {
                    status: 'done',
                    downloadId,
                    searchTerms: originalSearchTerms,
                    downloadPath,
                    message: `code: ${code}`,
                });
                console.log(`yt-dlp process exited with code ${code}`);
            });
        }

        return { downloaded: alreadyDownloaded, downloadPath };
    }

    async getUserInfo() {
        const access_token = await this.getValidAccessToken();
        const searchUrl = `https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true`;

        const response = await fetch(searchUrl, {
            headers: {
                'Authorization': `Bearer ${access_token}`,
                'Accept': 'application/json'
            }
        });

        
        if (response.status === 403) {
            console.log("Failed to get user info:", response.statusText);
        }

        const responseJson = await response.json() as YoutubeChannelType

        const channel = responseJson.items[0];
        return {
            source: 'youtube',
            id: channel.id,
            displayName: channel.snippet.title,
            description: channel.snippet.description || '',
            country: channel.snippet.country || '',
            avatarURL: channel.snippet.thumbnails?.high?.url || '',
            profileURL: `https://www.youtube.com/channel/${channel.snippet.customUrl || channel.id}`,
        } as GenericUser
    }
}

export const youtubeExtractor = new YoutubeExtractor()
export type { SearchResult }