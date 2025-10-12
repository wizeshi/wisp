import YouTubeIcon from '@mui/icons-material/YouTube';
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import CloudIcon from '@mui/icons-material/Cloud';
import { Album, Artist, BaseSongList, Playlist, SimpleAlbum, SimpleArtist, Song, Sources, spotifyArtistDetails } from '../types/SongTypes';
import { SimplifiedArtist,
    Artist as SpotifyArtist,
    SimplifiedAlbum as SpotifySimplifiedAlbum,
    Track as SpotifyTrack,
    TrackItem as SpotifyTrackItem,
    Playlist as SpotifyPlaylist,
    Album as SpotifyAlbum,
    SimplifiedTrack,
} from '@spotify/web-api-ts-sdk';


export const getServiceIcon = (service: Sources) => {
    let serviceIcon

    switch (service) {
        default:
        case "youtube":
            serviceIcon = <YouTubeIcon />
            break
        case "spotify":
            serviceIcon = <GraphicEqIcon />
            break
        case "soundcloud":
            serviceIcon = <CloudIcon />
            break
    }

    return serviceIcon   
}

export const getListType = (list: Album | Playlist | BaseSongList)  => {
    let listType = ""
    
    if (list instanceof Album) {
        listType = "Album"
    }
    if (list instanceof Playlist) {
        listType = "Playlist"
    }

    return listType
}

/* export function spotifySimpleArtistToArtist(spotifyArtist: SimplifiedArtist) {
    return new Artist(
        spotifyArtist.name,
        ""
    )
} */

export function spotifySimpleArtistToSimpleArtist(spotifyArtist: SimplifiedArtist) {
    return new SimpleArtist(
        spotifyArtist.id,
        spotifyArtist.name,
        ""
    )
}

export function spotifyArtistToArtist(spotifyArtist: spotifyArtistDetails) {
    let imageUrl = ""
    if (spotifyArtist.info.images) {
        imageUrl = spotifyArtist.info.images[0].url
    }

    const albums = spotifyArtist.albums.map((album) => {
        return spotifySimpleAlbumToSimpleAlbum(album)
    })

    const topSongs = spotifyArtist.topTracks.tracks.map((track) => {
        return spotifyTrackToSong(track)
    })
    
    return new Artist(
        spotifyArtist.info.id,
        spotifyArtist.info.name,
        imageUrl,
        spotifyArtist.info.followers.total,
        topSongs,
        albums,
    )
}

export function spotifyArtistToSimpleArtist(spotifyArtist: SpotifyArtist) {
    let imageUrl = ""
    if (spotifyArtist.images) {
        imageUrl = spotifyArtist.images[0].url
    }
    
    return new SimpleArtist(
        spotifyArtist.id,
        spotifyArtist.name,
        imageUrl
    )
}

export function spotifyTrackToSong(spotifyTrack: SpotifyTrack): Song {
    const artists: SimpleArtist[] = []
    spotifyTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToSimpleArtist(artist))
    })
    
    return new Song(
        spotifyTrack.name,
        artists,
        spotifyTrack.explicit,
        spotifyTrack.duration_ms / 1000,
        "spotify",
        spotifyTrack.album.images.length != 0 ? spotifyTrack.album.images[0].url : "",
        spotifyTrack.id
    )
}

export function spotifySimpleTrackToSong(simpleTrack: SimplifiedTrack, thumbnailURL: string): Song {
    const artists: SimpleArtist[] = []
    simpleTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToSimpleArtist(artist))
    })
    
    return new Song(
        simpleTrack.name,
        artists,
        simpleTrack.explicit,
        simpleTrack.duration_ms / 1000,
        "spotify",
        thumbnailURL,
        simpleTrack.id
    )
}

const isSpotifyTrack = (item: SpotifyTrackItem): item is SpotifyTrack => {
    return item.type === "track"
}

export function spotifyPlaylistToPlaylist(spotifyPlaylist: SpotifyPlaylist<SpotifyTrackItem>) {
    const Songs: Song[] = []
    spotifyPlaylist.tracks.items.forEach((track) => Songs.push(spotifyTrackToSong(
        isSpotifyTrack(track.track) && track.track 
    )))

    return new Playlist(
        spotifyPlaylist.name,
        { 
            name: spotifyPlaylist.owner.display_name,
            id: spotifyPlaylist.owner.id
        },
        Songs,
        spotifyPlaylist.images[0].url,
        spotifyPlaylist.id,
    )
}

export function spotifyAlbumToAlbum(spotifyAlbum: SpotifyAlbum) {
    const Songs: Song[] = []
    spotifyAlbum.tracks.items.forEach((track) => Songs.push(spotifySimpleTrackToSong(track, spotifyAlbum.images[0].url)))

    const Artists: SimpleArtist[] = []
    spotifyAlbum.artists.forEach((artist, index) => {
        Artists.push(spotifyArtistToSimpleArtist(artist))
    })


    return new Album(
        spotifyAlbum.name,
        Artists,
        spotifyAlbum.copyrights[0].text,
        new Date(),
        true,
        Songs,
        spotifyAlbum.images[0].url,
        spotifyAlbum.id,
    )
}

export function spotifySimpleAlbumToSimpleAlbum(spotifyAlbum: SpotifySimplifiedAlbum) {
    const Artists: SimpleArtist[] = []
    spotifyAlbum.artists.forEach((artist, index) => {
        Artists.push(spotifySimpleArtistToSimpleArtist(artist))
    })

    return new SimpleAlbum(
        spotifyAlbum.id,
        spotifyAlbum.name,
        spotifyAlbum.images[0].url,
        Artists,
        new Date(spotifyAlbum.release_date),
        (spotifyAlbum.copyrights) ? spotifyAlbum.copyrights[0].text : ""
    )
}