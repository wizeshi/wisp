import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { Artist, Song } from "../types/SongTypes"
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
import { getServiceIcon, spotifyArtistToArtist } from "../utils/Helpers"
import Fab from "@mui/material/Fab"
import { useSettings } from "../hooks/useSettings"
import Skeleton from "@mui/material/Skeleton"
import Divider from "@mui/material/Divider"

export const ArtistScreen: React.FC = () => {
    const { app, music } = useAppContext()
    const [ overIndex, setOverIndex ] = useState<number>(0)
    const [artist, setArtist] = useState<Artist | undefined>(undefined)
    const [albumIndex, setAlbumIndex] = useState(0)
    const { settings, loading, updateSettings }= useSettings()

    useEffect(() => {
        const fetchLists = async () => {
            setArtist(
                spotifyArtistToArtist(
                    await window.electronAPI.extractors.spotify.getArtistDetails(app.screen.shownThing.id)
                )
            )
        }

        fetchLists()
    }, [app.screen.shownThing])

    const handlePlay = (song: Song) => {
        /* switch(settings.listPlay) {
            case "Single": {
                // Add only this song to queue and play it
                music.player.setQueue([song])
                music.player.setSongIndex(0)
                break
            }
            case "Multiple": {
                // Add all songs from the list to queue
                music.player.setQueue(list.songs)
                // Find and play the selected song (comparing by title and artists)
                const songIndex = list.songs.findIndex(s => 
                    s.title === song.title && 
                    s.artists.length === song.artists.length &&
                    s.artists.every((artist, i) => artist.name === song.artists[i].name)
                )
                music.player.setSongIndex(songIndex !== -1 ? songIndex : 0)
                break
            }
        } */
    }

    const handlePlayArtist = (list: Song[]) => {
        music.player.setQueue(list)
    }

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, height: "100%", flexGrow: 1, flexDirection: "column", padding: "24px", overflow: "hidden" }}>
            <Box display="flex" sx={{ padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", flexShrink: 0 }}>
                <Box sx={{ position: "relative" }}>
                    {!artist ?
                        <Skeleton variant="rounded" sx={{ height: "200px", width: "200px"}}/>
                    : <Avatar variant="rounded" src={artist.thumbnailURL} sx={{ height: "200px", width: "200px"}}/>}
                
                    <Box sx={{ position: "absolute", left: "4px", bottom: "4px" }}>
                        <Fab color="success" onClick={() => handlePlayArtist(artist.topSongs)}>
                            <PlayArrow />    
                        </Fab>
                    </Box>
                </Box>
                
                <Box display="flex" sx={{ width: "100%", flexDirection: "row", paddingLeft: "18px", marginTop: "auto", position: "relative" }}>
                    <Box>
                        <Box display="flex" flexDirection="row">
                            <Typography variant="h4" fontWeight={900} sx={{ textWrap: "nowrap" }}>
                                {!artist ?
                                <Skeleton />
                                : artist.name }
                            </Typography>                   
                        </Box>
                        
                        <Box display="flex" sx={{ flexDirection: "row", paddingLeft: "12px" }}>
                            <Typography variant="h6" fontWeight={300} sx={{ paddingLeft: "12px" }}>
                                {!artist ? 
                                    <Skeleton /> 
                                :   `${Intl.NumberFormat().format(artist.monthlyListeners)} followers`}
                            </Typography>           
                        </Box>
                    </Box>
                </Box>
            </Box>
            <Box display="flex" sx={{ backgroundColor: "rgba(0, 0, 0, 0.35)", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", marginTop: "16px", padding: "16px", flexGrow: 1, flexDirection: "column", overflowY: "scroll" }}>
                <Box display="flex" sx={{ flexDirection:"column", padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", minHeight: 0, overflow: "hidden" }}>
                    <Typography variant="h6">Top Songs</Typography>
                    
                    <Divider variant="fullWidth" sx={{ margin: "8px 0 12px 0" }}/>

                    <Box display="grid" sx={{ gridTemplateColumns: "0.075fr 3em 2fr 1fr 0.1fr", paddingLeft: "16px", paddingRight: "16px", flexShrink: 0 }}>
                        <Typography color="textSecondary">#</Typography>
                        <Box /> {/* Empty space for thumbnail column */}
                        <Typography color="textSecondary">Title</Typography>
                        <Typography sx={{ textAlign: "center" }} color="textSecondary">Duration</Typography>
                        <Typography sx={{ textAlign: "center" }} color="textSecondary">Source</Typography>
                    </Box>
                    
                    <List sx={{ overflowY: "auto", minHeight: 0 }}>
                        {!artist ?

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
                        : artist.topSongs.slice(0, 5).map((song, index) => (
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
                                        gridTemplateColumns: "0.075fr 3em 2fr 1fr 0.1fr",
                                        alignItems: "center",
                                        borderRadius: "12px",
                                        zIndex: "5",
                                    }, (music.player.getCurrentSong() && music.player.getCurrentSong().title == song.title) &&  {
                                        backgroundColor: "rgba(255, 255, 255, 0.075)",
                                        color: "#90ee90"
                                    }]}
                                >
                                    {(overIndex == (index + 1)) ?
                                        <IconButton onClick={() => handlePlay(song)} size="small" sx={{ left: "-12px" }}>
                                            <PlayArrow />
                                        </IconButton>
                                    : <Typography variant="body2" sx={{ textAlign: "left" }} color="textSecondary">{index + 1}</Typography>
                                    }

                                    {!artist ?
                                        <Skeleton />
                                    :   <Avatar variant="rounded" src={song.thumbnailURL}/>
                                    }

                                    <Box>
                                        <Box display="flex" flexDirection="row">
                                            <Typography variant="body1">{song.title}</Typography>
                                            {song.explicit && <ExplicitIcon color="disabled" sx={{ paddingLeft: "8px" }} />}
                                        </Box>
                                        {song.artists.map((artist, index) => (
                                            <React.Fragment>
                                                <Link href="" variant="body2" underline="hover" color="textSecondary" position="sticky" zIndex="10">{artist.name}</Link>
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

                <Divider variant="fullWidth" sx={{ opacity: "0", margin: "12px 0" }}/>

                <Box display="flex" sx={{ flexDirection:"column", padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", minHeight: 0, overflowY: "hidden", height: "90%" }}>
                    <Typography variant="h6">Albums</Typography>

                    <Divider variant="fullWidth" sx={{ margin: "8px 0 12px 0" }}/>
                    
                    <Box 
                        sx={{ 
                            display: "flex",
                            flexDirection: "row",
                            flexWrap: "wrap",
                            gap: "12px",
                            minHeight: 0,
                            overflowY: "scroll",
                            justifyContent: "center"
                        }}
                    >
                        {!artist ?
                            (Array.from({ length: 7 }, (_, index) => (
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
                        : artist.albums.map((album, index) => {
                            return (
                                <Box 
                                    key={index}
                                    sx={{ 
                                        display: "flex",
                                        flexDirection: "column",
                                        flex: "1 1 160px",
                                        minWidth: "160px",
                                        maxWidth: "200px",
                                        padding: "12px", 
                                        border: "1px solid rgba(255, 255, 255, 0.15)", 
                                        borderRadius: "12px", 
                                        backgroundColor: "rgba(0, 0, 0, 0.25)",
                                        cursor: "pointer",
                                        transition: "background-color 0.2s",
                                        "&:hover": {
                                            backgroundColor: "rgba(255, 255, 255, 0.075)"
                                        }
                                    }}
                                    onClick={() => {
                                        app.screen.setShownThing({ id: album.id, type: "Album" })
                                        app.screen.setCurrentView("listView")
                                    }}
                                    onMouseEnter={() => setAlbumIndex(index + 1)}
                                    onMouseLeave={() => setAlbumIndex(0)}
                                >
                                    <Box sx={{ width: "100%", height: "auto", aspectRatio: "1 / 1", marginBottom: "8px", position: "relative" }}>
                                        <Avatar 
                                            src={album.thumbnailURL} 
                                            variant="rounded" 
                                            sx={{ 
                                                width: "100%",
                                                height: "100%"
                                            }}
                                        />
                                        {(albumIndex == (index + 1)) &&
                                            <Fab color="success" sx={{ position: "absolute", bottom: "4px", right: "4px" }} 
                                            onClick={() => {
                                                
                                            }}>
                                                <PlayArrow />
                                            </Fab>
                                        }
                                    </Box>

                                    <Typography 
                                        variant="body1" 
                                        sx={{ 
                                            fontWeight: 600,
                                            overflow: "hidden",
                                            textOverflow: "ellipsis",
                                            whiteSpace: "nowrap"
                                        }}
                                    >
                                        {album.title}
                                    </Typography>
                                    
                                    <Box display="flex" flexDirection="row" sx={{ flexWrap: "wrap" }}>
                                        {album.artists.map((artist, artistIndex) => (
                                            <React.Fragment key={artistIndex}>
                                                <Typography 
                                                    variant="body2" 
                                                    color="textSecondary"
                                                    sx={{
                                                        overflow: "hidden",
                                                        textOverflow: "ellipsis",
                                                        whiteSpace: "nowrap"
                                                    }}
                                                >
                                                    {artist.name}
                                                </Typography>
                                                {artistIndex < album.artists.length - 1 && (
                                                    <Typography variant="body2" color="textSecondary">
                                                        ,&nbsp;
                                                    </Typography>
                                                )}
                                            </React.Fragment>
                                        ))}
                                    </Box>
                                </Box>
                            )
                        })}
                    </Box>
                </Box>
            </Box>      
        </Box>
    )
}

const ButtonWrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    return (
        <div role="button" style={{
            padding: "12px",
            backgroundColor: "rgba(0, 0, 0, 0.35)",
            marginRight: "8px",
            textWrap: "nowrap",
            textAlign: "left",
            display: "flex",
            flexDirection: "row",
            cursor: "pointer",
            border: "1px solid rgba(255, 255, 255, 0.175)",
            borderRadius: "12px",
            maxHeight: "128px",
            width: "auto",
            aspectRatio: "2.5 / 1",
        }}>
            { children }
        </div>
    )
}