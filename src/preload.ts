/* eslint-disable @typescript-eslint/no-explicit-any */
// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts

import { contextBridge, ipcRenderer } from "electron";
import { APICredentials, UserData, UserSettings } from "./backend/utils/types";
import { GenericSong, SidebarItemType, SidebarListType, SongSources } from "./common/types/SongTypes";
import { LyricsSources } from "./common/types/LyricsTypes";

contextBridge.exposeInMainWorld('electronAPI', {
    info:{
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
        system: {
            checkInternetConnection: () => ipcRenderer.invoke("system:check-internet-connection")
        },
    },
    window: {
        minimize: () => ipcRenderer.invoke("window:minimize"),
        maximize: () => ipcRenderer.invoke("window:maximize"),
        isMaximized: () => ipcRenderer.invoke("window:isMaximized"),
        close: () => ipcRenderer.invoke("window:close"),
        send: (channel: string, ...args: any[]) => ipcRenderer.send(channel, ...args)
    },
    login: {
        spotify: {
            login: () => ipcRenderer.send('login:spotify-login'),
            onSuccess: (callback: () => void) => ipcRenderer.on('login:spotify-success', () => callback()),
            onError: (callback: (error: string) => void) => ipcRenderer.on('login:spotify-error', (_event, error) => callback(error)),
        },
        youtube: {
            login: () => ipcRenderer.send('login:youtube-login'),
            onSuccess: (callback: () => void) => ipcRenderer.on('login:youtube-success', () => callback()),
            onError: (callback: (error: string) => void) => ipcRenderer.on('login:youtube-error', (_event, error) => callback(error)),
        },
        isLoggedIn: (source: SongSources) => ipcRenderer.invoke('login:is-logged-in', source)
    },
    extractors: {
        getLyrics: (song: GenericSong, source?: LyricsSources) => ipcRenderer.invoke("extractors:lyrics-get", song, source),
        search: (searchQuery: string, source?: SongSources) => ipcRenderer.invoke('extractors:search', searchQuery, source),
        getUserLists: (type: SidebarListType, source?: SongSources) => ipcRenderer.invoke('extractors:user-lists', type, source),
        getUserInfo: (source?: SongSources) => ipcRenderer.invoke('extractors:user-info', source),
        getUserDetails: (id: string, source?: SongSources) => ipcRenderer.invoke('extractors:user-details', id, source),
        getListDetails: (type: SidebarItemType, id: string, source?: SongSources) => ipcRenderer.invoke('extractors:list-details', type, id, source),
        forceRefreshList: (type: "Playlist" | "Album", id: string, source?: SongSources) => ipcRenderer.invoke('extractors:force-refresh-list', type, id, source),
        getArtistInfo: (id: string, source?: SongSources) => ipcRenderer.invoke('extractors:artist-info', id, source),
        getArtistDetails: (id: string, source?: SongSources) => ipcRenderer.invoke('extractors:artist-details', id, source),
        getUserHome: (source?: SongSources) => ipcRenderer.invoke('extractors:user-home', source),
        getUserLikes: (source?: SongSources, offset?: number) => ipcRenderer.invoke('extractors:saved-songs', source, offset),
        youtube: {
            downloadAudio: (type: "url" | "terms", searchQuery: string) => ipcRenderer.invoke("extractors:youtube-download", type, searchQuery),
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
    },
    queryCache: {
        get: (searchTerms: string) => ipcRenderer.invoke('query-cache:get', searchTerms),
        set: (searchTerms: string, youtubeId: string) => ipcRenderer.invoke('query-cache:set', searchTerms, youtubeId),
        has: (searchTerms: string) => ipcRenderer.invoke('query-cache:has', searchTerms),
        delete: (searchTerms: string) => ipcRenderer.invoke('query-cache:delete', searchTerms),
        clear: () => ipcRenderer.invoke('query-cache:clear'),
        getStats: () => ipcRenderer.invoke('query-cache:stats')
    },
    local: {
        selectAudioFiles: () => ipcRenderer.invoke('local:select-audio-files'),
        importAudioFile: (filePath: string) => ipcRenderer.invoke('local:import-audio-file', filePath),
        importAudioFiles: (filePaths: string[]) => ipcRenderer.invoke('local:import-audio-files', filePaths),
        getAudioPath: (songId: string) => ipcRenderer.invoke('local:get-audio-path', songId),
        deleteSong: (songId: string) => ipcRenderer.invoke('local:delete-song', songId),
        getAllSongs: () => ipcRenderer.invoke('local:get-all-songs'),
        savePlaylist: (playlist: any) => ipcRenderer.invoke('local:save-playlist', playlist),
        saveAlbum: (album: any) => ipcRenderer.invoke('local:save-album', album)
    }
})