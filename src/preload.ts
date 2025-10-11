/* eslint-disable @typescript-eslint/no-explicit-any */
// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts

import { contextBridge, ipcRenderer } from "electron";
import { APICredentials, UserData, UserSettings } from "./backend/utils/types";
import { SidebarItemType, SidebarListType } from "./frontend/types/SongTypes";

contextBridge.exposeInMainWorld('electronAPI', {
    settings: {
        load: () => ipcRenderer.invoke("settings:load"),
        save: (settings: UserSettings) => ipcRenderer.invoke("settings:save", settings)
    },
    data: {
        load: () => ipcRenderer.invoke("data:load"),
        save: (data: UserData) => ipcRenderer.invoke("data:save", data)
    },
    credentials: {
        save: (credentials: APICredentials) => ipcRenderer.invoke("credentials:save", credentials),
        load: () => ipcRenderer.invoke("credentials:load"),
        has: () => ipcRenderer.invoke("credentials:has"),
        validate: (credentials: Partial<APICredentials>) => ipcRenderer.invoke("credentials:validate", credentials),
        delete: () => ipcRenderer.invoke("credentials:delete")
    },
    window: {
        minimize: () => ipcRenderer.invoke("window:minimize"),
        maximize: () => ipcRenderer.invoke("window:maximize"),
        isMaximized: () => ipcRenderer.invoke("window:isMaximized"),
        close: () => ipcRenderer.invoke("window:close"),
        send: (channel: string, ...args: any[]) => ipcRenderer.send(channel, ...args)
    },
    system: {
        checkInternetConnection: () => ipcRenderer.invoke("system:check-internet-connection")
    },
    login: {
        spotify: {
            login: () => ipcRenderer.send('login:spotify-login'),
            onSuccess: (callback: () => void) => ipcRenderer.on('login:spotify-success', () => callback()),
            onError: (callback: (error: string) => void) => ipcRenderer.on('login:spotify-error', (_event, error) => callback(error)),
            loggedIn: () => ipcRenderer.invoke('login:spotify-logged-in')
        },
        youtube: {
            login: () => ipcRenderer.send('login:youtube-login'),
            onSuccess: (callback: () => void) => ipcRenderer.on('login:youtube-success', () => callback()),
            onError: (callback: (error: string) => void) => ipcRenderer.on('login:youtube-error', (_event, error) => callback(error)),
            loggedIn: () => ipcRenderer.invoke('login:youtube-logged-in')
        }
    },
    extractors: {
        spotify: {
            search: (searchQuery: string) => ipcRenderer.invoke('extractors:spotify-search', searchQuery),
            getUserLists: (type: SidebarListType) => ipcRenderer.invoke('extractors:spotify-user-lists', type),
            getUserInfo: () => ipcRenderer.invoke('extractors:spotify-user-info'),
            getListInfo: (type: SidebarItemType, id: string) => ipcRenderer.invoke('extractors:spotify-list-info', type, id),
            getArtistInfo: (id: string) => ipcRenderer.invoke('extractors:spotify-artist-info', id)
        },
        youtube: {
            search: (searchQuery: string) => ipcRenderer.invoke('extractors:youtube-search', searchQuery),
            downloadYoutubeAudio: (type: "url" | "terms", searchQuery: string) => ipcRenderer.invoke("extractors:youtube-download", type, searchQuery),
            onDownloadStatus: (callback: (status: any) => void) =>
                ipcRenderer.on('youtube-download-status', (_event, status) => callback(status)),
        }
    },
    ytdlp: {
        ensure: () => ipcRenderer.invoke('ytdlp:ensure'),
        ensureFfmpeg: () => ipcRenderer.invoke('ytdlp:ensure-ffmpeg'),
        ensureBoth: () => ipcRenderer.invoke('ytdlp:ensure-both'),
        isAvailable: () => ipcRenderer.invoke('ytdlp:is-available'),
        update: () => ipcRenderer.invoke('ytdlp:update'),
        forceRedownload: () => ipcRenderer.invoke('ytdlp:force-redownload')
    }
})