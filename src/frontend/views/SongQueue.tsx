import Box from "@mui/material/Box"
import Divider from "@mui/material/Divider"
import Typography from "@mui/material/Typography"
import { useAppContext } from "../providers/AppContext"
import { Song } from "../types/SongTypes"
import Avatar from "@mui/material/Avatar"
import Link from "@mui/material/Link"
import React, { useState } from "react"
import ButtonBase from "@mui/material/ButtonBase"
import PlayArrow from "@mui/icons-material/PlayArrow"
import List from "@mui/material/List"
import ListItemButton from "@mui/material/ListItemButton"

export const SongQueue: React.FC = () => {
    const { music } = useAppContext();
    const [buttonShowingIndex, setButtonShowingIndex] = useState<number | null>(null)

    const isButtonShowing = (index: number) => buttonShowingIndex === index

    const handlePlay = (index: number) => {
        music.player.goToIndex(index)
    }

    const currentSong = music.player.getCurrentSong()
    const currentIndex = music.player.currentIndex
    
    // Calculate next up based on shuffle state
    const nextUp: Song[] = []
    const nextUpIndices: number[] = []
    
    if (music.player.shuffleEnabled && music.player.shuffleOrder.length > 0) {
        // Use shuffle order
        const currentShuffleIndex = music.player.shuffleIndex
        for (let i = 1; i < music.player.shuffleOrder.length; i++) {
            const shuffleIdx = (currentShuffleIndex + i) % music.player.shuffleOrder.length
            const actualIdx = music.player.shuffleOrder[shuffleIdx]
            nextUp.push(music.player.queue[actualIdx])
            nextUpIndices.push(actualIdx)
        }
    } else {
        // Normal order: only songs after current (don't loop back to show current song again)
        for (let i = currentIndex + 1; i < music.player.queue.length; i++) {
            nextUp.push(music.player.queue[i])
            nextUpIndices.push(i)
        }
        
        // If looping is enabled, add songs from the beginning (but skip the current song)
        if (music.player.loopMode !== 0) { // 0 = LoopingEnum.Off
            for (let i = 0; i < currentIndex; i++) {
                nextUp.push(music.player.queue[i])
                nextUpIndices.push(i)
            }
        }
    }

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, maxHeight: "inherit", flexGrow: 1, flexDirection: "column", padding: "24px", height: "100%", overflow: "hidden" }}>
            <Typography variant="h6" sx={{ flexShrink: 0 }}>Your Queue</Typography>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0", flexShrink: 0 }} />

            <Box sx={{ flexShrink: 0 }}>
                <Typography variant="body1" sx={{ marginBottom: "12px" }}>Now Playing</Typography>

                {currentSong != null ?
                    <QueueItem 
                        song={currentSong}
                        index={currentIndex}
                        handlePlay={handlePlay}
                        isButtonShowing={isButtonShowing}
                        setButtonShowing={setButtonShowingIndex}
                    />
                : <Typography variant="body1">There is no song playing.</Typography>}
            </Box>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0", flexShrink: 0 }} />

            <Box sx={{ flexGrow: 1, minHeight: 0, overflow: "hidden", display: "flex", flexDirection: "column" }}>
                <Typography variant="body1" sx={{ marginBottom: "12px", flexShrink: 0 }}>Next Up</Typography>
                {nextUp.length !== 0 ?
                <List sx={{ padding: "0px 0px 12px 0px", overflowY: "auto", flexGrow: 1, minHeight: 0 }}>
                    {nextUp.map((song, nextUpIndex) => {
                        const actualIndex = nextUpIndices[nextUpIndex]
                        
                        return (
                            <ListItemButton 
                                key={actualIndex}
                                sx={{ padding: "0", marginBottom: "12px", borderRadius: "8px" }}
                            >
                                <QueueItem 
                                    song={song}
                                    index={actualIndex}
                                    handlePlay={handlePlay}
                                    isButtonShowing={isButtonShowing}
                                    setButtonShowing={setButtonShowingIndex}
                                />
                            </ListItemButton>
                        )
                    })}
                </List>
                : <Typography variant="body1">There are no songs in the queue.</Typography>}
            </Box>
        </Box>
    )
}

const QueueItem: React.FC<{
    song: Song,
    index: number,
    handlePlay: (index: number) => void,
    isButtonShowing: (index: number) => boolean,
    setButtonShowing: (index: number | null) => void
}> = ({ song, index, handlePlay, isButtonShowing, setButtonShowing }) => {
    return (
        <Box display="flex" flexDirection="row" sx={{
            backgroundColor: "rgba(0,0,0,0.35)", 
            padding: "12px", 
            borderRadius: "8px" ,
            flexGrow: 1,
        }}
        onMouseEnter={() => setButtonShowing(index)}
        onMouseLeave={() => setButtonShowing(null)}>
            <Box sx={{ position: "relative", aspectRatio: "1/1", height: "64px", width: "auto" }}>
                <Avatar src={song.thumbnailURL} variant="rounded" sx={{ width: "100%", height: "100%" }}/>
                {isButtonShowing(index) &&
                    <ButtonBase sx={{ width: "100%", height: "100%", position: "absolute", top: "0px", left: "0px", borderRadius: "4px",
                    backgroundColor: "rgba(0, 0, 0, 0.6)"}} 
                    onClick={(event) => { 
                        handlePlay(index); event.stopPropagation() 
                    }}>
                        <PlayArrow />
                    </ButtonBase>
                }
            </Box>
            
            
            <Box display="flex" flexDirection="column" sx={{ marginLeft: "12px", marginTop: "auto" }}>
                <Link underline="hover" color="textPrimary" variant="body1">{song.title}</Link>
                <Box>
                    {song.artists.map((artist, artistIndex) => (
                        <React.Fragment key={artistIndex}>
                            <Link underline="hover" variant="body2" color="textSecondary">{ artist.name }</Link>
                            {artistIndex < song.artists.length - 1 && <Typography variant="caption" color="textSecondary" component="span">,&nbsp;</Typography>}
                        </React.Fragment>
                    ))}
                </Box>
            </Box>
        </Box>
    )
}