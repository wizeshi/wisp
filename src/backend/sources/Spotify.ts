import fetch from 'node-fetch'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { spotifyAccessType, spotifySavedCredentials } from '../utils/types'
import { Market, SpotifyApi, User, UserProfile } from '@spotify/web-api-ts-sdk'
import { SidebarListType } from '../../frontend/types/SongTypes'
import { loadCredentials } from '../Credentials'

const tokenFilePath = path.join(app.getPath('userData'), 'spotify_tokens.json')

const getSpotifyClientId = async (): Promise<string> => {
    const credentials = await loadCredentials()
    if (!credentials || !credentials.spotifyClientId) {
        throw new Error('Spotify client ID not found')
    }
    return credentials.spotifyClientId
}

export const getSpotifyAccess = async (authCode: string): Promise<spotifyAccessType> => {
    isSpotifyLoggedIn().then((value) => {
        if (value.expired && !value.loggedIn) {
            refreshSpotifyAccess()
            return
        }
    })

    const credentials = await loadCredentials()
    if (!credentials || !credentials.spotifyClientId || !credentials.spotifyClientSecret) {
        throw new Error('Spotify credentials not found')
    }

    const response = await fetch('https://accounts.spotify.com/api/token', {
        method: "POST",
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
            grant_type: "authorization_code",
            code: authCode,
            redirect_uri: "wisp-login://callback",
            client_id: credentials.spotifyClientId,
            client_secret: credentials.spotifyClientSecret
        })
    });

    const data = await response.json()

    return (data as spotifyAccessType)
}

export const refreshSpotifyAccess = async () => {
    const credentials = await loadCredentials()
    if (!credentials || !credentials.spotifyClientId || !credentials.spotifyClientSecret) {
        throw new Error('Spotify credentials not found')
    }

    const tokens = await loadSpotifyCredentials()
    const refresh_token = tokens.refresh_token

    const response = await fetch('https://accounts.spotify.com/api/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token,
            client_id: credentials.spotifyClientId,
            client_secret: credentials.spotifyClientSecret,
        }),
    });

    const data = (await response.json() as spotifyAccessType);

    if (!data.refresh_token) {
        data.refresh_token = tokens.refresh_token
    }

    if (data.access_token) {
        saveSpotifyCredentials(data)
    }

    return data;
}

export const saveSpotifyCredentials = async (tokens: spotifyAccessType) => {
    const expires_at = Date.now() + tokens.expires_in * 1000

    const data = {
        ...tokens,
        expires_at: expires_at,
    }

    await fs.promises.writeFile(tokenFilePath, JSON.stringify(data, null, 2))
}

export const loadSpotifyCredentials = async (): Promise<spotifySavedCredentials> => {
    try {
        const data = await fs.promises.readFile(tokenFilePath, 'utf-8');
        return JSON.parse(data)
    } catch(err) {
        return null
    }
}

export const isSpotifyLoggedIn = async (): Promise<{ loggedIn: boolean, expired: boolean}> => {
    try {
        const data = await loadSpotifyCredentials()
        const now = Date.now()
        if (data.access_token && data.refresh_token && (data.expires_at > now)) {
            return { loggedIn: true, expired: false }
        } else if (data.access_token && data.refresh_token) {
            return { loggedIn: true, expired: true }
        }
    } catch (err) {
        return { loggedIn: false, expired: true }
    }
}

export const spotifySearch = async (query: string) => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();

    const spotify = SpotifyApi.withAccessToken(clientId, tokens)
    const market = (await spotify.currentUser.profile()).country

    const results = await spotify.search(query, [
        'album', 'artist', 'playlist', 'track'
    ], market as Market, 10)

    return results
}

export const loadSpotifyUserLists = async (type: SidebarListType) => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)

    switch (type) {
        case "Playlists":
            return (await spotify.currentUser.playlists.playlists()).items
        case "Albums":
            return (await spotify.currentUser.albums.savedAlbums()).items
        case 'Artists':
            return (await spotify.currentUser.followedArtists()).artists.items
    }
}

export const getSpotifyUserInfo = async (): Promise<UserProfile> => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)

    return (await spotify.currentUser.profile())
}

export const getSpotifyUserDetails = async (id: string): Promise<User> => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)

    return (await spotify.users.profile(id))
}

export const getSpotifyListDetails = async (type: "Playlist" | "Album" | "Artist", id: string) => {
    if (type == "Artist") {
        console.log("Wrong function called, redirecting...")
        return getSpotifyArtistDetails(id)
    }
    
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)

    switch (type) {
        case "Playlist":
            return (await spotify.playlists.getPlaylist(id))
        case "Album":
            return (await spotify.albums.get(id))
    }
}

export const getSpotifyArtistInfo = async (id: string) => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)

    const artistInfo = await spotify.artists.get(id)

    return artistInfo
}

export const getSpotifyArtistDetails = async (id: string) => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)
    const market = (await spotify.currentUser.profile()).country

    const artistInfo = await spotify.artists.get(id)
    const artistTopTracks = await spotify.artists.topTracks(id, market as Market)
    const artistAlbums = (await spotify.artists.albums(id)).items

    return {
        info: artistInfo,
        topTracks: artistTopTracks,
        albums: artistAlbums,
    }
}

export const getSpotifyUserHome = async () => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const clientId = await getSpotifyClientId()
    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(clientId, accessToken)
    
    const topTracks = (await spotify.currentUser.topItems("tracks", 'short_term', 5)).items
    const topArtists = (await spotify.currentUser.topItems("artists", 'short_term', 5)).items
    const followedArtists = (await spotify.currentUser.followedArtists()).artists.items
    const followedAlbums = (await spotify.currentUser.albums.savedAlbums()).items
    const savedPlaylists = (await spotify.currentUser.playlists.playlists()).items

    return {
        topTracks: topTracks,
        topArtists: topArtists,
        followedArtists: followedArtists,
        followedAlbums: followedAlbums,
        savedPlaylists: savedPlaylists
    }
}

export type SpotifyUserHome = Awaited<ReturnType<typeof getSpotifyUserHome>>
