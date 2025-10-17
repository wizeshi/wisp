import path from 'node:path';
import { createServer, Server } from 'node:http';
import dns from 'dns';
import { app, BrowserWindow, ipcMain, shell, protocol, net, dialog, session } from 'electron';
import started from 'electron-squirrel-startup';
import { spotifyExtractor } from './backend/sources/Spotify';
import { youtubeExtractor } from './backend/sources/Youtube';
import * as Common from './backend/sources/Common';
import { ytDlpManager } from './backend/utils/YtDlpManager';
import { loadSettings, saveSettings } from './backend/Settings';
import { loadData, saveData } from './backend/Data';
import { deleteCredentials, hasCredentials, loadCredentials, saveCredentials, validateCredentials } from './backend/Credentials';
import { APICredentials, UserData, UserSettings } from './backend/utils/types';
import { GenericSong, GenericPlaylist, GenericAlbum, SidebarListType, SongSources } from './common/types/SongTypes';
import { getLyrics } from './backend/lyrics/Common';
import { LyricsSources } from './common/types/LyricsTypes';
import { queryCache } from './backend/QueryCache';
import { localManager } from './backend/LocalManager';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
    app.quit();
}

export let mainWindow: BrowserWindow | null = null
let youtubeOAuthServer: Server | null = null

protocol.registerSchemesAsPrivileged([
    { scheme: 'wisp-audio', privileges: { secure: true, standard: true, supportFetchAPI: true, stream: true, bypassCSP: true } }
])

if (process.defaultApp) {
    if (process.argv.length >= 2) {
        app.setAsDefaultProtocolClient('wisp-login', process.execPath, [path.resolve(process.argv[1])])
    }
} else {
    app.setAsDefaultProtocolClient('wisp-login')
}

app.whenReady().then(async () => {
    protocol.handle('wisp-audio', async request => {
        const requestUrl = request.url.replace('wisp-audio://', '')
        const filePath = `file:///${requestUrl.charAt(0) + ':' + requestUrl.slice(1)}`;

        return net.fetch(filePath)
    });

    mainWindow = new BrowserWindow({
        minWidth: 1154,
        width: 1154,
        minHeight: 665,
        height: 665,
        titleBarStyle: "hidden",
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
        icon: path.join(__dirname, '../assets/wisp.ico')
    });

    if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
        mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
        mainWindow.webContents.openDevTools();
    } else {
        mainWindow.loadFile(
            path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
        );
    }

    await session.defaultSession.extensions.loadExtension("C:/Users/wizeshi/AppData/Local/Google/Chrome/User Data/Default/Extensions/fmkadmapgofadopljbjfkapdkoienihi/7.0.0_0")

    ipcMain.on("login:youtube-login", async () => {
        try {
            const credentials = await loadCredentials()
            if (!credentials || !credentials.youtubeClientId) {
                mainWindow.webContents.send('login:youtube-error', 'No YouTube credentials found. Please complete setup first.')
                return
            }

            const clientId = credentials.youtubeClientId
            const redirectUri = "http://127.0.0.1:8080/callback"
            const scopes = [
                "https://www.googleapis.com/auth/youtube.readonly"
            ].join(" ")

            const authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" +
                `&client_id=${encodeURIComponent(clientId)}` +
                `&redirect_uri=${encodeURIComponent(redirectUri)}` +
                `&response_type=code` + 
                `&scope=${encodeURIComponent(scopes)}` +
                `&access_type=offline` +
                `&prompt=consent` +
                `&state=youtube`
        
            if (youtubeOAuthServer) {
                youtubeOAuthServer.close()
                youtubeOAuthServer = null
            }

            youtubeOAuthServer = createServer((req, res) => {
                const url = new URL(req.url, 'http://127.0.0.1:8080')
                const code = url.searchParams.get('code')

                if (code) {
                    res.writeHead(200, { 'Content-Type': 'text/html' })
                    res.end('<h1>Success! You can close this window.</h1><script>window.close()</script>')
                    
                    youtubeExtractor.getAccess(code).then(async (access) => {
                        await youtubeExtractor.saveTokens(access)

                        mainWindow.webContents.send('login:youtube-success')
                    }).catch((err: Error) => {
                        console.error('Failed to get YouTube access:', err)
                        mainWindow.webContents.send('login:youtube-error', err.message)
                    })
                    
                    if (youtubeOAuthServer) {
                        youtubeOAuthServer.close()
                        youtubeOAuthServer = null
                    }
                }
            })
        
        youtubeOAuthServer.on('error', (err) => {
            console.error('OAuth server error:', err)
            youtubeOAuthServer = null
        })

        youtubeOAuthServer.listen(8080, () => {
            shell.openExternal(authUrl)
        })
        
        } catch (error) {
            console.error('YouTube login error:', error)
            mainWindow.webContents.send('login:youtube-error', error.message)
        }
    })

    ipcMain.on("login:spotify-login", async () => {
        try {
            const credentials = await loadCredentials()
            if (!credentials || !credentials.spotifyClientId) {
                mainWindow.webContents.send('login:spotify-error', 'No Spotify credentials found. Please complete setup first.')
                return
            }

            const clientId = credentials.spotifyClientId
            const redirectUri = "wisp-login://callback"
            const scopes = [
                "playlist-read-private",
                "playlist-read-collaborative",
                "user-follow-read",
                "user-top-read",
                "user-read-recently-played",
                "user-library-read"
            ].join(" ");

            const authUrl = `https://accounts.spotify.com/authorize?response_type=code&client_id=${encodeURIComponent(clientId)}&scope=${encodeURIComponent(scopes)}&redirect_uri=${encodeURIComponent(redirectUri)}&state=spotify`;

            shell.openExternal(authUrl)
        } catch (error) {
            console.error('Spotify login error:', error)
            mainWindow.webContents.send('login:spotify-error', error.message)
        }
    })
    
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        shell.openExternal(url)
        return { action: 'deny' }
    })
})

