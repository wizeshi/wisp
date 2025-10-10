import { app, BrowserWindow, ipcMain, protocol, net } from 'electron';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { getSpotifyAccess, getSpotifyListDetails, getSpotifyUserInfo, isSpotifyLoggedIn, loadSpotifyUserLists, saveSpotifyCredentials, spotifySearch } from './backend/sources/Spotify'
import dns from 'dns';
import { downloadYoutubeAudio, getYoutubeAccess, isYoutubeLoggedIn, saveYoutubeCredentials, searchYoutube } from './backend/sources/Youtube';
import { loadSettings, saveSettings } from './backend/Settings';
import { UserSettings } from './backend/utils/types';
import { SidebarItemType, SidebarListType } from './frontend/types/SongTypes';
import dotenv from "dotenv"

dotenv.config()

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
    app.quit();
}

export let mainWindow: BrowserWindow | null = null

protocol.registerSchemesAsPrivileged([
    { scheme: 'wisp-audio', privileges: { secure: true, standard: true, supportFetchAPI: true, stream: true, bypassCSP: true } }
])

app.whenReady().then(() => {
    protocol.handle('wisp-audio', async request => {
        const requestUrl = request.url.replace('wisp-audio://', '')
        const filePath = `file:///${requestUrl.charAt(0) + ':' + requestUrl.slice(1)}`;

        return net.fetch(filePath)
    });

    mainWindow = new BrowserWindow({
        minWidth: 1046,
        width: 1046,
        minHeight: 665,
        height: 665,
        titleBarStyle: "hidden",
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
    });

    // and load the index.html of the app.
    if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
        mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
    } else {
        mainWindow.loadFile(
            path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
        );
    }

    ipcMain.on("login:youtube-login", () => {
        const clientId = process.env.YOUTUBE_CLIENT_ID
        const redirectUri = "http://127.0.0.1:5173/callback"
        const scopes = [
            "https://www.googleapis.com/auth/youtube.readonly"
        ].join(" ")

        const authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" +
            `&client_id=${encodeURIComponent(clientId)}` +
            `&redirect_uri=${encodeURIComponent(redirectUri)}` +
            `&response_type=code` + 
            `&scope=${encodeURIComponent(scopes)}` +
            `&access_type=offline` +
            `&prompt=consent`

        const win = new BrowserWindow({ width: 500, height: 700, show: true })

        win.loadURL(authUrl)
        
        win.webContents.on("will-redirect", (event, url) => {
            if (url.startsWith(redirectUri)) {
                const code = new URL(url).searchParams.get('code')
                win.close()
                if (mainWindow) {
                    mainWindow.webContents.send('login:youtube-code', code)
                }
            }
        })
    })

    ipcMain.on("login:spotify-login", () => {
        const clientId = process.env.SPOTIFY_CLIENT_ID
        const redirectUri = "http://127.0.0.1:5173/callback"
        const scopes = [
            "playlist-read-private",
            "playlist-read-collaborative",
            "user-follow-read",
            "user-top-read",
            "user-read-recently-played",
            "user-library-read"
        ].join(" ");

        const authUrl = `https://accounts.spotify.com/authorize?response_type=code&client_id=${encodeURIComponent(clientId)}&scope=${encodeURIComponent(scopes)}&redirect_uri=${encodeURIComponent(redirectUri)}`;

        const loginWindow = new BrowserWindow({
            width: 500,
            height: 700,
            show: true,
            webPreferences: {
                nodeIntegration: false,
                contextIsolation: true,
            }
        });

        loginWindow.loadURL(authUrl);

        loginWindow.webContents.on('will-redirect', (event, url) => {
            if (url.startsWith(redirectUri)) {
                const code = new URL(url).searchParams.get('code');
                    loginWindow.close();
                if (mainWindow) {
                    mainWindow.webContents.send('login:spotify-code', code);
                }
            }
        });

    })

    ipcMain.on("SPOTIFY_TOKEN", (event, code) => {
        getSpotifyAccess(code).then((access) => {
            saveSpotifyCredentials(access)
        })
    })

    ipcMain.on("YOUTUBE_TOKEN", (event, code) => {
        getYoutubeAccess(code).then((access) => {
            saveYoutubeCredentials(access)
        })
    })

    // Open the DevTools.
    mainWindow.webContents.openDevTools();
})

app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");

// Quit when all windows are closed.
app.on('window-all-closed', () => {
    app.quit();
});

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

ipcMain.handle('extractors:spotify-list-info', (_event, type: SidebarItemType, id) => {
    return getSpotifyListDetails(type, id)
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