/* eslint-disable @typescript-eslint/no-explicit-any */
import { Album, Artist, ItemTypes, Playlist, SavedAlbum, SearchResults, SimplifiedPlaylist, UserProfile } from "@spotify/web-api-ts-sdk";
import { youtubeSearchType } from "./SongTypes";
import { UserSettings } from "../../backend/utils/types";
export {}

declare global {
    interface Window {
        electronAPI: {
            settings: {
                load: () => UserSettings,
                save: (settings: UserSettings) => void,
            },
            window: {
                minimize: () => void,
                maximize: () => void,
                isMaximized: () => Promise<boolean>,
                close: () => void,
                send: (channel: string, ...args: any[]) => void,
            },
            system: {
                checkInternetConnection: () => void,
            },
            login: {
                spotify: {
                    login: () => void,
                    onCode: (callback: (code: string) => void) => void,
                    loggedIn: () => Promise<{ loggedIn: boolean, expired: boolean }>
                },
                youtube: {
                    login: () => void,
                    onCode: (callback: (code: string) => void) => void,
                    loggedIn: () => Promise<{ loggedIn: boolean, expired: boolean }>
                }
            },
            extractors: {
                spotify: {
                    search: (searchQuery: string) => Promise<SearchResults<readonly ItemTypes[]>>,
                    getUserLists: {
                        (type: "Playlists"): Promise<SimplifiedPlaylist[]>,
                        (type: "Albums"): Promise<SavedAlbum[]>,
                        (type: "Artists"): Promise<Artist[]>
                    },
                    getUserInfo: () => Promise<UserProfile>,
                    getListInfo: {
                        (type: "Playlist", id: string): Promise<Playlist>,
                        (type: "Album", id: string): Promise<Album>,
                    },
                },
                youtube: {
                    search: (searchQuery: string) => Promise<youtubeSearchType>,
                    downloadYoutubeAudio: (type: "url" | "terms", searchQuery: string) => Promise<{ downloaded: boolean, downloadPath?: string }>
                    onDownloadStatus: (callback: (status: { status: string, downloadPath: string, message: string }) => void) => void
                }
            }
        }
    }
}