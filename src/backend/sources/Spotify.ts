import fetch from 'node-fetch'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { spotifyAccessType, spotifySavedCredentials } from '../utils/types'
import { Artist, Market, SimplifiedAlbum, SpotifyApi, TopTracksResult } from '@spotify/web-api-ts-sdk'
import { SidebarListType, GenericSong, PlaylistItem } from '../../common/types/SongTypes'
import { loadCredentials } from '../Credentials'
import { GenericExtractor } from './Generic'
import { spotifyAlbumToGenericAlbum, spotifyArtistToGenericArtist, spotifyArtistToGenericSimpleArtist, spotifyPlaylistToGenericPlaylist, spotifySearchToGenericSearch, spotifySimplePlaylistToGenericPlaylist, spotifyTrackToGenericSong, spotifyUserHomeToGenericUserHome, spotifyUserProfileToGenericUserProfile, spotifyUserToGenericUser } from '../../common/Sources/SpotifyHelpers'
import { localManager } from '../LocalManager'

const tokenFilePath = path.join(app.getPath('userData'), 'spotify_tokens.json')

export type SpotifyArtistDetails = {
    info: Artist,
    topTracks: TopTracksResult,
    albums: SimplifiedAlbum[]
}

class SpotifyExtractor extends GenericExtractor {
    private clientId: string;
    private clientSecret: string;
    private initPromise: Promise<void>;
    private cachedMarket: Market | null = null;
    
    constructor() {
        super()
        this.initPromise = this.initialize()
    }

    private async initialize() {
        const credentials = await loadCredentials()
        if (!credentials || !credentials.spotifyClientId || !credentials.spotifyClientSecret) {
            throw new Error('Spotify credentials not found')
        }
        this.clientId = credentials.spotifyClientId
        this.clientSecret = credentials.spotifyClientSecret
    }

    private async ensureInitialized() {
        await this.initPromise
    }
    async getAccess(authCode: string): Promise<spotifyAccessType> {
        await this.ensureInitialized()
    
        const response = await fetch('https://accounts.spotify.com/api/token', {
            method: "POST",
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            },
            body: new URLSearchParams({
                grant_type: "authorization_code",
                code: authCode,
                redirect_uri: "wisp-login://callback",
                client_id: this.clientId,
                client_secret: this.clientSecret
            })
        });
    
        const data = await response.json() as spotifyAccessType
        
        // Save the tokens immediately after getting them
        if (data.access_token) {
            await this.saveTokens(data)
        }
    
