/* eslint-disable @typescript-eslint/no-explicit-any */
import { GenericAlbum, GenericArtist, GenericPlaylist, GenericSimpleArtist, GenericSimpleUser, GenericSong, GenericUser, SongSources } from "../../common/types/SongTypes";
import { GenericSearch, GenericUserHome } from "../../common/types/SourcesTypes";
import { APICredentials, UserData, UserSettings } from "../../backend/utils/types";
import { GenericLyrics, LyricsSources } from "../../common/types/LyricsTypes";
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
                },
                youtube: {
                    login: () => void,
                    onSuccess: (callback: () => void) => void,
                    onError: (callback: (error: string) => void) => void,
                },
                isLoggedIn: (source: SongSources) => Promise<{ loggedIn: boolean, expired: boolean }>
            },
            extractors: {
                getLyrics: (song: GenericSong, source?: LyricsSources) => Promise<GenericLyrics>,
                search: (searchQuery: string, source?: SongSources) => Promise<GenericSearch>,
                getUserLists: {
                    (type: "Playlists", source?: SongSources): Promise<GenericPlaylist[]>;
                    (type: "Albums", source?: SongSources): Promise<GenericAlbum[]>;
                    (type: "Artists", source?: SongSources): Promise<GenericArtist[]>;
                }
                getUserInfo: (source?: SongSources) => Promise<GenericUser>,
                getUserDetails: (id: string, source?: SongSources) => Promise<GenericSimpleUser>,
                getListDetails: {
                    (type: "Album", id: string, source?: SongSources): Promise<GenericAlbum>;
                    (type: "Playlist", id: string, source?: SongSources): Promise<GenericPlaylist>;
                    (type: "Artist", id: string, source?: SongSources): Promise<GenericArtist>;
                }
                forceRefreshList: {
                    (type: "Album", id: string, source?: SongSources): Promise<GenericAlbum>;
                    (type: "Playlist", id: string, source?: SongSources): Promise<GenericPlaylist>;
                }
                getArtistInfo: (id: string, source?: SongSources) => Promise<GenericSimpleArtist>,
                getArtistDetails: (id: string, source?: SongSources) => Promise<GenericArtist>,
                getUserHome: (source?: SongSources) => Promise<GenericUserHome>,
                getUserLikes: (source?: SongSources, offset?: number) => Promise<GenericPlaylist>,
                youtube: {
                    downloadAudio: (type: "url" | "terms", searchQuery: string) => Promise<{ downloaded: boolean, downloadPath?: string }>
                    onDownloadStatus: (callback: (status: { status: string, downloadId: string, searchTerms: string, downloadPath: string, message: string }) => void) => void
                }
            },
            local: {
                selectAudioFiles: () => Promise<string[]>,
                importAudioFile: (filePath: string) => Promise<GenericSong>,
                importAudioFiles: (filePaths: string[]) => Promise<GenericSong[]>,
                getAudioPath: (songId: string) => Promise<string | null>,
                deleteSong: (songId: string) => Promise<boolean>,
                getAllSongs: () => Promise<GenericSong[]>,
                savePlaylist: (playlist: GenericPlaylist) => Promise<boolean>,
                saveAlbum: (album: GenericAlbum) => Promise<boolean>
            },
            ytdlp: {
                ensure: () => Promise<string>,
                ensureFfmpeg: () => Promise<string>,
                ensureBoth: () => Promise<{ ytDlpPath: string; ffmpegPath: string }>,
                isAvailable: () => Promise<boolean>,
                update: () => Promise<void>,
                forceRedownload: () => Promise<string>
            },
            queryCache: {
                get: (searchTerms: string) => Promise<string | undefined>,
                set: (searchTerms: string, youtubeId: string) => Promise<void>,
                has: (searchTerms: string) => Promise<boolean>,
                delete: (searchTerms: string) => Promise<boolean>,
                clear: () => Promise<void>,
                getStats: () => Promise<{
                    totalEntries: number;
                    totalHits: number;
                    oldestEntry: number | null;
                    newestEntry: number | null;
                }>
            }
        }
    }
}