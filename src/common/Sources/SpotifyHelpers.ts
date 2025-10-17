import {
    SearchResults as SpotifySearchResults,
    SimplifiedArtist as SpotifySimplifiedArtist,
    Artist as SpotifyArtist,
    Track as SpotifyTrack,
    Album as SpotifyAlbum,
    Playlist as SpotifyPlaylist,
    SimplifiedTrack as SimplifiedTrack,
    TrackItem as SpotifyTrackItem,
    SimplifiedAlbum as SpotifySimplifiedAlbum,
    SimplifiedPlaylist as SpotifySimplifiedPlaylist,
    UserProfile as SpotifyUserProfile,
    User as SpotifyUser,
    ItemTypes
} from "@spotify/web-api-ts-sdk";
import { GenericSearch, GenericUserHome } from "../types/SourcesTypes";
import { GenericAlbum, GenericArtist, GenericPlaylist, GenericSimpleAlbum, GenericSimpleArtist, GenericSong, GenericUser, GenericSimpleUser, PlaylistItem } from "../types/SongTypes";
import { SpotifyArtistDetails } from "../../backend/sources/Spotify";



export function spotifySimpleArtistToGenericSimpleArtist(spotifyArtist: SpotifySimplifiedArtist) {
    return new GenericSimpleArtist(
        spotifyArtist.id,
        "spotify",
        spotifyArtist.name,
        ""
    )
}

export function spotifyArtistToGenericArtist(spotifyArtist: SpotifyArtistDetails) {
    let imageUrl = ""
    if (spotifyArtist.info.images) {
        imageUrl = spotifyArtist.info.images[0].url
    }

    const albums = spotifyArtist.albums.map((album) => {
        return spotifySimpleAlbumToGenericSimpleAlbum(album)
    })

    const topSongs = spotifyArtist.topTracks.tracks.map((track) => {
        return spotifyTrackToGenericSong(track)
    })
    
    return new GenericArtist(
        spotifyArtist.info.id,
        "spotify",
        spotifyArtist.info.name,
        imageUrl,
        spotifyArtist.info.followers.total,
        topSongs,
        albums,
    )
}

export function spotifyArtistToGenericSimpleArtist(spotifyArtist: SpotifyArtist) {
    let imageUrl = ""
    if (spotifyArtist.images) {
        imageUrl = spotifyArtist.images[0].url
    }
    
    return new GenericSimpleArtist(
        spotifyArtist.id,
        "spotify",
        spotifyArtist.name,
        imageUrl
    )
}

export function spotifyTrackToGenericSong(spotifyTrack: SpotifyTrack): GenericSong {
    const artists: GenericSimpleArtist[] = []
    spotifyTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToGenericSimpleArtist(artist))
    })
    
    return new GenericSong(
        spotifyTrack.name,
        artists,
        spotifyTrack.explicit,
        spotifyTrack.duration_ms / 1000,
        "spotify",
        spotifyTrack.id,
        spotifyTrack.album.images.length != 0 ? spotifyTrack.album.images[0].url : "",
        spotifySimpleAlbumToGenericSimpleAlbum(spotifyTrack.album),
    )
}

export function spotifySimpleTrackToGenericSong(simpleTrack: SimplifiedTrack, thumbnailURL: string): GenericSong {
    const artists: GenericSimpleArtist[] = []
    simpleTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToGenericSimpleArtist(artist))
    })
    
    return new GenericSong(
        simpleTrack.name,
        artists,
        simpleTrack.explicit,
        simpleTrack.duration_ms / 1000,
        "spotify",
        simpleTrack.id,
        thumbnailURL,
    )
}

const isSpotifyTrack = (item: SpotifyTrackItem): item is SpotifyTrack => {
    return item.type === "track"
}

