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
import { secondsToSecAndMin } from "../utils/utils"

enum ShuffleEnum {
    Off = 0,
    List = 1,
    Song = 2
}

export const PlayerBar: React.FC = () => {
    const [repeat, setRepeat] = useState<ShuffleEnum>(ShuffleEnum.Off)
    const [shuffle, setShuffle] = useState<boolean>(false)
    const [volume, setVolume] = useState<number>(0)
    const [oldVolume, setOldVolume] = useState<number>(0)
    const { music } = useAppContext()

    useEffect(() => {
        if (volume > 100) {
            setVolume(100)
        }
        if (volume < 0) {
            setVolume(0)
        }
    }, [volume])

    const handleSkipForward = () => {

    }

    const handleSkipBack = () => {

    }

    const handlePlay = () => {
        music.setPlaying(!music.playing)
    }

    const handleShuffle = () => {
        setShuffle(!shuffle)
    }

    const handleRepeat = () => {
        if (repeat < 2) {
            setRepeat(repeat + 1)
        } else {
            setRepeat(0)
        }
    }

    let repeatButton
    switch (repeat) {
        default:
        case 0:
            repeatButton = (
                <RepeatIcon />
            )
            break
        case 1:
            repeatButton = (
                <RepeatOnIcon />
            )
            break
        case 2:
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

    const handleProgressChange = (event: Event, newValue: number) => {
        music.current.setSecond(newValue)
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
    let artistName = ""
    let songDurationSeconds
    let songDurationFormatted
    if (music.current.song != undefined) {
        songName = music.current.song.title
        artistName = music.current.song.artist.name
        songDurationSeconds = music.current.song.durationSecs
        songDurationFormatted = music.current.song.durationFormatted
    }
    
    return (
        <Box display="flex" sx={{ height: "92px", width: "calc(100% - 24px)", marginLeft: "12px", marginBottom: "12px", border: "1px solid rgba(255, 255, 255, 0.175)", backgroundColor: "rgba(0, 0, 0, 0.5)",
                                position: "absolute", zIndex: "calc(var(--mui-zIndex-drawer) + 1)", bottom: "0", backdropFilter: "blur(6px)" }}>
            
            <Box sx={{ padding: "12px", display: "flex", width: "inherit" }}>
                <Box display="flex" sx={{ zIndex: "calc(var(--mui-zIndex-drawer) + 10)" }}>
                    <ButtonBase sx={{ marginTop: "auto", marginBottom: "auto" }}>
                        <Avatar variant="rounded" src="" sx={{ height: "64px", width: "64px" }}/>

                    </ButtonBase>
        
                    <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "auto", marginBottom: "auto" }}>
                        <Link href="" underline="hover" variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>{songName}</Link>
                        <Link href="" underline="hover" variant="caption" fontWeight="200" sx={{ color: "var(--mui-palette-text-secondary)" }}>{artistName}</Link>
                    </Box>
                </Box>
    
                <Box display="flex" sx={{ width: "inherit", position: "absolute", top: "12px", left: "12px" }}>
                    <Box display="flex" sx={{ alignItems: "center", flexDirection: "column", marginLeft: "auto", marginRight: "auto" }}>
                        <Box sx={{ paddingTop: "4px" }}>
                            <IconButton onClick={handleShuffle}>
                                {shuffle ?
                                    <ShuffleOnIcon />
                                :   <ShuffleIcon />
                                }
                            </IconButton>

                            <IconButton onClick={handleSkipBack}>
                                <SkipPreviousIcon />
                            </IconButton>
                            
                            <IconButton onClick={handlePlay}>
                                {music.playing ?
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

                        <Box display="flex" flexDirection="row">
                            <Typography sx={{ position: "relative", left: "-12px", top: "-8px" }}
                            variant="body2">{ secondsToSecAndMin(music.current.second) }</Typography>

                            <Slider
                            size="medium"
                            min={0}
                            max={songDurationSeconds}
                            step={1}
                            value={music.current.second}
                            onChange={handleProgressChange}
                            slotProps={{
                                thumb: { style: {
                                    width: "12px", height: "12px"
                                }}
                            }}
                            sx={{ width: "30vw", padding: "0" }}/>

                            <Typography sx={{ position: "relative", left: "12px", top: "-8px" }}
                            variant="body2">{ songDurationFormatted ?? "00:00" }</Typography>
                        </Box>

                    </Box>
                </Box>

                <Box display="flex" sx={{ marginLeft: "auto", marginRight: "12px", marginTop:"auto", marginBottom: "auto"}}>
                    <IconButton sx={{ paddingRight: "4px" }}>
                        <MusicNoteIcon />
                    </IconButton>
                    
                    <IconButton sx={{ paddingRight: "4px" }}>
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
        </Box>
    )
}