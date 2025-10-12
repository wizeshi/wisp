import Typography from "@mui/material/Typography";
import Box from "@mui/material/Box";
import React, { JSX, useEffect, useState } from "react";
import Divider from "@mui/material/Divider";
import GraphicEqIcon from '@mui/icons-material/GraphicEq';
import IconButton from "@mui/material/IconButton";
import LoginIcon from '@mui/icons-material/Login';
import CheckIcon from '@mui/icons-material/Check';
import EditIcon from '@mui/icons-material/Edit';
import { SvgIconTypeMap } from "@mui/material/SvgIcon";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import YoutubeIcon from '@mui/icons-material/YouTube'
import { LIST_PLAY_TYPES, SHUFFLE_TYPES } from "../../backend/utils/types";
import Select from "@mui/material/Select";
import MenuItem from "@mui/material/MenuItem";
import FormControl from "@mui/material/FormControl";
import { useSettings } from "../hooks/useSettings";
import Tooltip from "@mui/material/Tooltip";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import TextField from "@mui/material/TextField";
import Button from "@mui/material/Button";
import InputAdornment from "@mui/material/InputAdornment";
import Visibility from "@mui/icons-material/Visibility";
import VisibilityOff from "@mui/icons-material/VisibilityOff";
import Alert from "@mui/material/Alert";
import Avatar from "@mui/material/Avatar";

