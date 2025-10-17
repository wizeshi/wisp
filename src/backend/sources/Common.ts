import { SidebarItemType, SidebarListType, SongSources } from "../../common/types/SongTypes";
import { spotifyExtractor } from "./Spotify";
import { youtubeExtractor } from "./Youtube";
import { localExtractor } from "./Local";
import { GenericExtractor } from "./Generic";

// Default source priority
const DEFAULT_SOURCE: SongSources = "spotify";
const FALLBACK_SOURCE: SongSources = "youtube";

/**
 * Get the appropriate extractor for a given source
 */
export const getSourceExtractor = (source: SongSources): GenericExtractor => {
    switch (source) {
        case "local":
            return localExtractor as GenericExtractor;
        case "spotify":
            return spotifyExtractor as GenericExtractor;
        case "youtube":
            return youtubeExtractor as GenericExtractor;
        case "soundcloud":
            throw new Error("SoundCloud source not yet implemented");
        default:
            throw new Error(`Unknown source: ${source}`);
    }
}

/**
 * Automatically determine which source to use based on availability
 * Prioritizes Spotify, falls back to YouTube if not logged in
 */
export const getAvailableSource = async (preferredSource?: SongSources): Promise<SongSources> => {
    // If a preferred source is specified, try to use it
    if (preferredSource) {
        const extractor = getSourceExtractor(preferredSource);
        const status = await extractor.isLoggedIn();
        if (status.loggedIn && !status.expired) {
            return preferredSource;
        }
    }

    // Try default source (Spotify)
    try {
        const spotifyStatus = await spotifyExtractor.isLoggedIn();
        if (spotifyStatus.loggedIn && !spotifyStatus.expired) {
            return DEFAULT_SOURCE;
        }
    } catch (error) {
        console.log("Spotify not available:", error);
    }

    // Fall back to YouTube
    try {
        const youtubeStatus = await youtubeExtractor.isLoggedIn();
        if (youtubeStatus.loggedIn && !youtubeStatus.expired) {
            return FALLBACK_SOURCE;
        }
    } catch (error) {
        console.log("YouTube not available:", error);
    }

    // Default to Spotify even if not logged in (will prompt for login)
    return DEFAULT_SOURCE;
}

/**
 * Perform a search using the best available source
 * @param searchTerms - The search query
 * @param source - Optional: Force a specific source
 */
export const search = async (searchTerms: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Searching using ${selectedSource} source`);
    
    return await extractor.search(searchTerms);
}

/**
 * Get user info from the best available source
 */
export const getUserInfo = async (source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting user info from ${selectedSource} source`);
    
    return await extractor.getUserInfo();
}

/**
 * Get user lists (playlists, albums, or artists) from the best available source
 */
export const getUserLists = async (type: SidebarListType, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting user ${type} from ${selectedSource} source`);
    
    return await extractor.getUserLists(type);
}

/**
 * Get details for a specific user
 */
export const getUserDetails = async (id: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting user details from ${selectedSource} source`);
    
    return await extractor.getUserDetails(id);
}

/**
 * Get details for a playlist, album, or artist
 */
export const getListDetails = async (type: SidebarItemType, id: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting ${type} details from ${selectedSource} source`);
    
    return await extractor.getListDetails(type, id);
}

/**
 * Force refresh playlist/album from API, removing local songs
 */
export const forceRefreshListDetails = async (type: "Playlist" | "Album", id: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    
    // Only Spotify has the forceRefresh method for now
    if (selectedSource === 'spotify') {
        const { spotifyExtractor } = await import('./Spotify');
        console.log(`Force refreshing ${type} from Spotify API`);
        return await spotifyExtractor.forceRefreshListDetails(type, id);
    }
    
    // For other sources, just use normal getListDetails
    const extractor = getSourceExtractor(selectedSource);
    return await extractor.getListDetails(type, id);
}

/**
 * Get basic artist information
 */
export const getArtistInfo = async (id: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting artist info from ${selectedSource} source`);
    
    return await extractor.getArtistInfo(id);
}

/**
 * Get detailed artist information (top tracks, albums, etc.)
 */
export const getArtistDetails = async (id: string, source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting artist details from ${selectedSource} source`);
    
    return await extractor.getArtistDetails(id);
}

/**
 * Get user home data (top tracks, artists, etc.)
 */
export const getUserHome = async (source?: SongSources) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);
    
    console.log(`Getting user home from ${selectedSource} source`);
    
    return await extractor.getUserHome();
}

export const getSavedSongs = async (source?: SongSources, offset?: number) => {
    const selectedSource = source || await getAvailableSource();
    const extractor = getSourceExtractor(selectedSource);

    console.log(`Getting user saved songs from ${selectedSource} source`);

    return await extractor.getUserLikes(offset)
}