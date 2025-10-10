import Typography from "@mui/material/Typography";
import Box from "@mui/material/Box";
import React, { JSX, useEffect, useState } from "react";
import Divider from "@mui/material/Divider";
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import IconButton from "@mui/material/IconButton";
import LoginIcon from '@mui/icons-material/Login';
import CheckIcon from '@mui/icons-material/Check';
import { SvgIconTypeMap } from "@mui/material/SvgIcon";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import YoutubeIcon from '@mui/icons-material/YouTube'
import { LIST_PLAY_TYPES, SHUFFLE_TYPES } from "../../backend/utils/types";
import Select from "@mui/material/Select";
import MenuItem from "@mui/material/MenuItem";
import FormControl from "@mui/material/FormControl";
import { useSettings } from "../hooks/useSettings";
import Tooltip from "@mui/material/Tooltip";

export const Settings: React.FC = () => {
    const [spotifyLoggedIn, setSpotifyLoggedIn] = useState<boolean>(false)
    const [youtubeLoggedIn, setYoutubeLoggedIn] = useState<boolean>(false)
    const { settings, loading, updateSettings } = useSettings()

    const handleSpotifyLogin = () => {
        if (spotifyLoggedIn) return
        window.electronAPI.login.spotify.login()
    }

    const handleYoutubeLogin = () => {
        if (youtubeLoggedIn) return
        window.electronAPI.login.youtube.login()
    }

    useEffect(() => {
        window.electronAPI.login.spotify.onCode((code) => {
            console.log('Spotify code:', code)
            setSpotifyLoggedIn(true)
            window.electronAPI.window.send("SPOTIFY_TOKEN", code)
        })

        window.electronAPI.login.youtube.onCode((code) => {
            console.log('Youtube code', code)
            setYoutubeLoggedIn(true)
            window.electronAPI.window.send("YOUTUBE_TOKEN", code)
        })
    }, [])

    useEffect(() => {
        let cancelled = false;
        Promise.all([
            window.electronAPI.login.spotify.loggedIn(),
            window.electronAPI.login.youtube.loggedIn()
        ]).then(([spotify, youtube]) => {
            if (!cancelled) {
                setSpotifyLoggedIn(spotify.loggedIn && !spotify.expired)
                setYoutubeLoggedIn(youtube.loggedIn && !youtube.expired)
            }
        })

        return () => { cancelled = true; }
    }, [])

    if (loading) { return <Typography>Loading...</Typography>}

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, maxHeight: "inherit", flexGrow: 1, flexDirection: "column", padding: "24px" }}>

            <Typography variant="h6">Settings</Typography>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />

            <Box>
                <Typography variant="h6">Accounts</Typography>

                <Box>
                    <AccountRow serviceName="Spotify" ServiceIcon={GraphicEqIcon} loginState={spotifyLoggedIn} loginHandler={handleSpotifyLogin}/>

                    <AccountRow serviceName="Youtube" ServiceIcon={YoutubeIcon} loginState={youtubeLoggedIn} loginHandler={handleYoutubeLogin}/>
                </Box>
            </Box>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />

            <Box>
                <Typography variant="h6">Lyrics Providers</Typography>

                {["Genius", "MusixMatch", "NetEase", "LrcLib"].map((provider, index) => (
                    <SettingRowBox>
                        <Typography variant="body1">{ provider }</Typography>

                        <Box sx={{ marginLeft: "auto" }}>
                            <Typography variant="body1" color="error">Not Linked</Typography>
                        </Box>
                    </SettingRowBox>
                ))}
            </Box>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />
            
            <Box>
                <Typography variant="h6">Your Preferences</Typography>

                <SettingRowBox>
                    <Typography variant="body1">Shuffle Type</Typography>

                    <Box sx={{ marginLeft: "auto" }}>
                        <FormControl>
                            <Select
                                size="small"
                                value={settings.shuffleType || "Fisher-Yates"}
                                onChange={(e) => updateSettings({ shuffleType: e.target.value as typeof settings.shuffleType })}
                            >
                                {SHUFFLE_TYPES.map((type) => {
                                    let tooltip = ""
                                    switch (type) {
                                        case "Fisher-Yates":
                                            tooltip = "Shuffles using the Fisher-Yates method, randomizing the queue"
                                            break
                                        case "Algorithmic":
                                            tooltip = "Shuffles using a custom method, pseudo-randomizing the queue"
                                            break
                                    }

                                    return (
                                        <MenuItem key={type} value={type}>
                                            <Tooltip title={tooltip} disableInteractive>
                                                <span>{type}</span>
                                            </Tooltip>
                                        </MenuItem>
                                    )
                                })}
                            </Select>
                        </FormControl>
                    </Box>
                </SettingRowBox>

                <SettingRowBox>
                    <Typography variant="body1">List Play Type</Typography>

                    <Box sx={{ marginLeft: "auto" }}>
                        <FormControl>
                            <Select
                                size="small"
                                value={settings.listPlay || "Single"}
                                onChange={(e) => updateSettings({ listPlay: e.target.value as typeof settings.listPlay })}
                            >
                                {LIST_PLAY_TYPES.map((type) => {
                                    let tooltip = ""
                                    switch (type) {
                                        case "Single":
                                            tooltip = "When selecting a song from a list, only plays that song"
                                            break
                                        case "Multiple":
                                            tooltip = "When selecting a song from a list, plays that song and adds the rest to the queue"
                                            break
                                    }

                                    return (
                                        <MenuItem key={type} value={type}>
                                            <Tooltip title={tooltip} disableInteractive>
                                                <span>{type}</span>
                                            </Tooltip>
                                        </MenuItem>
                                    )
                                })}
                            </Select>
                        </FormControl>
                    </Box>
                </SettingRowBox>
            </Box>
            
        </Box>
    )
}

const SettingRowBox: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    return (
        <Box display="flex" flexDirection="row" sx={{
            height: "64px", margin: "12px 24px 12px 24px", backgroundColor: "rgba(0, 0, 0, 0.35)",
            borderRadius: "12px", padding: "0px 24px 0px 24px", alignItems: "center"
        }}>
            { children }
        </Box>
    )
}

const AccountRow: React.FC<{
    serviceName: string,
    // eslint-disable-next-line @typescript-eslint/ban-types
    ServiceIcon: OverridableComponent<SvgIconTypeMap<{}, "svg">> & {
        muiName: string;
    },
    loginState: boolean,
    loginHandler: () => void
}> = 
({ serviceName, ServiceIcon, loginState, loginHandler }) => {
    return (
        <SettingRowBox>
                <ServiceIcon sx={{ marginRight: "12px" }}/>

                <Typography variant="body1">{ serviceName }</Typography>
                
                <Box display="flex" sx={{ marginLeft: "auto" }}>
                    {loginState ?
                    <Typography variant="body1" color="success" sx={{ alignSelf: "center", marginRight: "12px"}}>
                        Logged In
                    </Typography>
                    :   <Typography variant="body1" color="error" sx={{ alignSelf: "center", marginRight: "12px"}}>
                        Not Logged In
                    </Typography>}
                    {loginState ?
                        <IconButton disabled>
                            <CheckIcon />
                        </IconButton>
                    :   <IconButton onClick={loginHandler}>
                            <LoginIcon />
                        </IconButton>}
                </Box>
        </SettingRowBox>
    )
}