import { GenericLyrics, LyricsSources } from "../../common/types/LyricsTypes";
import { GenericSong } from "../../common/types/SongTypes";
import { spotifyProvider } from "./Spotify";
import { lrcLibProvider } from "./LrcLib";

/**
 * Get lyrics with automatic fallback between providers
 * @param song - The song object with metadata
 * @param source - Optional source to use (defaults to trying all available)
 * @returns Promise<GenericLyrics>
 */
export const getLyrics = async (song: GenericSong, source?: LyricsSources): Promise<GenericLyrics> => {
    // If a specific source is requested, try only that source
    if (source) {
        switch (source) {
            case 'spotify':
                if (song.id) {
                    return await spotifyProvider.getLyrics(song.id)
                }
                throw new Error("No Spotify ID available for this song")
            case 'lrclib':
                return await lrcLibProvider.getLyrics(song)
            default:
                throw new Error(`Unknown lyrics source: ${source}`)
        }
    }

    if (song.id && song.source === 'spotify') {
        try {
            console.log("Attempting to get lyrics from Spotify...")
            const spotifyLyrics = await spotifyProvider.getLyrics(song.id)
            
            // Check if Spotify returned valid lyrics (not null/undefined)
            if (spotifyLyrics) {
                console.log("Successfully retrieved lyrics from Spotify")
                return spotifyLyrics
            } else {
                console.log("Spotify returned null, falling back to LrcLib")
            }
        } catch (error) {
            console.log("Failed to get lyrics from Spotify, falling back to LrcLib:", error)
        }
    }

    try {
        console.log("Attempting to get lyrics from LrcLib...")
        const lrcLibLyrics = await lrcLibProvider.getLyrics(song)
        console.log("Successfully retrieved lyrics from LrcLib")
        return lrcLibLyrics
    } catch (error) {
        console.error("Failed to get lyrics from LrcLib:", error)
    }

    return null
}