const LyricsProviders = [
    {
        name: "Spotify",
        iconUrl: "https://storage.googleapis.com/pr-newsroom-wp/1/2023/05/Spotify_Primary_Logo_RGB_White.png"
    },
    {
        name: "Genius",
        iconUrl: "https://images.genius.com/0ca83e3130e1303a7f78ba351e3091cd.1000x1000x1.png",
    },
    {
        name: "MusixMatch",
        iconUrl: "https://dashboard.snapcraft.io/site_media/appmedia/2018/09/Mark256.png"
    },
    {
        name: "LrcLib",
        iconUrl: "https://lrclib.net/assets/lrclib-370c57eb.png"
    },
]

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
        window.electronAPI.login.spotify.onSuccess(() => {
            console.log('Spotify login successful')
            setSpotifyLoggedIn(true)
        })

        window.electronAPI.login.spotify.onError((error) => {
            console.error('Spotify login error:', error)
        })

        window.electronAPI.login.youtube.onSuccess(() => {
            console.log('YouTube login successful')
            setYoutubeLoggedIn(true)
        })

        window.electronAPI.login.youtube.onError((error) => {
            console.error('YouTube login error:', error)
        })
    }, [])

    useEffect(() => {
        let cancelled = false;
        Promise.all([
            window.electronAPI.login.spotify.loggedIn(),
            window.electronAPI.login.youtube.loggedIn()
        ]).then(([spotify, youtube]) => {
            console.log(spotify)
            console.log(youtube)
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

            <Box sx={{ overflowY: "scroll", flexShrink: 0 }}>
                <Box>
                    <Typography variant="h6">Accounts</Typography>

                    <Box>
                        <AccountRow 
                            serviceName="Spotify" 
                            ServiceIcon={GraphicEqIcon} 
                            loginState={spotifyLoggedIn} 
                            loginHandler={handleSpotifyLogin}
                        />

                        <AccountRow 
                            serviceName="Youtube" 
                            ServiceIcon={YoutubeIcon} 
                            loginState={youtubeLoggedIn} 
                            loginHandler={handleYoutubeLogin}
                        />
                    </Box>
                </Box>

                <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />

                <Box>
                    <Typography variant="h6">Lyrics Providers</Typography>

                    {LyricsProviders.map((provider) => (
                        <LyricsRow 
                            serviceName={provider.name}
                            iconUrl={provider.iconUrl}
                        />
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

const LyricsRow: React.FC<{
    serviceName: string,
    iconUrl: string,
}> = ({ serviceName, iconUrl }) => {
    const [dialogOpen, setDialogOpen] = useState(false)
    const [hasCredentials, setHasCredentials] = useState(false)
    
    useEffect(() => {
        let cancelled = false;
        window.electronAPI.info.credentials.load()
            .then((creds) => {
                if (!cancelled && creds) {
                    if (serviceName === "Spotify") {
                        setHasCredentials(!!creds.spotifyCookie)
                    }
                    // Add more providers here as needed
                }
            })
            .catch((err) => {
                console.error("Failed to load credentials:", err)
            })
        
        return () => { cancelled = true; }
    }, [serviceName])
    
    const handleEditClick = () => {
        setDialogOpen(true)
    }

    const handleDialogClose = (hadInfo: boolean) => {
        setHasCredentials(hadInfo)
        setDialogOpen(false)
    }

    return (
        <>
            <SettingRowBox>
                <Box display="flex">
                    <Box sx={{ aspectRatio: "1/1", width: "24px", height: "auto", marginRight: "12px"}}>
                        <Avatar src={iconUrl} sx={{ width: "inherit", height: "inherit" }}/>
                    </Box>

                    <Typography variant="body1">{ serviceName }</Typography>
                </Box>

                <Box display="flex" sx={{ marginLeft: "auto", gap: "8px" }}>
                        {hasCredentials ?
                        <Typography variant="body1" color="success" sx={{ alignSelf: "center", marginRight: "12px"}}>
                            Logged In
                        </Typography>
                        :   <Typography variant="body1" color="error" sx={{ alignSelf: "center", marginRight: "12px"}}>
                            Not Logged In
                        </Typography>}
                        
                        <Tooltip title="Edit API Credentials">
                            <IconButton onClick={handleEditClick}>
                                <EditIcon />
                            </IconButton>
                        </Tooltip>
                    </Box>
            </SettingRowBox>

            <LyricsCredentialDialog
                open={dialogOpen}
                serviceName={serviceName}
                onClose={handleDialogClose}
            />
        </>
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
    const [dialogOpen, setDialogOpen] = useState(false)

    const handleEditClick = () => {
        setDialogOpen(true)
    }

    const handleDialogClose = () => {
        setDialogOpen(false)
    }

    return (
        <>
            <SettingRowBox>
                    <ServiceIcon sx={{ marginRight: "12px" }}/>

                    <Typography variant="body1">{ serviceName }</Typography>
                    
                    <Box display="flex" sx={{ marginLeft: "auto", gap: "8px" }}>
                        {loginState ?
                        <Typography variant="body1" color="success" sx={{ alignSelf: "center", marginRight: "12px"}}>
                            Logged In
                        </Typography>
                        :   <Typography variant="body1" color="error" sx={{ alignSelf: "center", marginRight: "12px"}}>
                            Not Logged In
                        </Typography>}
                        
                        <Tooltip title="Edit API Credentials">
                            <IconButton onClick={handleEditClick}>
                                <EditIcon />
                            </IconButton>
                        </Tooltip>

                        {loginState ?
                            <IconButton disabled>
                                <CheckIcon />
                            </IconButton>
                        :   <IconButton onClick={loginHandler}>
                                <LoginIcon />
                            </IconButton>}
                    </Box>
            </SettingRowBox>

            <AccountCredentialDialog
                open={dialogOpen}
                serviceName={serviceName}
                onClose={handleDialogClose}
                onSave={loginHandler}
            />
        </>
    )
}

interface AccountCredentialDialogProps {
    open: boolean
    serviceName: string
    onClose: () => void
    onSave: () => void
}

const AccountCredentialDialog: React.FC<AccountCredentialDialogProps> = ({ open, serviceName, onClose, onSave }) => {
    const [clientId, setClientId] = useState("")
    const [clientSecret, setClientSecret] = useState("")
    const [showClientSecret, setShowClientSecret] = useState(false)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState("")
    const [success, setSuccess] = useState(false)

    // Load existing credentials when dialog opens
    useEffect(() => {
        if (open) {
            setLoading(true)
            setError("")
            setSuccess(false)
            
            window.electronAPI.info.credentials.load()
                .then((creds) => {
                    if (creds) {
                        if (serviceName === "Spotify") {
                            setClientId(creds.spotifyClientId || "")
                            setClientSecret(creds.spotifyClientSecret || "")
                        } else if (serviceName === "Youtube") {
                            setClientId(creds.youtubeClientId || "")
                            setClientSecret(creds.youtubeClientSecret || "")
                        }
                    }
                })
                .catch((err) => {
                    console.error("Failed to load credentials:", err)
                    setError("Failed to load existing credentials")
                })
                .finally(() => {
                    setLoading(false)
                })
        }
    }, [open, serviceName])

    const handleSave = async () => {
        if (!clientId.trim() || !clientSecret.trim()) {
            setError("Both Client ID and Client Secret are required")
            return
        }

        setLoading(true)
        setError("")
        setSuccess(false)

        try {
            // Load existing credentials to preserve other service's credentials
            const existingCreds = await window.electronAPI.info.credentials.load() || {
                spotifyClientId: "",
                spotifyClientSecret: "",
                youtubeClientId: "",
                youtubeClientSecret: "",
                spotifyCookie: ""
            }

            // Update only the current service's credentials
            const updatedCreds = { ...existingCreds }
            if (serviceName === "Spotify") {
                updatedCreds.spotifyClientId = clientId.trim()
                updatedCreds.spotifyClientSecret = clientSecret.trim()
            } else if (serviceName === "Youtube") {
                updatedCreds.youtubeClientId = clientId.trim()
                updatedCreds.youtubeClientSecret = clientSecret.trim()
            }

            await window.electronAPI.info.credentials.save(updatedCreds)
            setSuccess(true)
            
            // Close dialog after a short delay to show success message
            setTimeout(() => {
                onClose()
                onSave() // Trigger re-authentication if needed
            }, 1500)
        } catch (err) {
            console.error("Failed to save credentials:", err)
            setError("Failed to save credentials. Please try again.")
            setLoading(false)
        }
    }

    const handleClose = () => {
        if (!loading) {
            setClientId("")
            setClientSecret("")
            setShowClientSecret(false)
            setError("")
            setSuccess(false)
            onClose()
        }
    }

    return (
        <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
            <DialogTitle>
                Edit {serviceName} API Credentials
            </DialogTitle>
            <DialogContent>
                {loading && !success ? (
                    <Box display="flex" justifyContent="center" padding="24px">
                        <Typography>Loading credentials...</Typography>
                    </Box>
                ) : (
                    <>
                        {error && (
                            <Alert severity="error" sx={{ marginBottom: "16px" }}>
                                {error}
                            </Alert>
                        )}
                        
                        {success && (
                            <Alert severity="success" sx={{ marginBottom: "16px" }}>
                                Credentials updated successfully!
                            </Alert>
                        )}

                        <TextField
                            fullWidth
                            label="Client ID"
                            value={clientId}
                            onChange={(e) => setClientId(e.target.value)}
                            margin="normal"
                            type="text"
                            disabled={loading}
                        />

                        <TextField
                            fullWidth
                            label="Client Secret"
                            value={clientSecret}
                            onChange={(e) => setClientSecret(e.target.value)}
                            margin="normal"
                            type={showClientSecret ? "text" : "password"}
                            disabled={loading}
                            InputProps={{
                                endAdornment: (
                                    <InputAdornment position="end">
                                        <IconButton
                                            onClick={() => setShowClientSecret(!showClientSecret)}
                                            edge="end"
                                        >
                                            {showClientSecret ? <VisibilityOff /> : <Visibility />}
                                        </IconButton>
                                    </InputAdornment>
                                )
                            }}
                        />
                    </>
                )}
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} disabled={loading}>
                    Cancel
                </Button>
                <Button 
                    onClick={handleSave} 
                    variant="contained" 
                    disabled={loading || success}
                >
                    {loading ? "Saving..." : "Save"}
                </Button>
            </DialogActions>
        </Dialog>
    )
}

interface LyricsCredentialDialogProps {
    open: boolean
    serviceName: string
    onClose: (hadInfo: boolean) => void
}

const LyricsCredentialDialog: React.FC<LyricsCredentialDialogProps> = ({ open, serviceName, onClose }) => {
    const [apiKey, setApiKey] = useState("")
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState("")
    const [success, setSuccess] = useState(false)

    // Load existing credentials when dialog opens
    useEffect(() => {
        if (open) {
            setLoading(true)
            setError("")
            setSuccess(false)
            
            window.electronAPI.info.credentials.load()
                .then((creds) => {
                    if (creds) {
                        if (serviceName === "Spotify") {
                            setApiKey(creds.spotifyCookie || "")
                        } else if (serviceName === "Youtube") {
                            /* setClientId(creds.youtubeClientId || "")
                            setClientSecret(creds.youtubeClientSecret || "") */
                        }
                    }
                })
                .catch((err) => {
                    console.error("Failed to load credentials:", err)
                    setError("Failed to load existing credentials")
                })
                .finally(() => {
                    setLoading(false)
                })
        }
    }, [open, serviceName])

    const handleSave = async () => {
        if (!apiKey.trim()) {
            setError("An API key / Cookie is required")
            return
        }

        setLoading(true)
        setError("")
        setSuccess(false)

        try {
            // Load existing credentials to preserve other service's credentials
            const existingCreds = await window.electronAPI.info.credentials.load() || {
                spotifyClientId: "",
                spotifyClientSecret: "",
                youtubeClientId: "",
                youtubeClientSecret: "",
                spotifyCookie: ""
            }

            // Update only the current service's credentials
            const updatedCreds = { ...existingCreds }
            if (serviceName === "Spotify") {
                updatedCreds.spotifyCookie = apiKey
            } else if (serviceName === "Youtube") {
                /* updatedCreds.youtubeClientId = clientId.trim()
                updatedCreds.youtubeClientSecret = clientSecret.trim() */
            }

            await window.electronAPI.info.credentials.save(updatedCreds)
            setSuccess(true)
            
            // Close dialog after a short delay to show success message
            setTimeout(() => {
                onClose(apiKey.length > 0 ? true : false)
            }, 1500)
        } catch (err) {
            console.error("Failed to save credentials:", err)
            setError("Failed to save credentials. Please try again.")
            setLoading(false)
        }
    }

    const handleClose = () => {
        if (!loading) {
            onClose(apiKey.length > 0 ? true : false)
            setApiKey("")
            setError("")
            setSuccess(false)
        }
    }

    return (
        <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
            <DialogTitle>
                Edit {serviceName} API Credentials
            </DialogTitle>
            <DialogContent>
                {loading && !success ? (
                    <Box display="flex" justifyContent="center" padding="24px">
                        <Typography>Loading credentials...</Typography>
                    </Box>
                ) : (
                    <>
                        {error && (
                            <Alert severity="error" sx={{ marginBottom: "16px" }}>
                                {error}
                            </Alert>
                        )}
                        
                        {success && (
                            <Alert severity="success" sx={{ marginBottom: "16px" }}>
                                Credentials updated successfully!
                            </Alert>
                        )}

                        <TextField
                            fullWidth
                            label="API key / Cookie"
                            value={apiKey}
                            onChange={(e) => setApiKey(e.target.value)}
                            margin="normal"
                            type="text"
                            disabled={loading}
                        />
                    </>
                )}
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} disabled={loading}>
                    Cancel
                </Button>
                <Button 
                    onClick={handleSave} 
                    variant="contained" 
                    disabled={loading || success}
                >
                    {loading ? "Saving..." : "Save"}
                </Button>
            </DialogActions>
        </Dialog>
    )
}