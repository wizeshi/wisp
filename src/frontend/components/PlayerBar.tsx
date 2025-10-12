import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"
import Link from "@mui/material/Link"
import Slider from "@mui/material/Slider"
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import PauseIcon from '@mui/icons-material/Pause';
import SkipNextIcon from '@mui/icons-material/SkipNext';
import SkipPreviousIcon from '@mui/icons-material/SkipPrevious';
import ShuffleIcon from '@mui/icons-material/Shuffle';
import ShuffleOnIcon from '@mui/icons-material/ShuffleOn';
import RepeatIcon from '@mui/icons-material/Repeat';
import RepeatOnIcon from '@mui/icons-material/RepeatOn';
import RepeatOneIcon from '@mui/icons-material/RepeatOne';
import IconButton from "@mui/material/IconButton"
import MusicNoteIcon from '@mui/icons-material/MusicNote';
import VolumeOffIcon from '@mui/icons-material/VolumeOff';
import VolumeDownIcon from '@mui/icons-material/VolumeDown';
import VolumeUpIcon from '@mui/icons-material/VolumeUp';
import QueueMusicIcon from '@mui/icons-material/QueueMusic';
import Input from "@mui/material/Input"
import { secondsToSecAndMin } from "../utils/Utils"
import { LoopingEnum, SimpleArtist } from "../types/SongTypes"
import Button from "@mui/material/Button"
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import Slide from "@mui/material/Slide"
import LinearProgress from "@mui/material/LinearProgress"
import { useData } from "../hooks/useData"

const ProgressControl: React.FC = () => {
    const { music } = useAppContext()
    const player = music.player
    const [isDragging, setIsDragging] = useState(false)
    const [tempValue, setTempValue] = useState(0)
    const [wasPlaying, setWasPlaying] = useState(false)

    const handleProgressChange = (event: Event, newValue: number | number[]) => {
        const value = Array.isArray(newValue) ? newValue[0] : newValue
        setTempValue(value)
    }

    const handleProgressCommit = (event: Event | React.SyntheticEvent, newValue: number | number[]) => {
        const value = Array.isArray(newValue) ? newValue[0] : newValue
        player.seek(value)
        setIsDragging(false)
        
        // Seek itself doesn't stop playback, so no need to resume
        // The wasPlaying state is kept for future potential use
    }

    const handleDragStart = () => {
        setWasPlaying(player.isPlaying)
        setIsDragging(true)
        setTempValue(player.currentTime)
        // Don't pause during drag - let it continue playing
    }

    const currentSong = music.player.getCurrentSong()
    const songDurationSeconds = currentSong?.durationSecs || 0
    const songDurationFormatted = currentSong?.durationFormatted || "00:00"
    const displayTime = isDragging ? tempValue : player.currentTime

    if (player.isLoading || music.isDownloading) {
        return (
            <Box display="flex" flexDirection="row" sx={{ marginTop: "8px", alignItems: "center" }}>
                <Typography sx={{ position: "relative", left: "-12px", top: "-8px" }}
                variant="body2">00:00</Typography>

                <LinearProgress
                    variant="indeterminate"
                    sx={{ width: "30vw", padding: "0", marginBottom: "14px" }}/>

                <Typography sx={{ position: "relative", left: "12px", top: "-8px" }}
                variant="body2">{songDurationFormatted}</Typography>
            </Box>
        )
    }

    return (
        <Box display="flex" flexDirection="row" sx={{ marginTop: "8px" }}>
            <Typography sx={{ position: "relative", left: "-12px", top: "-8px" }}
            variant="body2">{ secondsToSecAndMin(displayTime) }</Typography>

            <Slider
                size="medium"
                min={0}
                max={songDurationSeconds}
                step={1}
                value={displayTime}
                onChange={handleProgressChange}
                onChangeCommitted={handleProgressCommit}
                onMouseDown={handleDragStart}
                onTouchStart={handleDragStart}
                slotProps={{
                    thumb: { style: {
                        width: "12px", height: "12px"
                    }}
                }}
                sx={{ width: "30vw", padding: "0" }}/>

            <Typography sx={{ position: "relative", left: "12px", top: "-8px" }}
            variant="body2">{songDurationFormatted}</Typography>
        </Box>
    )
}

