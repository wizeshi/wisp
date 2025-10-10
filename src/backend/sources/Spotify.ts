import fetch from 'node-fetch'
import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { spotifyAccessType, spotifySavedCredentials } from '../utils/types'
import { Market, SpotifyApi, UserProfile } from '@spotify/web-api-ts-sdk'
import { SidebarItemType, SidebarListType } from '../../frontend/types/SongTypes'

const tokenFilePath = path.join(app.getPath('userData'), 'spotify_tokens.json')

const client_id = process.env.SPOTIFY_CLIENT_ID
const client_secret = process.env.SPOTIFY_CLIENT_SECRET;

export const getSpotifyAccess = async (authCode: string): Promise<spotifyAccessType> => {
    isSpotifyLoggedIn().then((value) => {
        if (value.expired && value.loggedIn) {
            refreshSpotifyAccess()
            return
        }
    })

    const response = await fetch('https://accounts.spotify.com/api/token', {
        method: "POST",
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
            grant_type: "authorization_code",
            code: authCode,
            redirect_uri: "http://127.0.0.1:5173/callback",
            client_id: client_id,
            client_secret: client_secret
        })
    });

    const data = await response.json()

    return (data as spotifyAccessType)
}

export const refreshSpotifyAccess = async () => {
    const tokens = await loadSpotifyCredentials()
    const refresh_token = tokens.refresh_token

    const response = await fetch('https://accounts.spotify.com/api/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token,
            client_id,
            client_secret,
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

    const tokens = await loadSpotifyCredentials();

    const spotify = SpotifyApi.withAccessToken(client_id, tokens)
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

    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(client_id, accessToken)

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

    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(client_id, accessToken)

    return (await spotify.currentUser.profile())
}

export const getSpotifyListDetails = async (type: SidebarItemType, id: string) => {
    if ((await isSpotifyLoggedIn()).expired) {
        await refreshSpotifyAccess()
    }

    const tokens = await loadSpotifyCredentials();
    const accessToken = {
        ...tokens,
        expires: tokens.expires_at 
    }

    const spotify = SpotifyApi.withAccessToken(client_id, accessToken)

    switch (type) {
        case "Playlist":
            return (await spotify.playlists.getPlaylist(id))
        case "Album":
            return (await spotify.albums.get(id))
    }
}