app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");

// Quit when all windows are closed.
app.on('window-all-closed', () => {
    app.quit();
});

app.on('open-url', (event, url) => {
    event.preventDefault()
    handleOAuthCallback(url)
})

const gotTheLock = app.requestSingleInstanceLock()
if (!gotTheLock) {
    app.quit()
} else {
    app.on('second-instance', (event, commandLine) => {
        const url = commandLine.find(arg => arg.startsWith('wisp-login://'))
        if (url) {
            handleOAuthCallback(url)
        }

        if (mainWindow) {
            if (mainWindow.isMinimized()) mainWindow.restore()
            mainWindow.focus()
        }
    })
}

function handleOAuthCallback(url: string) {
    const urlObj = new URL(url)
    const code = urlObj.searchParams.get('code')
    const state = urlObj.searchParams.get('state')

    if (mainWindow && code) {
        switch (state) {
            case "spotify":
                spotifyExtractor.getAccess(code).then(async (access) => {                    
                    await spotifyExtractor.saveTokens(access)

                    mainWindow.webContents.send('login:spotify-success')
                }).catch((err: Error) => {
                    console.error('Failed to get Spotify access:', err)
                    mainWindow.webContents.send('login:spotify-error', err.message)
                })
                break
            case "youtube":
                // This case probably won't happen since YouTube uses localhost, but keep bc why not
                youtubeExtractor.getAccess(code).then(async (access) => {
                    await youtubeExtractor.saveTokens(access)

                    mainWindow.webContents.send('login:youtube-success')
                }).catch((err: Error) => {
                    console.error('Failed to get YouTube access:', err)
                    mainWindow.webContents.send('login:youtube-error', err.message)
                })
                break
        }
    }
}

ipcMain.handle("window:minimize", () => {
    mainWindow.minimize()
})

ipcMain.handle("window:maximize", () => {
    if (mainWindow.isMaximized()) mainWindow.unmaximize()
    else mainWindow.maximize()
})

ipcMain.handle("window:isMaximized", () => {
    return mainWindow.isMaximized() ?? false
})

ipcMain.handle("window:close", () => {
    mainWindow.close()
})

ipcMain.handle("extractors:search", (_event, searchQuery: string, source?: SongSources) => {
    return Common.search(searchQuery, source)
})

ipcMain.handle("extractors:user-lists", (_event, type: SidebarListType, source?: SongSources) => {
    return Common.getUserLists(type, source)
})

ipcMain.handle('extractors:user-info', (_event, source?: SongSources) => {
    return Common.getUserInfo(source)
})

ipcMain.handle('extractors:user-details', (_event, id: string, source?: SongSources) => {
    return Common.getUserDetails(id, source)
})

ipcMain.handle('extractors:list-details', (_event, type: "Album" | "Playlist" | "Artist", id: string, source?: SongSources) => {
    return Common.getListDetails(type, id, source)
})

ipcMain.handle('extractors:force-refresh-list', (_event, type: "Album" | "Playlist", id: string, source?: SongSources) => {
    return Common.forceRefreshListDetails(type, id, source)
})

ipcMain.handle('extractors:artist-info', (_event, id: string, source?: SongSources) => {
    return Common.getArtistInfo(id, source)
})

ipcMain.handle('extractors:artist-details', (_event, id: string, source?: SongSources) => {
    return Common.getArtistDetails(id, source)
})

ipcMain.handle('extractors:user-home', (_event, source?: SongSources) => {
    return Common.getUserHome(source)
})

