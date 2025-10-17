import { GenericAlbum, GenericArtist, GenericPlaylist, GenericSimpleArtist, GenericSong } from "./SongTypes"

/**
 * Generic type for search results across all sources
 */
export type GenericSearch = {
    songs: GenericSong[]
    albums?: GenericAlbum[]
    playlists?: GenericPlaylist[]
    artists?: GenericArtist[]
}

/**
 * Generic type for user home page data
 */
export type GenericUserHome = {
    topTracks: GenericSong[]
    topArtists: GenericSimpleArtist[]
    followedArtists: GenericSimpleArtist[]
    followedAlbums: GenericAlbum[]
    savedPlaylists: GenericPlaylist[]
}