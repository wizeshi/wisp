import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { GenericSong } from "../../common/types/SongTypes"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Skeleton from "@mui/material/Skeleton"
import Divider from "@mui/material/Divider"
import Stack from "@mui/material/Stack"
import Button from "@mui/material/Button"
import { GenericLyrics } from "../../common/types/LyricsTypes"
import { usePlayer } from "../providers/PlayerContext"
import { usePlayerTime } from "../hooks/usePlayerTime"

export const LyricsScreen: React.FC = () => {
    const player = usePlayer()
    const playerTime = usePlayerTime()
    const [song, setSong] = useState<GenericSong | undefined>(undefined)
    const [lyrics, setLyrics] = useState<GenericLyrics | null>(null)
    const [synced, setSynced] = useState(true)
    const [currentLineIndex, setCurrentLineIndex] = useState<number>(-1)
    const lineRefs = React.useRef<(HTMLDivElement | null)[]>([])
    const containerRef = React.useRef<HTMLDivElement | null>(null)
    
    useEffect(() => {
        setSong(player.getCurrentSong())
    }, [player.getCurrentSong])

    useEffect(() => {
        if (song && song.id) {
            Promise.all([
                window.electronAPI.extractors.getLyrics(song)
            ]).then(([lyrics]) => {
                console.log("Fetched lyrics:", lyrics)
                setLyrics(lyrics)
                setSynced(lyrics.synced)
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

        const currentTime = playerTime * 1000 // Convert to milliseconds
        
        // Find the current line index based on startTimeMs
        const lineIndex = lyrics.lines.findIndex((line, index) => {
            const nextLine = lyrics.lines[index + 1]
            return currentTime >= parseInt(line.startTimeMs) && 
                   (!nextLine || currentTime < parseInt(nextLine.startTimeMs))
        })

        if (lineIndex !== -1 && lineIndex !== currentLineIndex) {
            setCurrentLineIndex(lineIndex)
        }
    }, [lyrics, synced, playerTime, currentLineIndex])

    // Scroll to current line
    useEffect(() => {
        if (lineRefs.current[currentLineIndex] && synced) {
            lineRefs.current[currentLineIndex]?.scrollIntoView({
                behavior: 'smooth',
                block: 'center',
            })
        }
    }, [currentLineIndex, synced])

    const handleClickSynced = () => {
        setSynced(true)
    }

    const handleClickUnsynced = () => {
        setSynced(false)
    }

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
                        {!lyrics ? <Skeleton /> : <>
                            <Button size="small" variant="contained" disabled={!lyrics.synced} onClick={handleClickSynced}>Synced</Button>
                            <Button size="small" variant="contained" onClick={handleClickUnsynced}>Unsynced</Button>
                        </>}
                    </Stack>
                </Stack>
            </Box>

            <Divider variant="fullWidth" sx={{ margin: "12px 0"}}/>
        
            <Box ref={containerRef} display="flex" flexDirection="column" sx={{ position: "relative", textAlign: "center", gap: "24px", overflowY: "auto" }}>
                {/* Fixed provider label at top right */}
                {lyrics && (
                    <Box sx={{ 
                        position: "sticky", 
                        top: 0, 
                        right: 0, 
                        zIndex: 10,
                        display: "flex",
                        justifyContent: "flex-end",
                        pointerEvents: "none",
                        marginBottom: "-32px" // Offset so it doesn't push content down
                    }}>
                        <Typography 
                            variant="caption"
                            color="textSecondary"
                            sx={{ 
                                padding: "4px 24px", 
                                pointerEvents: "auto",
                            }}
                        >
                            Lyrics provided by {lyrics.provider}
                        </Typography>
                    </Box>
                )}
                
                {!lyrics ?
                    <Skeleton />    
                :
                <Box sx={{ position: "relative"}}>
                    <Box sx={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                        {lyrics.lines.map((line, index) => {
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
                                // Only allow clicking if synced
                                if (!synced) return
                                
                                // Seek to the line's timestamp (convert from milliseconds to seconds)
                                const timeInSeconds = parseInt(line.startTimeMs) / 1000
                                player.seek(timeInSeconds)
                                // If paused, start playing
                                if (!player.isPlaying) {
                                    player.play()
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
                                        cursor: synced ? 'pointer' : 'default',
                                        '&:hover': synced ? {
                                            transform: 'scale(1.02)',
                                            transition: 'transform 0.2s ease',
                                        } : {}
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
                                        {line.content}
                                    </Typography>
                                </Box>
                            )
                        })}
                    </Box>
                </Box>
                }
            </Box>
        </Box>
    )
}