ipcMain.handle("extractors:youtube-download", (_event, type: "url" | "terms", searchQuery: string) => {
    return youtubeExtractor.downloadAudio(type, searchQuery)
})

ipcMain.handle("extractors:saved-songs", (_event, source?: SongSources, offset?: number) => {
    return Common.getSavedSongs(source, offset)
})

ipcMain.handle("login:is-logged-in", (_event, source: SongSources) => {
    const extractor = Common.getSourceExtractor(source)
    return extractor.isLoggedIn()
})

ipcMain.handle("extractors:lyrics-get", (event, song: GenericSong, source?: LyricsSources) => {
    return getLyrics(song, source)
})

// Local file management handlers
ipcMain.handle('local:select-audio-files', async () => {
    if (!mainWindow) {
        return []
    }
    
    const result = await dialog.showOpenDialog(mainWindow, {
        properties: ['openFile', 'multiSelections'],
        filters: [
            { name: 'Audio Files', extensions: ['mp3', 'flac', 'm4a', 'ogg', 'wav', 'aac', 'opus', 'wma'] }
        ]
    }) as unknown as { canceled: boolean; filePaths: string[] }
    
    return result.canceled ? [] : result.filePaths
})

ipcMain.handle('local:import-audio-file', async (_event, filePath: string) => {
    return await localManager.importLocalAudioFileWithMetadata(filePath)
})

ipcMain.handle('local:import-audio-files', async (_event, filePaths: string[]) => {
    const songs = []
    for (const filePath of filePaths) {
        try {
            const song = await localManager.importLocalAudioFileWithMetadata(filePath)
            songs.push(song)
        } catch (error) {
            console.error(`Failed to import ${filePath}:`, error)
        }
    }
    return songs
})

ipcMain.handle('local:get-audio-path', async (_event, songId: string) => {
    return await localManager.getLocalAudioPath(songId)
})

ipcMain.handle('local:delete-song', async (_event, songId: string) => {
    return await localManager.deleteLocalSong(songId)
})

ipcMain.handle('local:get-all-songs', async () => {
    return await localManager.getAllLocalSongs()
})

ipcMain.handle('local:save-playlist', async (_event, playlist: GenericPlaylist) => {
    return await localManager.savePlaylist(playlist)
})

ipcMain.handle('local:save-album', async (_event, album: GenericAlbum) => {
    return await localManager.saveAlbum(album)
})

ipcMain.handle("system:check-internet-connection", () => {
/*   let connected = false

  dns.lookup("google.com")
  
  return */
})

ipcMain.handle("settings:load", () => {
    return loadSettings()
})

ipcMain.handle("settings:save", (event, settings: UserSettings) => {
    saveSettings(settings)
    return
})

ipcMain.handle("data:load", () => {
    return loadData()
})

ipcMain.handle("data:save", (event, data: UserData) => {
    saveData(data)
    return
})

// Credentials handlers
ipcMain.handle("credentials:save", async (event, credentials: APICredentials) => {
    return await saveCredentials(credentials)
})

ipcMain.handle("credentials:load", async () => {
    return await loadCredentials()
})

ipcMain.handle("credentials:has", () => {
    return hasCredentials()
})

ipcMain.handle("credentials:validate", (event, credentials: Partial<APICredentials>) => {
    return validateCredentials(credentials)
})

ipcMain.handle("credentials:delete", async () => {
    return await deleteCredentials()
})

ipcMain.handle("ytdlp:ensure", async () => {
    return await ytDlpManager.ensureYtDlp()
})

ipcMain.handle("ytdlp:is-available", async () => {
    return await ytDlpManager.isAvailable()
})

ipcMain.handle("ytdlp:update", async () => {
    return await ytDlpManager.update()
})

ipcMain.handle("ytdlp:force-redownload", async () => {
    return await ytDlpManager.forceRedownload()
})

ipcMain.handle("ytdlp:ensure-ffmpeg", async () => {
    return await ytDlpManager.ensureFfmpeg()
})

ipcMain.handle("ytdlp:ensure-both", async () => {
    return await ytDlpManager.ensureBoth()
})

// Query cache handlers
ipcMain.handle("query-cache:get", async (event, searchTerms: string) => {
    return await queryCache.get(searchTerms)
})

ipcMain.handle("query-cache:set", async (event, searchTerms: string, youtubeId: string) => {
    return await queryCache.set(searchTerms, youtubeId)
})

ipcMain.handle("query-cache:has", async (event, searchTerms: string) => {
    return await queryCache.has(searchTerms)
})

ipcMain.handle("query-cache:delete", async (event, searchTerms: string) => {
    return await queryCache.delete(searchTerms)
})

ipcMain.handle("query-cache:clear", async () => {
    return await queryCache.clear()
})

ipcMain.handle("query-cache:stats", async () => {
    return await queryCache.getStats()
})