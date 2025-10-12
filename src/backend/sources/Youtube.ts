import fetch from 'node-fetch'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { youtubeSearchType } from '../../frontend/types/SongTypes'
import { URLSearchParams } from 'node:url'
import { youtubeAccessType, youtubeSavedCredentials } from '../utils/types'
import { spawn } from 'node:child_process'
import { mainWindow } from '../../main'
// eslint-disable-next-line import/no-unresolved
import { Innertube, ClientType, YTNodes } from 'youtubei.js'
import { loadCredentials } from '../Credentials'
import { ytDlpManager } from '../utils/YtDlpManager'

const songFileLocations = path.join(app.getPath('userData'), 'songCache')
const tokenFilePath = path.join(app.getPath('userData'), 'youtube_tokens.json')

const redirect_uri = "http://127.0.0.1:8080/callback"

let innertube: Innertube | undefined;
(async () => {
    innertube = await Innertube.create({
        client_type: ClientType.WEB,
        device_category: "desktop",
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        player_id: "0004de42"
    })
})()

export const getYoutubeAccess = async (code: string) => {
    const credentials = await loadCredentials()
    if (!credentials || !credentials.youtubeClientId || !credentials.youtubeClientSecret) {
        throw new Error('YouTube credentials not found')
    }

    const response = await fetch('https://oauth2.googleapis.com/token', {
        method: "POST",
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            code,
            client_id: credentials.youtubeClientId,
            client_secret: credentials.youtubeClientSecret,
            redirect_uri,
            grant_type: 'authorization_code'
        }),
    })

    const data = await response.json()

    return (data as youtubeAccessType)
}

const refreshYoutubeAccess = async () => {
    const apiCredentials = await loadCredentials()
    if (!apiCredentials || !apiCredentials.youtubeClientId || !apiCredentials.youtubeClientSecret) {
        throw new Error('YouTube credentials not found')
    }

    const credentials = await loadYoutubeCredentials()
    const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            client_id: apiCredentials.youtubeClientId,
            client_secret: apiCredentials.youtubeClientSecret,
            refresh_token: credentials.refresh_token,
            grant_type: 'refresh_token'
        })
    })

    const data = (await response.json() as youtubeAccessType)

    if (data.access_token) {
        if (!data.refresh_token) data.refresh_token = credentials.refresh_token
        await saveYoutubeCredentials({ ...credentials, ...data })
    }

    return data.access_token
}

export const saveYoutubeCredentials = async (tokens: youtubeAccessType) => {
    const expires_at = Date.now() + tokens.expires_in * 1000
    
    const data = {
        ...tokens,
        expires_at
    }

    await fs.promises.writeFile(tokenFilePath, JSON.stringify(data, null, 2))
}

export const getValidYoutubeAccessToken = async () => {
    const credentials = await loadYoutubeCredentials()
    if (!credentials) throw new Error("No Youtube credentials found")
    if (credentials.expires_at <= Date.now()) {
        return await refreshYoutubeAccess()
    }
    return credentials.access_token
}

export const loadYoutubeCredentials = async (): Promise<youtubeSavedCredentials> => {
    try {
        const data = await fs.promises.readFile(tokenFilePath, 'utf-8');
        return JSON.parse(data)
    } catch(err) {
        return null
    }
}

export const isYoutubeLoggedIn = async (): Promise<{ loggedIn: boolean, expired: boolean}> => {
    try {
        const data = await loadYoutubeCredentials()
        const now = Date.now()
        if (data.access_token && data.refresh_token && (data.expires_at > now)) {
            return { loggedIn: true, expired: false }
        } else if (data.access_token && data.refresh_token) {
            return { loggedIn: true, expired: true }
        }
    } catch (err) {
        return { loggedIn: false, expired: true }
    }
}

type SearchResult = 
    | { source: 'api', data: youtubeSearchType }
    | { source: 'innertube', data: InnertubeSearchResult }

const youtubeSearch = async (searchQuery: string) => {
        const type = "video"
        const maxResults = 10

        const access_token = await getValidYoutubeAccessToken()
        const searchUrl = "https://www.googleapis.com/youtube/v3/search?" +
                "part=snippet" +
                `&q=${encodeURIComponent(searchQuery)}` +
                `&type=${encodeURIComponent(type)}` +
                `&maxResults=${encodeURIComponent(maxResults)}`

        const response = await fetch(
                searchUrl,
                {
                        headers: {
                                'Authorization' : `Bearer ${access_token}`,
                                'Accept': 'application/json'
                        }
                }
        );

        if (response.status == 403) {
            throw new Error(response.statusText)
        }

        const data = (await response.json() as youtubeSearchType)

        return data
}

const innertubeSearch = async (searchQuery: string) => {
    const type = "video"

    const data = await innertube.search(searchQuery, {type: type})

    return data
}

type InnertubeSearchResult = Awaited<ReturnType<typeof innertubeSearch>>

export const searchYoutube = async (searchQuery: string): Promise<SearchResult> => {
    try {
        const results = await youtubeSearch(searchQuery)
        return { source: 'api', data: results }
    } catch (error) {
        console.log('Youtube Data API failed, falling back to Innertube:', error.code)
        const results = await innertubeSearch(searchQuery)
        return { source: 'innertube', data: results }
    }
}

