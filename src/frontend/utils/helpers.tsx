import YouTubeIcon from '@mui/icons-material/YouTube';
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import CloudIcon from '@mui/icons-material/Cloud';
import { Album, Artist, BaseSongList, Playlist, Song, Sources } from '../types/SongTypes';
import { SimplifiedArtist, Artist as SpotifyArtist, Track as SpotifyTrack } from '@spotify/web-api-ts-sdk';


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
    return new Artist(
        spotifyArtist.name,
        spotifyArtist.images[0].url
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
        spotifyTrack.album.images[0].url
    )
}