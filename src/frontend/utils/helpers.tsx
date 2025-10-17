import YouTubeIcon from '@mui/icons-material/YouTube';
import CloudIcon from '@mui/icons-material/Cloud';
import LanIcon from '@mui/icons-material/Lan';
import { GenericAlbum, GenericSimpleArtist, GenericPlaylist, SongSources, GenericSimpleAlbum, GenericArtist, GenericSong } from '../../common/types/SongTypes';
import Avatar from '@mui/material/Avatar';
import { SxProps } from '@mui/material';
import { Theme } from '@mui/material/styles';


export const getServiceIcon = (service: SongSources, style?: SxProps<Theme>) => {
    switch (service) {
        default:
        case 'local':
            return (
                <Avatar sx={{...style, bgcolor: "transparent"}}>
                    <LanIcon sx={{ color: "#1976d2" }}/>
                </Avatar>
            )
        case "youtube":
            return (
                <Avatar sx={{...style, bgcolor: "transparent"}}>
                    <YouTubeIcon sx={{ color: "#FF0033" }}/>
                </Avatar>
            )
        case "spotify":
            return (
                <Avatar sx={style} src="https://storage.googleapis.com/pr-newsroom-wp/1/2023/05/Spotify_Primary_Logo_RGB_Green.png" alt="Spotify Logo"/>
            )
        case "soundcloud":
            return (
                <Avatar sx={style}>
                    <CloudIcon />
                </Avatar>
            )
    }
}

export const isSong = (item: unknown): item is GenericSong => {
    return (
        item instanceof GenericSong ||
        (typeof item === 'object' && item !== null && 'title' in item && 'artists' in item && 'durationSecs' in item)
    )
}

// Type guard for GenericSimpleAlbum - has artists, releaseDate, label but NO songs
export const isSimpleAlbum = (item: unknown): item is GenericSimpleAlbum => {
    return (
        item instanceof GenericSimpleAlbum ||
        (typeof item === 'object' && item !== null && 'artists' in item && 'releaseDate' in item && 'label' in item && !('songs' in item))
    )
}

// Type guard for GenericAlbum - extends GenericSimpleAlbum but also has songs and explicit
export const isAlbum = (item: unknown): item is GenericAlbum => {
    return (
        item instanceof GenericAlbum ||
        (typeof item === 'object' && item !== null && 'artists' in item && 'explicit' in item && 'releaseDate' in item && 'label' in item && 'songs' in item && 'title' in item)
    )
}

// Type guard for GenericPlaylist - has author and songs
export const isPlaylist = (item: unknown): item is GenericPlaylist => {
    return (
        item instanceof GenericPlaylist ||
        (typeof item === 'object' && item !== null && 'author' in item && 'songs' in item && 'title' in item)
    )
}

// Type guard for GenericSimpleArtist - has name and thumbnailURL but NOT monthlyListeners/topSongs
export const isSimpleArtist = (item: unknown): item is GenericSimpleArtist => {
    return (
        item instanceof GenericSimpleArtist ||
        (typeof item === 'object' && item !== null && 'name' in item && 'thumbnailURL' in item && !('monthlyListeners' in item))
    )
}

// Type guard for GenericArtist - extends GenericSimpleArtist but also has monthlyListeners, topSongs, albums
export const isArtist = (item: unknown): item is GenericArtist => {
    return (
        item instanceof GenericArtist ||
        (typeof item === 'object' && item !== null && 'name' in item && 'thumbnailURL' in item && 'monthlyListeners' in item && 'topSongs' in item && 'albums' in item)
    )
}