export const downloadYoutubeAudio = async ( 
    type: "url" | "terms", 
    url: string 
) => {
    const originalSearchTerms = url // Store the original search terms
    let downloadId = ""
    
    switch (type) {
        case "url": {
            downloadId = url
            break
        }
        default:
        case "terms": {
            const searchResults = await searchYoutube(url)

            // Helper for loose title matching
            const isTitleMatch = (query: string, title: string) => {
                const normalize = (str: string) =>
                    str.toLowerCase().replace(/[^a-z0-9 ]/gi, '').split(' ').filter(Boolean);
                
                const queryWords = normalize(query);
                const titleWords = normalize(title);
                
                const matchCount = queryWords.filter(word => titleWords.includes(word)).length;
                
                return matchCount >= Math.max(1, Math.floor(queryWords.length * 0.7)); // 70% match
            }

            switch (searchResults.source) {
                case "api": {
                    // Filter for most probable song
                    const probableSongs = searchResults.data.items.filter(item => {
                        const title = item.snippet.title;
                        const channel = item.snippet.channelTitle.toLowerCase();
        
                        // 1. Title must loosely match the query
                        if (!isTitleMatch(url, title)) return false;
        
                        // 2. Must be a video
                        if (item.id.kind != "youtube#video") return false;
        
                        // 3. Prefer official audio/topic/artist channels
                        if (title.toLowerCase().includes("official audio") || 
                            channel.includes("topic") || 
                            channel.includes("official")) return true;
        
                        // 4. Avoid live, cover, remix, etc.
                        if (title.toLowerCase().includes("live") || 
                            title.toLowerCase().includes("remix") || 
                            title.toLowerCase().includes("cover") || 
                            title.toLowerCase().includes("performance") ||
                            title.toLowerCase().includes("old version") ||
                            title.toLowerCase().includes("single version") ||
                            title.toLowerCase().includes("unreleased") ||
                            title.toLowerCase().includes("official video")) return false;
        
                        // 5. Otherwise, allow if it looks like a music video
                        return true;
                    });
        
                    // Pick the best match or fallback to first item
                    const bestSong = probableSongs[0] || searchResults.data.items[0];
                    if (bestSong && bestSong.id && bestSong.id.videoId) {
                        downloadId = `${bestSong.id.videoId}`;
                    }
                    break
                }
                case 'innertube': {
                    // Filter for most probable 
                    const searchArray = searchResults.data.results.filterType(YTNodes.Video)

                    const probableSongs = searchArray.filter(item => {
                        const title = item.title.toString();
                        const channel = item.author.name.toLowerCase();
        
                        // 1. Title must loosely match the query
                        if (!isTitleMatch(url, title)) return false;
        
                        // 2. Prefer official audio/topic/artist channels
                        if (title.toLowerCase().includes("official audio") || 
                            channel.includes("topic") || 
                            channel.includes("official")) return true;
        
                        // 3. Avoid live, cover, remix, etc.
                        if (title.toLowerCase().includes("live") || 
                            title.toLowerCase().includes("remix") || 
                            title.toLowerCase().includes("cover") || 
                            title.toLowerCase().includes("performance") ||
                            title.toLowerCase().includes("old version") ||
                            title.toLowerCase().includes("single version") ||
                            title.toLowerCase().includes("unreleased") ||
                            title.toLowerCase().includes("official video")) return false;
        
                        // 4. Otherwise, allow if it looks like a music video
                        return true;
                    });
        
                    // Pick the best match or fallback to first item
                    const bestSong = probableSongs[0] || searchArray[0];
                    if (bestSong && bestSong.video_id) {
                        downloadId = `${bestSong.video_id}`;
                    }
                    break
                }
            }
            break
        }
    }

    const downloadPath = path.join(songFileLocations, `${downloadId}.ogg`)
    console.log(downloadPath)

    let alreadyDownloaded = false;
    if (fs.existsSync(downloadPath)) {
        alreadyDownloaded = true;

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
                downloadPath: downloadPath,
                downloadId: downloadId,
                searchTerms: originalSearchTerms,
                message: `Failed to initialize yt-dlp/ffmpeg: ${error.message}`,
            });
            return { downloaded: false, downloadPath }
        }

        // Set up environment to include our bin directory in PATH
        // This allows yt-dlp to find ffmpeg
        const env = { ...process.env }
        const pathSeparator = process.platform === 'win32' ? ';' : ':'
        env.PATH = `${binDir}${pathSeparator}${env.PATH || ''}`

        const ytdlp = spawn(ytDlpPath, [
            '-P', songFileLocations,
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
                downloadId: downloadId,
                searchTerms: originalSearchTerms,
                downloadPath: downloadPath,
                message: data.toString(),
            });
            console.log(`yt-dlp: ${data}`);
        });

        ytdlp.stderr.on('data', (data) => {
            mainWindow.webContents.send('youtube-download-status', {
                status: 'error',
                downloadId: downloadId,
                searchTerms: originalSearchTerms,
                downloadPath: downloadPath,
                message: data.toString(),
            });
            console.log(`yt-dlp error: ${data}`);
        });

        ytdlp.on('close', (code) => {
            mainWindow.webContents.send('youtube-download-status', {
                status: 'done',
                downloadId: downloadId,
                searchTerms: originalSearchTerms,
                downloadPath: downloadPath,
                message: `code: ${code}`,
            });
            console.log(`yt-dlp process exited with code ${code}`);
        });
    }

    return { downloaded: alreadyDownloaded, downloadPath };
}