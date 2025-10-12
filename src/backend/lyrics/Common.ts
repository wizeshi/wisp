import { LyricsProviders } from "../utils/types";
import { spotifyProvider } from "./Spotify";

export const getLyrics = async (source: LyricsProviders, id: string) => {
    switch (source) {
        case 'Spotify':
        default:
            return await spotifyProvider.getLyrics(id)
    }
}