export type LyricsSources = "spotify" | "musixmatch" | "genius" | "lrclib"

export type GenericLyricsProvider = {
    info: {
        name: LyricsSources,
        iconURL: string
    },
    getLyrics: (id: string) => GenericLyrics 
}

export type GenericLyrics = {
    provider: LyricsSources,
    synced: boolean,
    lines: GenericLyricsLine[]
}

export type GenericLyricsLine = {
    content: string,
    startTimeMs: string,
}