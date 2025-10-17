import { GenericExtractor } from './Generic'
import { SidebarListType, GenericSong, GenericSimpleArtist, GenericAlbum, GenericPlaylist, GenericSimpleUser, GenericUser } from '../../common/types/SongTypes'
import { GenericSearch, GenericUserHome } from '../../common/types/SourcesTypes'
import { localManager } from '../LocalManager'

class LocalExtractor extends GenericExtractor {
    constructor() {
        super()
    }

    async isLoggedIn(): Promise<{ loggedIn: boolean; expired: boolean }> {
        return { loggedIn: true, expired: false }
    }

    /**
     * Search through local songs
     */
    async search(searchTerms: string): Promise<GenericSearch> {
        const allSongs = await localManager.getAllLocalSongs()
        const query = searchTerms.toLowerCase()

        const matchingSongs = allSongs.filter(song => {
            const titleMatch = song.title.toLowerCase().includes(query)
            const artistMatch = song.artists.some(artist => 
                artist.name.toLowerCase().includes(query)
            )
            const albumMatch = song.album?.title.toLowerCase().includes(query)

            return titleMatch || artistMatch || albumMatch
        })

        return {
            songs: matchingSongs
        }
    }

    /**
     * Get user's local library lists
     */
    async getUserLists(type: SidebarListType): Promise<unknown> {
        switch (type) {
            case "Playlists":
                return await localManager.loadAllPlaylists()
            case "Albums":
                return await localManager.loadAllAlbums()
            case "Artists":
                return await localManager.loadAllArtists()
            default:
                return []
        }
    }

    /**
     * Get mock user info for local source
     */
    async getUserInfo(): Promise<GenericUser> {
        return new GenericUser(
            'local-user',
            'local',
            'Local Library',
            '',
            0,
            '',
            '',
            ''
        )
    }

    /**
     * Get user details (not applicable for local)
     */
    async getUserDetails(id: string): Promise<GenericUser> {
        return this.getUserInfo()
    }

    /**
     * Get playlist or album details
     */
    async getListDetails(type: "Playlist" | "Album" | "Artist", id: string): Promise<GenericPlaylist | GenericAlbum> {
        if (type === "Artist") {
            throw new Error("Use getArtistDetails for artists")
        }

        if (type === "Playlist") {
            const playlist = await localManager.loadPlaylist(id, 'local')
            if (!playlist) {
                throw new Error(`Playlist ${id} not found`)
            }
            return playlist
        }

        if (type === "Album") {
            const album = await localManager.loadAlbum(id, 'local')
            if (!album) {
                throw new Error(`Album ${id} not found`)
            }
            return album
        }

        throw new Error(`Unknown list type: ${type}`)
    }

    /**
     * Get basic artist info
     */
    async getArtistInfo(id: string): Promise<GenericSimpleArtist> {
        const artist = await localManager.loadArtist(id, 'local')
        if (!artist) {
            throw new Error(`Artist ${id} not found`)
        }

        return new GenericSimpleArtist(
            artist.id,
            artist.source,
            artist.name,
            artist.thumbnailURL
        )
    }

    /**
     * Get detailed artist information
     */
    async getArtistDetails(id: string): Promise<unknown> {
        const artist = await localManager.loadArtist(id, 'local')
        if (!artist) {
            throw new Error(`Artist ${id} not found`)
        }
        return artist
    }

    /**
     * Get local library home/overview
     */
    async getUserHome(): Promise<GenericUserHome> {
        const allSongs = await localManager.getAllLocalSongs()
        const allPlaylists = await localManager.loadAllPlaylists()
        const allAlbums = await localManager.loadAllAlbums()
        const allArtists = await localManager.loadAllArtists()

        // Extract unique artists from songs
        const artistMap = new Map<string, GenericSimpleArtist>()
        allSongs.forEach(song => {
            song.artists.forEach(artist => {
                if (!artistMap.has(artist.id)) {
                    artistMap.set(artist.id, artist)
                }
            })
        })

        const uniqueArtists = Array.from(artistMap.values())

        return {
            topTracks: allSongs.slice(0, 50), // Show up to 50 songs
            topArtists: uniqueArtists.slice(0, 50),
            followedArtists: uniqueArtists,
            followedAlbums: allAlbums || [],
            savedPlaylists: allPlaylists
        }
    }
}

export const localExtractor = new LocalExtractor()
