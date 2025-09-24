import React, { useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { Album, Artist, Playlist, Song } from "../utils/types"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"
import List from "@mui/material/List"
import ListItem from "@mui/material/ListItem"
import ListItemButton from "@mui/material/ListItemButton"
import Link from "@mui/material/Link"
import ExplicitIcon from '@mui/icons-material/Explicit';
import IconButton from "@mui/material/IconButton"
import PlayArrow from "@mui/icons-material/PlayArrow"
import { getServiceIcon } from "../utils/helpers"

export const ListScreen: React.FC<{ currentList: Album | Playlist }> = ({ currentList }) => {
    const { music } = useAppContext()
    const [ overIndex, setOverIndex ] = useState<number>(0)

    const handlePlay = (song: Song) => {
        console.log("playing")
        music.current.setSong(song)
        music.current.setSecond(0)
        music.setPlaying(true)
    }

    let artist = ""

    if (currentList instanceof Album) {
        artist = currentList.artist.name
    }

    if (currentList instanceof Playlist) {
        artist = currentList.author
    }
    
    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, maxHeight: "inherit", flexGrow: 1, flexDirection: "column", padding: "24px" }}>
            <Box display="flex" sx={{ padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)" }}>
                <ButtonBase>
                    <Avatar variant="rounded" src="" sx={{ height: "200px", width: "200px"}}/>
                </ButtonBase>
                
                <Box display="flex" sx={{ width: "100%", flexDirection: "row", paddingLeft: "18px", marginTop: "auto" }}>
                    <Box>
                        <Box display="flex" flexDirection="row">
                            <Typography variant="h4" fontWeight={900} sx={{ textWrap: "nowrap" }}>{ currentList.title }</Typography>
                            
                            {((currentList instanceof Album) && currentList.explicit) &&
                                <ExplicitIcon sx={{ marginTop: "auto", marginBottom: "auto", paddingLeft: "12px" }} color="disabled"/>
                            }
                            
                        </Box>
                        
                        <Box display="flex" sx={{ flexDirection: "row", paddingLeft: "12px" }}>
                            <Avatar variant="rounded" src="" sx={{ margin: "auto 0 auto 0", height: "24px", width: "24px"}}/>

                            <Typography variant="h6" fontWeight={200} sx={{ paddingLeft: "12px" }}>{ artist }</Typography>
                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { (currentList.songs.length > 1) ? `${currentList.songs.length} songs` : `${currentList.songs.length} song` }
                            </Typography>
                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { currentList.durationFormatted }
                            </Typography>               
                        </Box>
                    </Box>
                    
                    <Box display="flex" sx={{  marginLeft: "auto", marginTop: "auto" }}>
                        <Box display="flex">
                            {(currentList instanceof Album) && 
                                <Typography variant="caption" color="textSecondary" sx={{ textAlign: "right" }}> { currentList.label } </Typography>
                            }
                        </Box>
                    </Box>
                </Box>
            </Box>
            <Box display="flex" sx={{overflowY: "scroll", flexDirection:"column", marginTop: "16px", padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)" }}>
                <Box display="grid" sx={{ gridTemplateColumns: "0.075fr 2fr 1fr 0.1fr", paddingLeft: "16px", paddingRight: "16px" }}>
                    <Typography color="textSecondary">#</Typography>
                    <Typography color="textSecondary">Title</Typography>
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Duration</Typography>
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Source</Typography>
                </Box>
                
                <List sx={{ flexGrow: 1 }}>
                    {currentList.songs.map((song, index) => (
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
                                }, (music.current.song && music.current.song.title == song.title) &&  {
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
                                    <Typography variant="body2" sx={{ textAlign: "center" }}>{ getServiceIcon(song.source) }</Typography>
                                </Box>
                            </ListItemButton>
                        </ListItem>
                    ))}
                </List>
            </Box>
            
        </Box>
    )
}

export const DotRowSeparator: React.FC<{ sx?: React.CSSProperties }> = ({ sx }) => {
    return (
        <Typography variant="h6" fontWeight={900} color="var(--mui-palette-text-secondary)"
        sx={{ paddingLeft: "8px", paddingRight: "8px", ...sx }}>•</Typography>
    )
}