        return data
    }
    
    async refreshAccess() {
        await this.ensureInitialized()
    
        const tokens = await this.loadTokens()
        const refresh_token = tokens.refresh_token
    
        const response = await fetch('https://accounts.spotify.com/api/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'refresh_token',
                refresh_token,
                client_id: this.clientId,
                client_secret: this.clientSecret,
            }),
        });
    
        const data = (await response.json() as spotifyAccessType);
    
        if (!data.refresh_token) {
            data.refresh_token = tokens.refresh_token
        }
    
        if (data.access_token) {
            await this.saveTokens(data)
        }
    
        return data;
    }
    
    async saveTokens(tokens: spotifyAccessType) {
        const data: spotifySavedCredentials = {
            ...tokens,
            expires_at: Date.now() + tokens.expires_in * 1000,
        }
    
        await fs.promises.writeFile(tokenFilePath, JSON.stringify(data, null, 2))
    }
    
    async loadTokens(): Promise<spotifySavedCredentials> {
        try {
            const data = await fs.promises.readFile(tokenFilePath, 'utf-8');
            return JSON.parse(data)
        } catch(err) {
            return null
        }
    }
    
    async isLoggedIn(): Promise<{ loggedIn: boolean, expired: boolean}> {
        const data = await this.loadTokens()
        if (!data || !data.access_token || !data.refresh_token) {
            return { loggedIn: false, expired: true }
        }
        
        const now = Date.now()
        const expired = data.expires_at <= now
        
        return { loggedIn: true, expired }
    }

    private async getSpotifyClient(): Promise<SpotifyApi> {
        await this.ensureInitialized()
        
        const loginStatus = await this.isLoggedIn()
        if (loginStatus.expired) {
            await this.refreshAccess()
        }

        const tokens = await this.loadTokens()
        const accessToken = {
            ...tokens,
            expires: tokens.expires_at 
        }

        return SpotifyApi.withAccessToken(this.clientId, accessToken)
    }

    private async getMarket(spotify: SpotifyApi): Promise<Market> {
        if (!this.cachedMarket) {
            const profile = await spotify.currentUser.profile()
            this.cachedMarket = profile.country as Market
        }
        return this.cachedMarket
    }
    
    async search(query: string) {
        const spotify = await this.getSpotifyClient()
        const market = await this.getMarket(spotify)
    
        return spotifySearchToGenericSearch(await spotify.search(query, [
            'album', 'artist', 'playlist', 'track'
        ], market, 10))
    }
    
    async getUserLists(type: SidebarListType) {
        const spotify = await this.getSpotifyClient()
    
        switch (type) {
            case "Playlists": {
                const items = (await spotify.currentUser.playlists.playlists()).items
                return items.map(spotifySimplePlaylistToGenericPlaylist)
            }
            case "Albums": {
                const items = ((await spotify.currentUser.albums.savedAlbums()).items)
                return items.map((item) => spotifyAlbumToGenericAlbum(item.album))
            }
            case 'Artists': {
                const items = ((await spotify.currentUser.followedArtists()).artists.items)
                return items.map(spotifyArtistToGenericSimpleArtist)
            }
        }
    }

    async getUserInfo() {
        const spotify = await this.getSpotifyClient()
        return spotifyUserProfileToGenericUserProfile(await spotify.currentUser.profile())
    }
    
    async getUserDetails(id: string) {
        const spotify = await this.getSpotifyClient()
        return spotifyUserToGenericUser(await spotify.users.profile(id))
    }
    
    async getListDetails(type: "Playlist" | "Album" | "Artist", id: string) {
        if (type === "Artist") {
            console.log("Wrong function called, redirecting...")
            return this.getArtistDetails(id)
        }
        
        const spotify = await this.getSpotifyClient()
    
        if (type === "Playlist") {
            // Check if we have a cached version with local songs
            const cachedPlaylist = await localManager.loadPlaylist(id, 'spotify')
            if (cachedPlaylist) {
                const hasLocalSongs = cachedPlaylist.songs.some((song: GenericSong) => song.source === 'local')
                // If playlist has local songs, return cached version instead of refreshing
                if (hasLocalSongs) {
                    console.log(`Playlist ${id} has local songs, using cached version`)
                    return cachedPlaylist
                }
            }
            
            // No local songs or no cache, fetch fresh data from Spotify
            const result = spotifyPlaylistToGenericPlaylist((await spotify.playlists.getPlaylist(id)))
            
            // Cache the playlist
            await localManager.savePlaylist(result)
            
            // Cache all songs in the playlist
            if (result.songs) {
                for (const song of result.songs) {
                    await localManager.saveSong(song)
                }
            }
            
            return result
        } else {
            // Check if we have a cached version with local songs
            const cachedAlbum = await localManager.loadAlbum(id, 'spotify')
            if (cachedAlbum) {
                const hasLocalSongs = cachedAlbum.songs.some((song: GenericSong) => song.source === 'local')
                // If album has local songs, return cached version instead of refreshing
                if (hasLocalSongs) {
                    console.log(`Album ${id} has local songs, using cached version`)
                    return cachedAlbum
                }
            }
            
            // No local songs or no cache, fetch fresh data from Spotify
            const result = spotifyAlbumToGenericAlbum(await spotify.albums.get(id))
            
            // Cache the album
            await localManager.saveAlbum(result)
            
            // Cache all songs in the album
            if (result.songs) {
                for (const song of result.songs) {
                    await localManager.saveSong(song)
                }
            }
            
            return result
        }
    }
    
    async getArtistInfo(id: string) {
        const spotify = await this.getSpotifyClient()
        return spotifyArtistToGenericSimpleArtist(await spotify.artists.get(id))
    }
    
    async getArtistDetails(id: string) {
        const spotify = await this.getSpotifyClient()
        const market = await this.getMarket(spotify)
    
        const [artistInfo, artistTopTracks, artistAlbumsResponse] = await Promise.all([
            spotify.artists.get(id),
            spotify.artists.topTracks(id, market),
            spotify.artists.albums(id)
        ])
    
        return spotifyArtistToGenericArtist({
            info: artistInfo,
            topTracks: artistTopTracks,
            albums: artistAlbumsResponse.items,
        })
    }
    
    async getUserHome() {
        const spotify = await this.getSpotifyClient()
        
        const [topTracksRes, topArtistsRes, followedArtistsRes, followedAlbumsRes, savedPlaylistsRes] = await Promise.all([
            spotify.currentUser.topItems("tracks", 'short_term', 5),
            spotify.currentUser.topItems("artists", 'short_term', 5),
            spotify.currentUser.followedArtists(),
            spotify.currentUser.albums.savedAlbums(),
            spotify.currentUser.playlists.playlists()
        ])
    
        return spotifyUserHomeToGenericUserHome({
            topTracks: topTracksRes.items,
            topArtists: topArtistsRes.items,
            followedArtists: followedArtistsRes.artists.items,
            followedAlbums: followedAlbumsRes.items.map(item => item.album),
            savedPlaylists: savedPlaylistsRes.items
        })
    }

    // Force refresh from Spotify API, removing local songs
    async forceRefreshListDetails(type: "Playlist" | "Album", id: string) {
        const spotify = await this.getSpotifyClient()
    
        if (type === "Playlist") {
            // Fetch fresh data from Spotify
            const result = spotifyPlaylistToGenericPlaylist(await spotify.playlists.getPlaylist(id))
            
            // Cache the playlist (this will overwrite any version with local songs)
            await localManager.savePlaylist(result)
            
            // Cache all songs in the playlist
            if (result.songs) {
                for (const song of result.songs) {
                    await localManager.saveSong(song)
                }
            }
            
            return result
        } else {
            // Fetch fresh data from Spotify
            const result = spotifyAlbumToGenericAlbum(await spotify.albums.get(id))
            
            // Cache the album (this will overwrite any version with local songs)
            await localManager.saveAlbum(result)
            
            // Cache all songs in the album
            if (result.songs) {
                for (const song of result.songs) {
                    await localManager.saveSong(song)
                }
            }
            
            return result
        }
    }

    async getUserLikes(offset?: number) {
        const spotify = await this.getSpotifyClient()
        const market = await this.getMarket(spotify)
        const response = await spotify.currentUser.tracks.savedTracks(50, offset, market)

        const playlistItems = response.items.map((item, index) => {
            return {
                ...spotifyTrackToGenericSong(item.track),
                addedAt: new Date(item.added_at),
                trackNumber: (offset || 0) + index + 1
            } as PlaylistItem
        })

        // Return a GenericPlaylist structure for consistency
        const totalDuration = playlistItems.reduce((acc, song) => acc + (song.durationSecs || 0), 0)
        const hours = Math.floor(totalDuration / 3600)
        const minutes = Math.floor((totalDuration % 3600) / 60)
        const durationFormatted = hours > 0 ? `${hours}:${minutes.toString().padStart(2, '0')}:${(totalDuration % 60).toString().padStart(2, '0')}` : `${minutes}:${(totalDuration % 60).toString().padStart(2, '0')}`

        return {
            id: 'liked-songs',
            title: 'Liked Songs',
            description: 'Your liked songs from Spotify',
            thumbnailURL: 'https://misc.scdn.co/liked-songs/liked-songs-300.png',
            author: {
                id: '',
                name: '',
                avatarURL: ''
            },
            songs: playlistItems,
            source: 'spotify' as const,
            durationFormatted,
            durationSecs: totalDuration,
            // Add pagination info
            total: response.total,
            hasMore: response.next !== null
        }
    }
}

export const spotifyExtractor = new SpotifyExtractor()
export type SpotifyUserHome = Awaited<ReturnType<typeof spotifyExtractor.getUserHome>>