export function spotifyPlaylistToGenericPlaylist(spotifyPlaylist: SpotifyPlaylist<SpotifyTrack>) {
    const Songs: PlaylistItem[] = []
    spotifyPlaylist.tracks.items.forEach((track) => Songs.push(
        new PlaylistItem(
            track.track.name,
            track.track.artists.map(spotifySimpleArtistToGenericSimpleArtist),
            track.track.explicit,
            track.track.duration_ms / 1000,
            "spotify",
            track.track.id,
            track.track.album.images[0].url,
            new Date(track.added_at),
            spotifyPlaylist.tracks.items.findIndex(t => t === track) + 1,
            isSpotifyTrack(track.track) ? spotifySimpleAlbumToGenericSimpleAlbum(track.track.album) : undefined,
        )
    ))

    const author: GenericSimpleUser = new GenericSimpleUser(
        spotifyPlaylist.owner.id,
        "spotify",
        spotifyPlaylist.owner.display_name,
        spotifyPlaylist.owner.external_urls.spotify,
        0,
        spotifyPlaylist.owner.external_urls.spotify,
    )

    return new GenericPlaylist(
        spotifyPlaylist.name,
        author,
        Songs,
        spotifyPlaylist.images[0].url,
        spotifyPlaylist.id,
        "spotify",
    )
}

export function spotifySimplePlaylistToGenericPlaylist(spotifyPlaylist: SpotifySimplifiedPlaylist) {
    const author: GenericSimpleUser = new GenericSimpleUser(
        spotifyPlaylist.owner.id,
        "spotify",
        spotifyPlaylist.owner.display_name ?? "",
        spotifyPlaylist.owner.external_urls.spotify,
        0,
        spotifyPlaylist.owner.external_urls.spotify,
    )

    return new GenericPlaylist(
        spotifyPlaylist.name,
        author,
        [],
        spotifyPlaylist.images[0].url,
        spotifyPlaylist.id,
        "spotify"
    )
}

export function spotifyAlbumToGenericAlbum(spotifyAlbum: SpotifyAlbum) {
    const Songs: GenericSong[] = []
    spotifyAlbum.tracks.items.forEach((track) => Songs.push(spotifySimpleTrackToGenericSong(track, spotifyAlbum.images[0].url)))

    const Artists: GenericSimpleArtist[] = []
    spotifyAlbum.artists.forEach((artist, index) => {
        Artists.push(spotifyArtistToGenericSimpleArtist(artist))
    })


    return new GenericAlbum(
        spotifyAlbum.name,
        Artists,
        spotifyAlbum.copyrights[0].text,
        new Date(),
        true,
        Songs,
        spotifyAlbum.images[0].url,
        spotifyAlbum.id,
        "spotify"
    )
}

export function spotifySimpleAlbumToGenericSimpleAlbum(spotifyAlbum: SpotifySimplifiedAlbum) {
    const Artists: GenericSimpleArtist[] = []
    spotifyAlbum.artists.forEach((artist, index) => {
        Artists.push(spotifySimpleArtistToGenericSimpleArtist(artist))
    })

    const albumImage = (spotifyAlbum && spotifyAlbum.images && spotifyAlbum.images.length > 0) ? spotifyAlbum.images[0].url : ""

    return new GenericSimpleAlbum(
        spotifyAlbum.id,
        "spotify",
        spotifyAlbum.name,
        albumImage,
        Artists,
        new Date(spotifyAlbum.release_date),
        (spotifyAlbum.copyrights) ? spotifyAlbum.copyrights[0].text : ""
    )
}

