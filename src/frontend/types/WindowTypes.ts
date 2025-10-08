/* eslint-disable @typescript-eslint/no-explicit-any */
import { ItemTypes, SearchResults } from "@spotify/web-api-ts-sdk";
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