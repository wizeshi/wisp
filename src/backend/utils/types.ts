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

export interface UserSettings {
    shuffleType: ShuffleType
}