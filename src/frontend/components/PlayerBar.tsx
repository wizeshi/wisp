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
import { Artist, LoopingEnum } from "../types/SongTypes"
import Button from "@mui/material/Button"
import KeyboardArrowUpIcon from '@mui/icons-material/KeyboardArrowUp';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import Slide from "@mui/material/Slide"
import LinearProgress from "@mui/material/LinearProgress"

const ProgressControl: React.FC = () => {
    const { music } = useAppContext()
    const player = music.audioPlayerElement

    const handleProgressChange = (event: Event, newValue: number) => {
        player.seek(newValue)
    }

    const currentSong = music.player.getCurrentSong()
    const songDurationSeconds = currentSong?.durationSecs || 0
    const songDurationFormatted = currentSong?.durationFormatted || "00:00"

    if (music.player.songLoading) {
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
            variant="body2">{ secondsToSecAndMin(music.audioPlayerElement.currentTime) }</Typography>

            <Slider
                size="medium"
                min={0}
                max={songDurationSeconds}
                step={1}
                value={music.audioPlayerElement.currentTime}
                onChange={handleProgressChange}
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
    const { app, music } = useAppContext()
    const player = music.audioPlayerElement

    useEffect(() => {
        player.setVolume(volume)
    }, [volume])

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
        const index = music.player.songIndex + 1
        if (music.player.queue[index]) {
            music.player.setSongIndex(index)
        }
    }

    const handleSkipBack = () => {
        const index = music.player.songIndex - 1
        if (music.player.queue[index]) {
            music.player.setSongIndex(index)
        }
    }

    const handlePlay = () => {
        player.isPlaying ? player.pause() : player.play()
    }

    const handleShuffle = () => {
        music.player.shuffle.toggle()
    }

    const handleRepeat = () => {
        if (music.player.loop.type < 2) {
            music.player.loop.setType(music.player.loop.type + 1)
        } else {
            music.player.loop.setType(0)
        }
    }

    let repeatButton
    switch (music.player.loop.type) {
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

    let volumeIcon
    if (volume == 0) {
        volumeIcon = <VolumeOffIcon />
    } else if (volume < 50) {
        volumeIcon = <VolumeDownIcon />
    } else if (volume >= 50) {
        volumeIcon = <VolumeUpIcon />
    }

    let songName = ""
    let artists: Array<Artist> = []
    let songThumbnailUrl = ""
    const currentSong = music.player.getCurrentSong()
    if (music.player.getCurrentSong() != undefined) {
        songName = currentSong.title
        artists = currentSong.artists
        songThumbnailUrl = currentSong.thumbnailURL
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
                                        {music.player.shuffle.shuffled ?
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
                            <IconButton sx={{ paddingRight: "4px" }}>
                                <MusicNoteIcon />
                            </IconButton>
                            
                            <IconButton sx={{ paddingRight: "4px" }} onClick={() => { app.screen.setCurrentView("songQueue") }}>
                                <QueueMusicIcon />
                            </IconButton>
                            
                            <IconButton onClick={handleVolumeButton} sx={{ marginRight: "6px" }}>
                                {volumeIcon}
                            </IconButton>
        
                            <Slider size="small" min={0} max={100} value={volume} onChange={handleVolumeChange}
                            sx={{ width: "100px", padding: "18px 0", marginRight: "12px" }}/>
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