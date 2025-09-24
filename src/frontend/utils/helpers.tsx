import YouTubeIcon from '@mui/icons-material/YouTube';
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import CloudIcon from '@mui/icons-material/Cloud';
import { Album, BaseSongList, Playlist, Sources } from './types';


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