import YouTubeIcon from '@mui/icons-material/YouTube';
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import CloudIcon from '@mui/icons-material/Cloud';
import { Album, Artist, BaseSongList, Playlist, Song, Sources } from '../types/SongTypes';
import { SimplifiedArtist,
    Artist as SpotifyArtist, 
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

export function spotifySimpleArtistToArtist(spotifyArtist: SimplifiedArtist) {
    return new Artist(
        spotifyArtist.name,
        ""
    )
}

export function spotifyArtistToArtist(spotifyArtist: SpotifyArtist) {
    let imageUrl = ""
    if (spotifyArtist.images) {
        imageUrl = spotifyArtist.images[0].url
    }
    
    return new Artist(
        spotifyArtist.name,
        imageUrl
    )
}

export function spotifyTrackToSong(spotifyTrack: SpotifyTrack): Song {
    const artists: Artist[] = []
    spotifyTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToArtist(artist))
    })
    
    return new Song(
        spotifyTrack.name,
        artists,
        spotifyTrack.explicit,
        spotifyTrack.duration_ms / 1000,
        "spotify",
        spotifyTrack.album.images.length != 0 ? spotifyTrack.album.images[0].url : ""
    )
}

export function spotifySimpleTrackToSong(simpleTrack: SimplifiedTrack): Song {
    const artists: Artist[] = []
    simpleTrack.artists.forEach((artist) => {
        artists.push(spotifySimpleArtistToArtist(artist))
    })
    
    return new Song(
        simpleTrack.name,
        artists,
        simpleTrack.explicit,
        simpleTrack.duration_ms / 1000,
        "spotify",
        simpleTrack.preview_url
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
        spotifyPlaylist.owner.display_name,
        Songs,
        spotifyPlaylist.images[0].url,
        spotifyPlaylist.id,
    )
}

export function spotifyAlbumToAlbum(spotifyAlbum: SpotifyAlbum) {
    const Songs: Song[] = []
    spotifyAlbum.tracks.items.forEach((track) => Songs.push(spotifySimpleTrackToSong(track)))

    const Artists: Artist[] = []
    spotifyAlbum.artists.forEach((artist, index) => {
        Artists.push(spotifyArtistToArtist(artist))
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