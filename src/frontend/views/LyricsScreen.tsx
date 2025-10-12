import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { Artist, Song } from "../types/SongTypes"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import List from "@mui/material/List"
import IconButton from "@mui/material/IconButton"
import Fab from "@mui/material/Fab"
import { useSettings } from "../hooks/useSettings"
import Skeleton from "@mui/material/Skeleton"
import Divider from "@mui/material/Divider"
import Stack from "@mui/material/Stack"
import Button from "@mui/material/Button"
import { SpotifyLyrics } from "../../backend/utils/types"

export const LyricsScreen: React.FC = () => {
    const { app, music } = useAppContext()
    const [ overIndex, setOverIndex ] = useState<number>(0)
    const [song, setSong] = useState<Song | undefined>(undefined)
    const [lyrics, setLyrics] = useState<SpotifyLyrics | null>(null)
    const [synced, setSynced] = useState(true)
    const [currentLineIndex, setCurrentLineIndex] = useState<number>(-1)
    const lineRefs = React.useRef<(HTMLDivElement | null)[]>([])
    const containerRef = React.useRef<HTMLDivElement | null>(null)
    
    useEffect(() => {
        setSong(music.player.getCurrentSong())
    }, [music.player.getCurrentSong])

    useEffect(() => {
        if (song?.source_id) {
            Promise.all([
                window.electronAPI.extractors.getLyrics("Spotify", song.source_id)
            ]).then(([lyrics]) => {
                console.log(lyrics)
                setLyrics(lyrics)
                // Reset refs array when lyrics change
                lineRefs.current = []
            }).catch((error) => {
                console.error("Failed to fetch lyrics:", error)
            })
        }
    }, [song])

    // Update current line based on playback time
    useEffect(() => {
        if (!lyrics || !synced) return

        const currentTime = music.player.currentTime * 1000 // Convert to milliseconds
        
        // Find the current line index based on startTimeMs
        const lineIndex = lyrics.lyrics.lines.findIndex((line, index) => {
            const nextLine = lyrics.lyrics.lines[index + 1]
            return currentTime >= parseInt(line.startTimeMs) && 
                   (!nextLine || currentTime < parseInt(nextLine.startTimeMs))
        })

        if (lineIndex !== -1 && lineIndex !== currentLineIndex) {
            setCurrentLineIndex(lineIndex)
        }
    }, [lyrics, synced, music.player.currentTime, currentLineIndex])

    // Scroll to current line
    useEffect(() => {
        if (lineRefs.current[currentLineIndex] && synced) {
            lineRefs.current[currentLineIndex]?.scrollIntoView({
                behavior: 'smooth',
                block: 'center',
            })
        }
    }, [currentLineIndex, synced])

    const artistsString = song?.artists.map(artist => artist.name).join(", ") || ""

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, height: "calc(100% - 64px)", flexGrow: 1, flexDirection: "column", padding: "24px", overflow: "hidden" }}>
            <Box>
                <Stack direction="row">
                    <Typography variant="h6">
                        {!song ?
                            <Skeleton />
                        : `Lyrics for: ${song.title} - ${artistsString}`}
                    </Typography>

                    <Stack direction="row" spacing={2} sx={{ marginLeft: "auto" }}>
                        <Button size="small" variant="contained">Synced</Button>
                        <Button size="small" variant="contained">Unsynced</Button>
                    </Stack>
                </Stack>
            </Box>

            <Divider variant="fullWidth" sx={{ margin: "12px 0"}}/>
        
            <Box ref={containerRef} display="flex" flexDirection="column" sx={{ textAlign: "center", gap: "24px", overflowY: "auto" }}>
                {!lyrics ?
                    <Skeleton />    
                :   lyrics.lyrics.lines.map((line, index) => {
                        const distance = Math.abs(index - currentLineIndex)
                        
                        // When no line is active (currentLineIndex === -1), all lines should be dimmed/blurred
                        const isActive = index === currentLineIndex
                        const hasActiveeLine = currentLineIndex !== -1
                        
                        const blurAmount = synced 
                            ? (hasActiveeLine ? Math.min(distance * 0.5, 3) : 1.5)
                            : 0
                        
                        const opacity = synced 
                            ? (hasActiveeLine 
                                ? (isActive ? 1 : Math.max(0.3, 1 - distance * 0.15))
                                : 0.4)
                            : 1
                        
                        const handleLineClick = () => {
                            // Seek to the line's timestamp (convert from milliseconds to seconds)
                            const timeInSeconds = parseInt(line.startTimeMs) / 1000
                            music.player.seek(timeInSeconds)
                            // If paused, start playing
                            if (!music.player.isPlaying) {
                                music.player.play()
                            }
                        }
                        
                        return (
                            <Box
                                key={index}
                                ref={(el: HTMLDivElement | null) => { 
                                    if (el) {
                                        lineRefs.current[index] = el 
                                    }
                                }}
                                onClick={handleLineClick}
                                sx={{
                                    cursor: 'pointer',
                                    '&:hover': {
                                        transform: 'scale(1.02)',
                                        transition: 'transform 0.2s ease',
                                    }
                                }}
                            >
                                <Typography 
                                    variant="h4"
                                    sx={{
                                        opacity: opacity,
                                        filter: `blur(${blurAmount}px)`,
                                        transition: 'opacity 0.3s ease, filter 0.3s ease',
                                        fontWeight: index === currentLineIndex ? 'bold' : 'normal',
                                    }}
                                >
                                    {line.words}
                                </Typography>
                            </Box>
                        )
                    })}
            </Box>
        </Box>
    )
}