import { LoopingEnum, Song } from "../../frontend/types/SongTypes"

export type spotifyAccessType = {
    access_token: string,
    token_type: string,
    expires_in: number,
    refresh_token: string,
    scope: string,
}

export interface spotifySavedCredentials extends spotifyAccessType {
    expires_at: number,
}

export type youtubeAccessType = {
    access_token: string,
    expires_in: number,
    refresh_token: string,
    scope: string,
    token_type: string,
    refresh_token_expires_in: string,
}

export interface youtubeSavedCredentials extends youtubeAccessType {
    expires_at: number
}

export const SHUFFLE_TYPES = ["Fisher-Yates", "Algorithmic"] as const
export type ShuffleType = typeof SHUFFLE_TYPES[number]

export const LIST_PLAY_TYPES = ["Single", "Multiple"] as const
export type ListPlayType = typeof LIST_PLAY_TYPES[number]

export interface UserData {
    lastPlayed: Song | undefined,
    preferredVolume: number,
    shuffled: boolean,
    looped: LoopingEnum,
    isNewUser: boolean
}

export interface UserSettings {
    shuffleType: ShuffleType
    listPlay: ListPlayType
}

export interface APICredentials {
    spotifyClientId: string
    spotifyClientSecret: string
    youtubeClientId: string
    youtubeClientSecret: string
}