export const PlayerBar: React.FC = () => {
    const [playerBarShown, setPlayerBarShown] = useState<boolean>(true)
    const [volume, setVolume] = useState<number>(10)
    const [oldVolume, setOldVolume] = useState<number>(0)
    const [initialized, setInitialized] = useState<boolean>(false)
    const { app, music } = useAppContext()
    const player = music.player
    const { data, loading, updateData } = useData()

    // Load saved settings on mount (only once)
    useEffect(() => {
        if (!loading && !initialized) {
            setVolume(data.preferredVolume)
            
            // Set shuffle state if different from saved
            if (data.shuffled !== player.shuffleEnabled) {
                player.toggleShuffle()
            }
            
            // Set loop mode if different from saved - toggle the appropriate number of times
            const currentLoop = player.loopMode
            const targetLoop = data.looped
            if (currentLoop !== targetLoop) {
                // Calculate how many times to toggle (0->1->2->0)
                const toggleCount = (targetLoop - currentLoop + 3) % 3
                for (let i = 0; i < toggleCount; i++) {
                    player.toggleLoop()
                }
            }
            
            setInitialized(true)
        }
    }, [loading, initialized])

    // Track when the current song changes and save it to lastPlayed
    useEffect(() => {
        if (loading) return
        
        const currentSong = player.getCurrentSong()
        if (currentSong && currentSong !== data.lastPlayed) {
            updateData({ lastPlayed: currentSong })
        }
    }, [player.currentIndex, loading])

    // Update player volume immediately, but don't save yet
    useEffect(() => {
        player.setVolume(volume)
    }, [volume])

    // Debounce saving volume changes
    useEffect(() => {
        if (loading) return

        const timeoutId = setTimeout(() => {
            updateData({ preferredVolume: volume })
        }, 500) // Save 500ms after user stops changing volume

        return () => clearTimeout(timeoutId)
    }, [volume, loading])

    useEffect(() => {
        if (volume > 100) {
            setVolume(100)
        }
        if (volume < 0) {
            setVolume(0)
        }
    }, [volume])

    // Global spacebar handler for play/pause
    useEffect(() => {
        const handleKeyPress = (event: KeyboardEvent) => {
            // Only trigger if spacebar is pressed and not typing in an input/textarea
            if (event.code === 'Space' && 
                event.target instanceof HTMLElement && 
                !['INPUT', 'TEXTAREA'].includes(event.target.tagName)) {
                event.preventDefault() // Prevent page scroll
                player.isPlaying ? player.pause() : player.play()
            }
        }

        window.addEventListener('keydown', handleKeyPress)

        return () => {
            window.removeEventListener('keydown', handleKeyPress)
        }
    }, [player])

    const handleSkipForward = () => {
        player.skipNext()
    }

    const handleSkipBack = () => {
        player.skipPrevious()
    }

    const handlePlay = () => {
        player.isPlaying ? player.pause() : player.play()
    }

    const handleShuffle = () => {
        music.player.toggleShuffle()
        // Save the new shuffle state
        updateData({ shuffled: !player.shuffleEnabled })
    }

    const handleRepeat = () => {
        music.player.toggleLoop()
        // Save the new loop state (after toggle, so we need to calculate next state)
        const nextLoopState = player.loopMode < 2 ? player.loopMode + 1 : 0
        updateData({ looped: nextLoopState as LoopingEnum })
    }

    let repeatButton
    switch (music.player.loopMode) {
        default:
        case LoopingEnum.Off:
            repeatButton = (
                <RepeatIcon />
            )
            break
        case LoopingEnum.List:
            repeatButton = (
                <RepeatOnIcon />
            )
            break
        case LoopingEnum.Song:
            repeatButton = (
                <RepeatOneIcon />
            )
            break
    }

    const handleVolumeChange = (event: Event, newValue: number) => {
        setVolume(newValue)
    }

    const handleVolumeInput = (event: React.ChangeEvent<HTMLInputElement>) => {
        setVolume(event.target.value === '' ? 0 : Number(event.target.value))
    }

    const handleVolumeButton = () => {
        if (volume > 0) {
            setOldVolume(volume)
            setVolume(0)
        } else {
            setVolume(oldVolume)
        }
    }

    const handleVolumeWheel = (event: React.WheelEvent) => {
        event.preventDefault()
        // deltaY is negative when scrolling up, positive when scrolling down
        const delta = event.deltaY > 0 ? -5 : 5
        setVolume(prevVolume => {
            const newVolume = prevVolume + delta
            // Clamp between 0 and 100
            return Math.max(0, Math.min(100, newVolume))
        })
    }

    let volumeIcon
    if (volume == 0) {
        volumeIcon = <VolumeOffIcon />
    } else if (volume < 50) {
        volumeIcon = <VolumeDownIcon />
    } else if (volume >= 50) {
        volumeIcon = <VolumeUpIcon />
    }

    let songName = ""
    let artists: Array<SimpleArtist> = []
    let songThumbnailUrl = ""
    const currentSong = music.player.getCurrentSong()
    if (currentSong != undefined) {
        songName = currentSong.title
        artists = currentSong.artists
        songThumbnailUrl = currentSong.thumbnailURL
    }

    if (loading) {
        return <></>
    }
    
    return (
        <React.Fragment>
            <Slide direction="up" in={playerBarShown} mountOnEnter unmountOnExit>
                <Box display="flex" sx={{ height: "92px", width: "calc(100% - 24px)", marginLeft: "12px", marginBottom: "12px", border: "1px solid rgba(255, 255, 255, 0.175)", backgroundColor: "rgba(0, 0, 0, 0.5)",
                                        position: "absolute", zIndex: "calc(var(--mui-zIndex-drawer) + 1)", bottom: "0", backdropFilter: "blur(6px)" }}>
                    
                    <Box sx={{ padding: "12px", display: "flex", width: "inherit" }}>
                        <Box display="flex" sx={{ zIndex: "calc(var(--mui-zIndex-drawer) + 10)" }}>
                            <ButtonBase sx={{ marginTop: "auto", marginBottom: "auto" }}>
                                <Avatar variant="rounded" src={songThumbnailUrl} sx={{ height: "64px", width: "64px" }}/>
        
                            </ButtonBase>
                
                            <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "auto", marginBottom: "auto" }}>
                                <Link href="" underline="hover" variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>{songName}</Link>
                                
                                <Box>
                                    {artists.map((artist, index) => (
                                        <React.Fragment>
                                            <Link href="" underline="hover" variant="caption" fontWeight="200" sx={{ color: "var(--mui-palette-text-secondary)" }}>{ artist.name }</Link>
                                            {index < artists.length - 1 && <Typography variant="caption" color="textSecondary">,&nbsp;</Typography>}
                                        </React.Fragment>
                                    ))}
                                </Box>
                            </Box>
                        </Box>
            
                        <Box display="flex" sx={{ width: "inherit", position: "absolute", top: "12px", left: "12px" }}>
                            <Box display="flex" sx={{ alignItems: "center", flexDirection: "column", marginLeft: "auto", marginRight: "auto" }}>
                                <Box sx={{ paddingTop: "4px" }}>
                                    <IconButton onClick={handleShuffle}>
                                        {music.player.shuffleEnabled ?
                                            <ShuffleOnIcon />
                                        :   <ShuffleIcon />
                                        }
                                    </IconButton>
        
                                    <IconButton onClick={handleSkipBack}>
                                        <SkipPreviousIcon />
                                    </IconButton>
                                    
                                    <IconButton onClick={handlePlay}>
                                        {player.isPlaying ?
                                            <PauseIcon />
                                        : <PlayArrowIcon />
                                        }
                                    </IconButton>
                                    
                                    <IconButton onClick={handleSkipForward}>
                                        <SkipNextIcon />
                                    </IconButton>
        
                                    <IconButton onClick={handleRepeat}>
                                        {repeatButton}
                                    </IconButton>
                                </Box>
        
                                <ProgressControl />
        
                            </Box>
                        </Box>
        
                        <Box display="flex" sx={{ marginLeft: "auto", marginRight: "12px", marginTop:"auto", marginBottom: "auto"}}>
                            <IconButton sx={{ paddingRight: "4px" }} onClick={() => { app.screen.setCurrentView("lyricsView"); }}>
                                <MusicNoteIcon />
                            </IconButton>
                            
                            <IconButton sx={{ paddingRight: "4px" }} onClick={() => { app.screen.setCurrentView("songQueue") }}>
                                <QueueMusicIcon />
                            </IconButton>
                            
                            <IconButton onClick={handleVolumeButton} sx={{ marginRight: "6px" }}>
                                {volumeIcon}
                            </IconButton>
        
                            <Slider 
                                size="small" 
                                min={0} 
                                max={100} 
                                value={volume} 
                                onChange={handleVolumeChange}
                                onWheel={handleVolumeWheel}
                                sx={{ width: "100px", padding: "18px 0", marginRight: "12px" }}
                            />
                            <Input
                            value={volume}
                            size="small"
                            onChange={handleVolumeInput}
                            inputProps={{
                                step: 10,
                                min: 0,
                                max: 100,
                                type: 'number'
                            }}
                            sx={{ marginTop: "auto", marginBottom: "auto", width: "48px", height: "28px", textAlign: "center" }}
                            />
                        </Box>
        
                    </Box>

                    <Button sx={{
                        position: "absolute", right: "-1px", top: "-36px", backgroundColor: "rgba(0, 0, 0, 0.35)",
                        border: "1px solid rgba(255, 255, 255, 0.175)", borderBottom: "0px"
                    }}
                    color="inherit"
                    onClick={() => setPlayerBarShown(false)}>
                        <KeyboardArrowDownIcon />
                    </Button>
                </Box>
            </Slide>
            
            {!playerBarShown &&
                <Button sx={{
                    position: "fixed", right: "12px", bottom: "0px", backgroundColor: "rgba(0, 0, 0, 0.35)",
                    border: "1px solid rgba(255, 255, 255, 0.175)", borderBottom: "0px",
                    zIndex: "calc(var(--mui-zIndex-drawer) + 2)"
                }}
                color="inherit"
                onClick={() => setPlayerBarShown(true)}>
                    <KeyboardArrowUpIcon />
                </Button>
            }
        </React.Fragment>
    )
}