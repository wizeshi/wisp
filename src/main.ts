import { app, BrowserWindow, ipcMain, shell, protocol, net } from 'electron';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { getSpotifyAccess, getSpotifyArtistDetails, getSpotifyListDetails, getSpotifyUserInfo, isSpotifyLoggedIn, loadSpotifyUserLists, saveSpotifyCredentials, spotifySearch } from './backend/sources/Spotify'
import dns from 'dns';
import { downloadYoutubeAudio, getYoutubeAccess, isYoutubeLoggedIn, saveYoutubeCredentials, searchYoutube } from './backend/sources/Youtube';
import { loadSettings, saveSettings } from './backend/Settings';
import { APICredentials, UserData, UserSettings } from './backend/utils/types';
import { SidebarItemType, SidebarListType } from './frontend/types/SongTypes';
import { createServer, Server } from 'node:http';
import { loadData, saveData } from './backend/Data';
import { deleteCredentials, hasCredentials, loadCredentials, saveCredentials, validateCredentials } from './backend/Credentials';

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

app.whenReady().then(() => {
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
        icon: "assets/wisp.ico"
    });

    if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
        mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
    } else {
        mainWindow.loadFile(
            path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
        );
    }

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
                    
                    getYoutubeAccess(code).then((access) => {
                        saveYoutubeCredentials(access)

                        mainWindow.webContents.send('login:youtube-success')
                    }).catch((err) => {
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

    // Open the DevTools.
    mainWindow.webContents.openDevTools();
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
                getSpotifyAccess(code).then((access) => {                    
                    saveSpotifyCredentials(access)

                    mainWindow.webContents.send('login:spotify-success')
                }).catch((err) => {
                    console.error('Failed to get Spotify access:', err)
                    mainWindow.webContents.send('login:spotify-error', err.message)
                })
                break
            case "youtube":
                // This case probably won't happen since YouTube uses localhost, but keep bc why not
                getYoutubeAccess(code).then((access) => {
                    saveYoutubeCredentials(access)

                    mainWindow.webContents.send('login:youtube-success')
                }).catch((err) => {
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

ipcMain.handle("extractors:spotify-search", (_event, searchQuery: string) => {
    return spotifySearch(searchQuery)
})

ipcMain.handle("extractors:spotify-user-lists", (_event, type: SidebarListType) => {
    return loadSpotifyUserLists(type)
})

ipcMain.handle('extractors:spotify-user-info', (_event) => {
    return getSpotifyUserInfo()
})

ipcMain.handle('extractors:spotify-list-info', (_event, type: "Album" | "Playlist", id) => {
    return getSpotifyListDetails(type, id)
})

ipcMain.handle('extractors:spotify-artist-info', (_event, id) => {
    return getSpotifyArtistDetails(id)
})

ipcMain.handle("extractors:youtube-search", (_event, searchQuery) => {
    return searchYoutube(searchQuery)
})

ipcMain.handle("extractors:youtube-download", (_event, type, searchQuery) => {
    return downloadYoutubeAudio(type, searchQuery)
})

ipcMain.handle("login:spotify-logged-in", () => {
	return isSpotifyLoggedIn()
})

ipcMain.handle("login:youtube-logged-in", () => {
    return isYoutubeLoggedIn()
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

// yt-dlp handlers
import { ytDlpManager } from './backend/utils/YtDlpManager';

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