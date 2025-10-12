import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { Album, Playlist, Song } from "../types/SongTypes"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import List from "@mui/material/List"
import ListItem from "@mui/material/ListItem"
import ListItemButton from "@mui/material/ListItemButton"
import Link from "@mui/material/Link"
import ExplicitIcon from '@mui/icons-material/Explicit';
import IconButton from "@mui/material/IconButton"
import PlayArrow from "@mui/icons-material/PlayArrow"
import { getServiceIcon, spotifyAlbumToAlbum, spotifyPlaylistToPlaylist } from "../utils/Helpers"
import Fab from "@mui/material/Fab"
import { useSettings } from "../hooks/useSettings"
import Skeleton from "@mui/material/Skeleton"
import { DotRowSeparator } from "../components/DotRowSeparator"
import AvatarGroup from "@mui/material/AvatarGroup"

export const ListScreen: React.FC = () => {
    const { app, music } = useAppContext()
    const [ overIndex, setOverIndex ] = useState<number>(0)
    const [list, setList] = useState<Album | Playlist | undefined>(undefined)
    const [hoverOverHeader, setHoverOverHeader] = useState(false)
    const [artistImages, setArtistImages] = useState<string[]>([])
    const { settings, loading, updateSettings }= useSettings()

    useEffect(() => {
        const fetchLists = async () => {
            if (app.screen.shownThing.type == "Album") {
                const album = await window.electronAPI.extractors.spotify.getListInfo("Album", app.screen.shownThing.id)
                const artistImagesPromise = album.artists.map(async (oldArtist) => {
                    const artist = await window.electronAPI.extractors.spotify.getArtistInfo(oldArtist.id)
                    return artist.images[0].url
                })

                const artistImagesURL = await Promise.all(artistImagesPromise)
                setArtistImages(artistImagesURL)
                console.log(artistImagesURL)
                setList(
                    spotifyAlbumToAlbum(album)
                )
            }

            if (app.screen.shownThing.type == "Playlist") {
                const playlist = await window.electronAPI.extractors.spotify.getListInfo("Playlist", app.screen.shownThing.id)
                console.log(playlist)
                setArtistImages([
                    (await window.electronAPI.extractors.spotify.getUserDetails(playlist.owner.id)).images[0].url
                ])
                setList(
                    spotifyPlaylistToPlaylist(playlist)
                )
            }
        }

        fetchLists()
    }, [app.screen.shownThing])

    const handlePlay = (song: Song) => {
        const songInQueueIndex = music.player.queue.findIndex(queueSong => queueSong == song)
        if (songInQueueIndex != -1) {
            // Song already in queue, just play it
            music.player.goToIndex(songInQueueIndex)
        } else {
            switch(settings.listPlay) {
                case "Single": {
                    // Add only this song to queue and play it
                    music.player.setQueue([song], 0)
                    break
                }
                case "Multiple": {
                    // Add all songs from the list to queue
                    // Find and play the selected song (comparing by title and artists)
                    const songIndex = list.songs.findIndex(s => 
                        s.title === song.title && 
                        s.artists.length === song.artists.length &&
                        s.artists.every((artist, i) => artist.name === song.artists[i].name)
                    )
                    music.player.setQueue(list.songs, songIndex !== -1 ? songIndex : 0)
                    break
                }
            }
        }
    }

    const handlePlayList = (list: Song[]) => {
        music.player.setQueue(list, 0)
    }

    let artistElement 

    if (list instanceof Album) {
        artistElement = list.artists.map((artist, index) => (
            <React.Fragment>
                <Typography variant="h6" fontWeight={200}>
                    { artist.name }
                </Typography>
                { index < list.artists.length - 1 && <Typography variant="h6" fontWeight={200} sx={{ letterSpacing: "-6px" }}>, &nbsp; </Typography> }
            </React.Fragment>
        ))
    } else if (list instanceof Playlist) {
        artistElement = <Typography variant="h6" fontWeight={200}> { list.author.name } </Typography>
    }
    
    const explicit = true

    return (
        <Box display="flex" sx={{ 
            maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, 
            height: "calc(100% - 64px)", 
            flexGrow: 1, 
            flexDirection: "column", 
            padding: "24px", 
            overflow: "hidden",
            position: "relative"
        }}>
            {/* Blurred background */}
            {list && (
                <Box sx={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    right: 0,
                    height: "50%",
                    backgroundImage: `url(${list.thumbnailURL})`,
                    backgroundSize: "cover",
                    backgroundPosition: "center",
                    filter: "blur(2px)",
                    opacity: 0.65,
                    zIndex: 0,
                    '&::after': {
                        content: '""',
                        position: "absolute",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: "100%",
                        background: "linear-gradient(to bottom, transparent 0%, var(--mui-palette-background-default) 100%)",
                    }
                }}/>
            )}

            <Box display="flex" sx={{ padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", flexShrink: 0, position: "relative", zIndex: 1 }}
                onMouseEnter={() => setHoverOverHeader(true)}
                onMouseLeave={() => setHoverOverHeader(false)}>
                <Box sx={{ position: "relative" }}>
                    {!list ?
                        <Skeleton variant="rounded" sx={{ height: "200px", width: "200px"}}/>
                    : <Avatar variant="rounded" src={list.thumbnailURL} sx={{ height: "200px", width: "200px"}}/>}
                
                    <Box sx={{ position: "absolute", left: "4px", bottom: "4px" }}>
                        {hoverOverHeader && 
                            <Fab color="success" onClick={() => {handlePlayList(list.songs); console.log(list.songs)}}>
                                <PlayArrow />    
                            </Fab>
                        }
                    </Box>
                </Box>
                
                <Box display="flex" sx={{ width: "100%", flexDirection: "row", paddingLeft: "18px", marginTop: "auto", position: "relative" }}>
                    <Box>
                        <Box display="flex" flexDirection="row">
                            <Typography variant="h4" fontWeight={900} sx={{ textWrap: "nowrap" }}>
                                {!list ?
                                <Skeleton />
                                : list.title }
                            </Typography>
                            
                            {!list ?
                                <Skeleton />
                            : ((list instanceof Album) && explicit) &&
                                <ExplicitIcon sx={{ marginTop: "auto", marginBottom: "auto", paddingLeft: "12px" }} color="disabled"/>
                            }
                            
                        </Box>
                        
                        <Box display="flex" sx={{ flexDirection: "row", paddingLeft: "12px" }}>
                            <Box display="flex" sx={{ gap: "8px"}}>
                                {artistImages && artistImages.map((url) => (
                                    <Avatar variant="rounded" src={url} 
                                    sx={{ margin: "auto 0 auto 0", height: "24px", width: "24px"}}/>
                                ))}
                            </Box>

                            <Box display="flex" sx={{ marginLeft: "12px" }}>
                                { artistElement }
                            </Box>

                            {!list ?
                                <Skeleton />
                            : (list instanceof Album) && (
                                <React.Fragment>
                                    <DotRowSeparator />
                                    <Typography variant="h6" fontWeight={200} color="textSecondary"> { list.releaseDate.getFullYear() } </Typography>
                                </React.Fragment>
                            )}

                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { !list ?
                                    <Skeleton />
                                : (list.songs.length > 1) ? `${list.songs.length} songs` : `${list.songs.length} song`}
                            </Typography>
                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { !list ? <Skeleton /> : list.durationFormatted }
                            </Typography>               
                        </Box>
                    </Box>
                    
                    <Box display="flex" sx={{  marginLeft: "auto", marginTop: "auto" }}>
                        <Box display="flex">
                            {!list ?
                                <Skeleton />
                            : (list instanceof Album) && (
                                <Typography variant="caption" color="textSecondary" sx={{ textAlign: "right" }}> { list.label } </Typography>
                            )}
                        </Box>
                    </Box>
                </Box>
            </Box>
            <Box display="flex" sx={{ flexDirection:"column", marginTop: "16px", padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", flexGrow: 1, minHeight: 0, overflow: "hidden", position: "relative", zIndex: 1 }}>
                <Box display="grid" sx={{ gridTemplateColumns: "0.075fr 2fr 1fr 0.1fr", paddingLeft: "16px", paddingRight: "16px", flexShrink: 0 }}>
                    <Typography color="textSecondary">#</Typography>
                    <Typography color="textSecondary">Title</Typography>
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Duration</Typography>
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Source</Typography>
                </Box>
                
                <List sx={{ flexGrow: 1, overflowY: "auto", minHeight: 0 }}>
                    {!list ?

                        (Array.from({ length: 10 }, (_, index) => (
                            <ListItem
                                key={index}
                                sx={{
                                    paddingTop: "0",
                                    paddingRight: "0px",
                                    paddingLeft: "0px",
                                    paddingBottom: "0px",
                                    marginBottom: "8px",
                            }}
                            >

                            </ListItem>
                        )))
                    : list.songs.map((song, index) => (
                        <ListItem
                            key={index}
                            sx={{
                                paddingTop: "0",
                                paddingRight: "0px",
                                paddingLeft: "0px",
                                paddingBottom: "0px",
                                marginBottom: "8px",
                        }}
                        >
                            <ListItemButton
                                onMouseOver={() => { setOverIndex(index + 1) }}
                                onMouseLeave={() => { setOverIndex(0) }}
                                onDoubleClick={() => handlePlay(song)}
                                sx={[{
                                    display: "grid",
                                    gridTemplateColumns: "0.075fr 2fr 1fr 0.1fr",
                                    alignItems: "center",
                                    borderRadius: "12px",
                                    zIndex: "5",
                                }, (music.player.getCurrentSong() && music.player.getCurrentSong().title == song.title) &&  {
                                    backgroundColor: "rgba(255, 255, 255, 0.075)",
                                    color: "#90ee90"
                                }, !(list instanceof Album) && {
                                    gridTemplateColumns: "0.075fr 3em 2fr 1fr 0.1fr",
                                }]}
                            >
                                {(overIndex == (index + 1)) ?
                                    <IconButton onClick={() => handlePlay(song)} size="small" sx={{ left: "-12px" }}>
                                        <PlayArrow />
                                    </IconButton>
                                : <Typography variant="body2" sx={{ textAlign: "left" }} color="textSecondary">{index + 1}</Typography>
                                }

                                {!(list instanceof Album) && (
                                        <Avatar variant="rounded" src={song.thumbnailURL}/>
                                )}

                                <Box>
                                    <Box display="flex" flexDirection="row">
                                        <Typography variant="body1">{song.title}</Typography>
                                        {song.explicit && <ExplicitIcon color="disabled" sx={{ paddingLeft: "8px" }} />}
                                    </Box>
                                    {song.artists.map((artist, index) => (
                                        <React.Fragment>
                                            <Link onClick={() => {
                                                app.screen.setShownThing({id: artist.id, type: "Artist"})
                                                app.screen.setCurrentView("artistView")
                                            }} variant="body2" underline="hover" color="textSecondary" position="sticky" zIndex="10">{artist.name}</Link>
                                            {index < song.artists.length - 1 && <Typography variant="caption" color="textSecondary">,&nbsp;</Typography>}
                                        </React.Fragment>
                                    ))}
                                </Box>
                                <Box>
                                    <Typography variant="body2" sx={{ textAlign: "center" }}>{song.durationFormatted}</Typography>
                                </Box>
                                <Box>
                                    <Typography variant="body2" sx={{ textAlign: "right" }}>{ getServiceIcon(song.source) }</Typography>
                                </Box>
                            </ListItemButton>
                        </ListItem>
                    ))}
                </List>
            </Box>      
        </Box>
    )
}