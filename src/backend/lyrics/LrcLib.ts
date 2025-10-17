import { GenericLyrics, GenericLyricsLine } from "../../common/types/LyricsTypes"
import { GenericSong } from "../../common/types/SongTypes"

const LRCLIB_LYRICS_BASE_URL = 'https://lrclib.net/api/get'
const LRCLIB_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 wisp/1.0.0'

type LrcLibLyrics = {
    id: string,
    trackName: string,
    artistName: string,
    albumName: string,
    duration: number,
    instrumental: boolean,
    plainLyrics: string,
    syncedLyrics: string
}

class LrcLibProvider {
    async getLyrics(song: GenericSong) {
        const artistName = encodeURIComponent(song.artists.map(artist => artist.name).join(", "))
        const trackName = encodeURIComponent(song.title)
        const albumName = encodeURIComponent(song.album ? encodeURIComponent(song.album.title) : "")
        const songDuration = song.durationSecs

        const URL = `${LRCLIB_LYRICS_BASE_URL}?artist_name=${artistName}&track_name=${trackName}&album_name=${albumName}&duration=${songDuration}`
        
        const response = await fetch(URL, {
            headers: {
                'Accept': 'application/json',
                'User-Agent': LRCLIB_USER_AGENT,
            },
        })

        try {
            if (response.ok) {
                const lyricsResponse = (await response.json()) as LrcLibLyrics
                const synced = (lyricsResponse.syncedLyrics && lyricsResponse.syncedLyrics.length > 0) ? true : false

                switch (synced) {
                    case true: {
                        // Parse synced lyrics format: [mm:ss.cc] Lorem ipsum dolor sit amet
                        const lines: GenericLyricsLine[] = lyricsResponse.syncedLyrics.split("\n")
                            .filter((line: string) => line.trim())
                            .map((line: string) => {
                                // Match timestamp pattern [mm:ss.cc]
                                const match = line.match(/\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)/)
                                if (match) {
                                    const minutes = parseInt(match[1])
                                    const seconds = parseInt(match[2])
                                    const centiseconds = parseInt(match[3])
                                    const content = match[4]
                                    
                                    // Convert to milliseconds
                                    const startTimeMs = (minutes * 60 * 1000) + (seconds * 1000) + (centiseconds * 10)
                                    
                                    return {
                                        content: content,
                                        startTimeMs: startTimeMs.toString()
                                    }
                                }
                                // Fallback if pattern doesn't match
                                return {
                                    content: line,
                                    startTimeMs: "0"
                                }
                            })
                        
                        const properLyrics: GenericLyrics = {
                            provider: "lrclib",
                            synced: synced,
                            lines: lines
                        }

                        return properLyrics
                    }
                    case false: {
                        // Parse plain lyrics - just split by newline
                        const lines: GenericLyricsLine[] = lyricsResponse.plainLyrics.split("\n")
                            .filter((line: string) => line.trim())
                            .map((line: string) => ({
                                content: line,
                                startTimeMs: "0"
                            }))
                        
                        const properLyrics: GenericLyrics = {
                            provider: "lrclib",
                            synced: synced,
                            lines: lines
                        }

                        return properLyrics
                    }
                }
            }
        } catch (e) {
            console.log(e)
        }
    }
}

export const lrcLibProvider = new LrcLibProvider()