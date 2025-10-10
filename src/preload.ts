/* eslint-disable @typescript-eslint/no-explicit-any */
// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts

import { contextBridge, ipcRenderer } from "electron";
import { UserSettings } from "./backend/utils/types";
import { SidebarItemType, SidebarListType } from "./frontend/types/SongTypes";

contextBridge.exposeInMainWorld('electronAPI', {
    settings: {
        load: () => ipcRenderer.invoke("settings:load"),
        save: (settings: UserSettings) => ipcRenderer.invoke("settings:save", settings)
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
            onCode: (callback: (code: string) => void) => ipcRenderer.on('login:spotify-code', (_event, code) => callback(code)),
            loggedIn: () => ipcRenderer.invoke('login:spotify-logged-in')
        },
        youtube: {
            login: () => ipcRenderer.send('login:youtube-login'),
            onCode: (callback: (code: string) => void) => ipcRenderer.on('login:youtube-code', (_event, code) => callback(code)),
            loggedIn: () => ipcRenderer.invoke('login:youtube-logged-in')
        }
    },
    extractors: {
        spotify: {
            search: (searchQuery: string) => ipcRenderer.invoke('extractors:spotify-search', searchQuery),
            getUserLists: (type: SidebarListType) => ipcRenderer.invoke('extractors:spotify-user-lists', type),
            getUserInfo: () => ipcRenderer.invoke('extractors:spotify-user-info'),
            getListInfo: (type: SidebarItemType, id: string) => ipcRenderer.invoke('extractors:spotify-list-info', type, id),
        },
        youtube: {
            search: (searchQuery: string) => ipcRenderer.invoke('extractors:youtube-search', searchQuery),
            downloadYoutubeAudio: (type: "url" | "terms", searchQuery: string) => ipcRenderer.invoke("extractors:youtube-download", type, searchQuery),
            onDownloadStatus: (callback: (status: any) => void) =>
                ipcRenderer.on('youtube-download-status', (_event, status) => callback(status)),
        }
    }
})