export function spotifySearchToGenericSearch(spotifySearch: SpotifySearchResults<readonly ItemTypes[]>): GenericSearch {
    // Convert tracks to GenericSong[]
    const songs: GenericSong[] = spotifySearch.tracks?.items
        .filter((track: SpotifyTrack) => track != null)
        .map((track: SpotifyTrack) => spotifyTrackToGenericSong(track)) ?? []

    // Convert albums to GenericAlbum[]
    const albums: GenericAlbum[] = spotifySearch.albums?.items
        .filter((album: SpotifySimplifiedAlbum) => album != null)
        .map((album: SpotifySimplifiedAlbum) => {
            const Songs: GenericSong[] = []
            const Artists: GenericSimpleArtist[] = album.artists
                ?.filter((artist: SpotifySimplifiedArtist) => artist != null)
                .map((artist: SpotifySimplifiedArtist) => 
                    spotifySimpleArtistToGenericSimpleArtist(artist)
                ) ?? []

            return new GenericAlbum(
                album.name,
                Artists,
                "", // label not available in search results
                new Date(album.release_date),
                false, // explicit not available in simplified album
                Songs, // tracks not included in search results
                album.images?.[0]?.url ?? "",
                album.id,
                "spotify" 
            )
        }) ?? []

    // Convert playlists to GenericPlaylist[]
    const playlists: GenericPlaylist[] = spotifySearch.playlists?.items
        .filter((playlist: SpotifyPlaylist) => playlist != null)
        .map((playlist: SpotifyPlaylist) => {
            const author: GenericSimpleUser = new GenericSimpleUser(
                playlist.owner.id,
                "spotify",
                playlist.owner.display_name ?? "",
                playlist.owner.external_urls.spotify,
                0,
                playlist.owner.external_urls.spotify,
            )

            return new GenericPlaylist(
                playlist.name,
                author,
                [], // tracks not included in search results
                playlist.images?.[0]?.url ?? "",
                playlist.id,
                "spotify"
            )
        }) ?? []

    // Convert artists to GenericArtist[]
    const artists: GenericArtist[] = spotifySearch.artists?.items
        .filter((artist: SpotifyArtist) => artist != null)
        .map((artist: SpotifyArtist) => {
            return new GenericArtist(
                artist.id,
                "spotify",
                artist.name,
                artist.images?.[0]?.url ?? "",
                artist.followers.total,
                [], // top songs not included in search results
                [], // albums not included in search results
            )
        }) ?? []

    return {
        songs,
        albums,
        playlists,
        artists
    }
}

export function spotifyUserProfileToGenericUserProfile(spotifyUserProfile: SpotifyUserProfile): GenericUser {
    return new GenericUser(
        spotifyUserProfile.id,
        "spotify",
        spotifyUserProfile.display_name,
        spotifyUserProfile.images[0].url ?? "",
        spotifyUserProfile.followers?.total,
        spotifyUserProfile.external_urls.spotify,
        spotifyUserProfile.email,
        spotifyUserProfile.country,
    )
}

export function spotifyUserToGenericUser(spotifyUser: SpotifyUser): GenericSimpleUser {
    return new GenericSimpleUser(
        spotifyUser.id,
        "spotify", 
        spotifyUser.display_name,
        spotifyUser.images[0].url ?? "",
        spotifyUser.followers?.total,
        spotifyUser.external_urls.spotify,
    )
}

export function spotifyUserHomeToGenericUserHome(spotifyUserHome: {
    topTracks: SpotifyTrack[],
    topArtists: SpotifyArtist[],
    followedArtists: SpotifyArtist[],
    followedAlbums: SpotifyAlbum[],
    savedPlaylists: SpotifySimplifiedPlaylist[],
}): GenericUserHome {
    return {
        topTracks: spotifyUserHome.topTracks.map(track => spotifyTrackToGenericSong(track)),
        topArtists: spotifyUserHome.topArtists.map(artist => spotifyArtistToGenericSimpleArtist(artist)),
        followedArtists: spotifyUserHome.followedArtists.map(artist => spotifyArtistToGenericSimpleArtist(artist)),
        followedAlbums: spotifyUserHome.followedAlbums.map(album => spotifyAlbumToGenericAlbum(album)),
        savedPlaylists: spotifyUserHome.savedPlaylists.map(playlist => spotifySimplePlaylistToGenericPlaylist(playlist)),
    }
}