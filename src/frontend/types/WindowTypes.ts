/* eslint-disable @typescript-eslint/no-explicit-any */
import { Album, Artist, ItemTypes, Playlist, SavedAlbum, SearchResults, SimplifiedPlaylist, User, UserProfile } from "@spotify/web-api-ts-sdk";
import { spotifyArtistDetails, youtubeSearchType } from "./SongTypes";
import { APICredentials, LyricsProviders, SpotifyLyrics, UserData, UserSettings } from "../../backend/utils/types";
import { SpotifyUserHome } from "../../backend/sources/Spotify";
export {}

declare global {
    interface Window {
        electronAPI: {
            info: {
                system: {
                    checkInternetConnection: () => void,
                },
                settings: {
                    load: () => Promise<UserSettings>,
                    save: (settings: UserSettings) => Promise<void>,
                },
                data: {
                    load: () => Promise<UserData>,
                    save: (settings: UserData) => Promise<void>,
                },
                credentials: {
                    save: (credentials: APICredentials) => Promise<void>,
                    load: () => Promise<APICredentials | null>,
                    has: () => Promise<boolean>,
                    validate: (credentials: Partial<APICredentials>) => Promise<boolean>,
                    delete: () => Promise<void>
                },
            }
            window: {
                minimize: () => void,
                maximize: () => void,
                isMaximized: () => Promise<boolean>,
                close: () => void,
                send: (channel: string, ...args: any[]) => void,
            },
            login: {
                spotify: {
                    login: () => void,
                    onSuccess: (callback: () => void) => void,
                    onError: (callback: (error: string) => void) => void,
                    loggedIn: () => Promise<{ loggedIn: boolean, expired: boolean }>
                },
                youtube: {
                    login: () => void,
                    onSuccess: (callback: () => void) => void,
                    onError: (callback: (error: string) => void) => void,
                    loggedIn: () => Promise<{ loggedIn: boolean, expired: boolean }>
                }
            },
            extractors: {
                getLyrics: (source: LyricsProviders, id: string) => Promise<SpotifyLyrics>, 
                spotify: {
                    search: (searchQuery: string) => Promise<SearchResults<readonly ItemTypes[]>>,
                    getUserLists: {
                        (type: "Playlists"): Promise<SimplifiedPlaylist[]>,
                        (type: "Albums"): Promise<SavedAlbum[]>,
                        (type: "Artists"): Promise<Artist[]>
                    },
                    getUserInfo: () => Promise<UserProfile>,
                    getUserDetails: (id: string) => Promise<User>,
                    getListInfo: {
                        (type: "Playlist", id: string): Promise<Playlist>,
                        (type: "Album", id: string): Promise<Album>,
                    },
                    getArtistDetails: (id: string) => Promise<spotifyArtistDetails>,
                    getArtistInfo: (id: string) => Promise<Artist>,
                    getUserHome: () => Promise<SpotifyUserHome>
                },
                youtube: {
                    search: (searchQuery: string) => Promise<youtubeSearchType>,
                    downloadYoutubeAudio: (type: "url" | "terms", searchQuery: string) => Promise<{ downloaded: boolean, downloadPath?: string }>
                    onDownloadStatus: (callback: (status: { status: string, downloadId: string, searchTerms: string, downloadPath: string, message: string }) => void) => void
                }
            },
            ytdlp: {
                ensure: () => Promise<string>,
                ensureFfmpeg: () => Promise<string>,
                ensureBoth: () => Promise<{ ytDlpPath: string; ffmpegPath: string }>,
                isAvailable: () => Promise<boolean>,
                update: () => Promise<void>,
                forceRedownload: () => Promise<string>
            }
        }
    }
}