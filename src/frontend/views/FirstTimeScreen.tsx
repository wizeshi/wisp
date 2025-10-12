import React, { useEffect, useState } from "react"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Button from "@mui/material/Button"
import TextField from "@mui/material/TextField"
import Stepper from "@mui/material/Stepper"
import Step from "@mui/material/Step"
import StepLabel from "@mui/material/StepLabel"
import Alert from "@mui/material/Alert"
import AlertTitle from "@mui/material/AlertTitle"
import Card from "@mui/material/Card"
import CardContent from "@mui/material/CardContent"
import Link from "@mui/material/Link"
import CircularProgress from "@mui/material/CircularProgress"
import CheckCircleIcon from "@mui/icons-material/CheckCircle"
import ErrorIcon from "@mui/icons-material/Error"
import MusicNoteIcon from "@mui/icons-material/MusicNote"
import Avatar from "@mui/material/Avatar"
import logoImage from "../../../assets/wisp.png"
import { APICredentials } from "../../backend/utils/types"

const steps = [
    "Welcome",
    "Spotify Setup",
    "YouTube Setup",
    "Authentication",
    "Download Tools",
    "Complete"
]

interface AuthStatus {
    spotify: "idle" | "loading" | "success" | "error"
    youtube: "idle" | "loading" | "success" | "error"
}

interface DownloadStatus {
    ytdlp: "idle" | "downloading" | "success" | "error"
    ffmpeg: "idle" | "downloading" | "success" | "error"
}

export const FirstTimeScreen: React.FC = () => {
    const [activeStep, setActiveStep] = useState(0)
    const [credentials, setCredentials] = useState<APICredentials>({
        spotifyClientId: "",
        spotifyClientSecret: "",
        youtubeClientId: "",
        youtubeClientSecret: "",
        spotifyCookie: ""
    })
    const [authStatus, setAuthStatus] = useState<AuthStatus>({
        spotify: "idle",
        youtube: "idle"
    })
    const [downloadStatus, setDownloadStatus] = useState<DownloadStatus>({
        ytdlp: "idle",
        ffmpeg: "idle"
    })
    const [errors, setErrors] = useState<Record<string, string>>({})

    // Listen for Spotify OAuth events
    useEffect(() => {
        window.electronAPI.login.spotify.onSuccess(() => {
            setAuthStatus(prev => ({ ...prev, spotify: "success" }))
        })

        window.electronAPI.login.spotify.onError((error) => {
            console.error("Spotify auth error:", error)
            setAuthStatus(prev => ({ ...prev, spotify: "error" }))
        })
    }, [])

    // Listen for YouTube OAuth events
    useEffect(() => {
        window.electronAPI.login.youtube.onSuccess(() => {
            setAuthStatus(prev => ({ ...prev, youtube: "success" }))
        })

        window.electronAPI.login.youtube.onError((error) => {
            console.error("YouTube auth error:", error)
            setAuthStatus(prev => ({ ...prev, youtube: "error" }))
        })
    }, [])

    const handleNext = () => {
        setActiveStep((prevStep) => prevStep + 1)
    }

    const handleBack = () => {
        setActiveStep((prevStep) => prevStep - 1)
    }

    const handleCredentialChange = (field: keyof APICredentials) => (
        event: React.ChangeEvent<HTMLInputElement>
    ) => {
        setCredentials({
            ...credentials,
            [field]: event.target.value
        })
        // Clear error when user starts typing
        if (errors[field]) {
            setErrors({ ...errors, [field]: "" })
        }
    }

    const validateSpotifyCredentials = () => {
        const newErrors: Record<string, string> = {}
        
        if (!credentials.spotifyClientId.trim()) {
            newErrors.spotifyClientId = "Spotify Client ID is required"
        }
        if (!credentials.spotifyClientSecret.trim()) {
            newErrors.spotifyClientSecret = "Spotify Client Secret is required"
        }
        
        setErrors(newErrors)
        return Object.keys(newErrors).length === 0
    }

    const validateYoutubeCredentials = () => {
        const newErrors: Record<string, string> = {}
        
        if (!credentials.youtubeClientId.trim()) {
            newErrors.youtubeClientId = "YouTube Client ID is required"
        }
        if (!credentials.youtubeClientSecret.trim()) {
            newErrors.youtubeClientSecret = "YouTube Client Secret is required"
        }
        
        setErrors(newErrors)
        return Object.keys(newErrors).length === 0
    }

    const handleSpotifyNext = async () => {
        if (validateSpotifyCredentials()) {
            try {
                // Save credentials (partial save for now, will be completed after YouTube step)
                await window.electronAPI.info.credentials.save(credentials)
                handleNext()
            } catch (error) {
                console.error("Error saving Spotify credentials:", error)
                setErrors({ ...errors, spotifyClientId: "Failed to save credentials" })
            }
        }
    }

    const handleYoutubeNext = async () => {
        if (validateYoutubeCredentials()) {
            try {
                // Save complete credentials
                await window.electronAPI.info.credentials.save(credentials)
                handleNext()
            } catch (error) {
                console.error("Error saving YouTube credentials:", error)
                setErrors({ ...errors, youtubeClientId: "Failed to save credentials" })
            }
        }
    }

    const handleSpotifyAuth = () => {
        setAuthStatus(prev => ({ ...prev, spotify: "loading" }))
        // Trigger Spotify OAuth flow - events will update status
        window.electronAPI.login.spotify.login()
    }

    const handleYoutubeAuth = () => {
        setAuthStatus(prev => ({ ...prev, youtube: "loading" }))
        // Trigger YouTube OAuth flow - events will update status
        window.electronAPI.login.youtube.login()
    }

    const handleDownloadTools = async () => {
        // Download yt-dlp
        setDownloadStatus(prev => ({ ...prev, ytdlp: "downloading" }))
        try {
            await window.electronAPI.ytdlp.ensure()
            setDownloadStatus(prev => ({ ...prev, ytdlp: "success" }))
        } catch (error) {
            console.error("Error downloading yt-dlp:", error)
            setDownloadStatus(prev => ({ ...prev, ytdlp: "error" }))
            return
        }

        // Download ffmpeg
        setDownloadStatus(prev => ({ ...prev, ffmpeg: "downloading" }))
        try {
            await window.electronAPI.ytdlp.ensureFfmpeg()
            setDownloadStatus(prev => ({ ...prev, ffmpeg: "success" }))
        } catch (error) {
            console.error("Error downloading ffmpeg:", error)
            setDownloadStatus(prev => ({ ...prev, ffmpeg: "error" }))
        }
    }

    const handleComplete = async () => {
        try {
            // Mark user as not new
            const userData = await window.electronAPI.info.data.load()
            await window.electronAPI.info.data.save({ ...userData, isNewUser: false })
            
            console.log("Setup complete! User data updated.")
            
            // Reload the page to show the main app
            window.location.reload()
        } catch (error) {
            console.error("Error completing setup:", error)
        }
    }

    const renderStepContent = () => {
        switch (activeStep) {
            case 0:
                return <WelcomeStep onNext={handleNext} />
            
            case 1:
                return (
                    <SpotifySetupStep
                        credentials={credentials}
                        errors={errors}
                        onChange={handleCredentialChange}
                        onNext={handleSpotifyNext}
                        onBack={handleBack}
                    />
                )
            
            case 2:
                return (
                    <YoutubeSetupStep
                        credentials={credentials}
                        errors={errors}
                        onChange={handleCredentialChange}
                        onNext={handleYoutubeNext}
                        onBack={handleBack}
                    />
                )
            
            case 3:
                return (
                    <AuthenticationStep
                        authStatus={authStatus}
                        onSpotifyAuth={handleSpotifyAuth}
                        onYoutubeAuth={handleYoutubeAuth}
                        onNext={handleNext}
                        onBack={handleBack}
                    />
                )
            
            case 4:
                return (
                    <DownloadToolsStep
                        downloadStatus={downloadStatus}
                        onDownload={handleDownloadTools}
                        onNext={handleNext}
                        onBack={handleBack}
                    />
                )
            
            case 5:
                return <CompleteStep onComplete={handleComplete} />
            
            default:
                return null
        }
    }

    return (
        <Box
            sx={{
                flex: 1,
                width: "100%",
                overflowY: "auto",
                overflowX: "hidden",
                background: "linear-gradient(135deg, rgba(25,25,25,1) 0%, rgba(15,15,15,1) 100%)",
                display: "flex",
                flexDirection: "column",
                alignItems: "center"
            }}
        >
            <Box sx={{ 
                maxWidth: "800px", 
                width: "100%", 
                padding: "48px 24px 80px 24px",
                boxSizing: "border-box"
            }}>
                <Box display="flex" alignItems="center" justifyContent="center" sx={{ marginBottom: "32px", gap: "16px" }}>
                    <Avatar variant="rounded" src={logoImage} sx={{ aspectRatio: "1/1", height: "48px", width: "auto"}}/>
                    <Typography variant="h3" fontWeight="bold">
                        WISP Setup
                    </Typography>
                </Box>

                {/* Stepper */}
                <Stepper activeStep={activeStep} sx={{ marginBottom: "32px" }}>
                    {steps.map((label) => (
                        <Step key={label}>
                            <StepLabel>{label}</StepLabel>
                        </Step>
                    ))}
                </Stepper>

                {/* Step Content */}
                <Card sx={{ backgroundColor: "rgba(0, 0, 0, 0.4)", backdropFilter: "blur(10px)" }}>
                    <CardContent sx={{ padding: "32px" }}>
                        {renderStepContent()}
                    </CardContent>
                </Card>
            </Box>
        </Box>
    )
}

const WelcomeStep: React.FC<{ onNext: () => void }> = ({ onNext }) => (
    <Box>
        <Typography variant="h4" gutterBottom>
            Welcome to WISP! 🎵
        </Typography>
        <Typography variant="body1" paragraph>
            <strong>wizeshi's Interfaceable Song Provider</strong> is your unified music player for Spotify and YouTube.
        </Typography>
        
        <Alert severity="info" sx={{ marginTop: "24px", marginBottom: "24px" }}>
            <AlertTitle>What You'll Need</AlertTitle>
            To use WISP, you'll need to provide your own API credentials:
            <ul>
                <li><strong>Spotify</strong>: Client ID and Client Secret (free)</li>
                <li><strong>YouTube</strong>: Client ID and Client Secret (free with quota limits)</li>
            </ul>
            Don't worry! We'll guide you through getting these in the next steps.
        </Alert>

        <Typography variant="body2" color="textSecondary" paragraph>
            <strong>Why do I need my own API keys?</strong><br />
            This ensures you have full control over your data, unlimited usage (within provider limits),
            and compliance with API terms of service.
        </Typography>

        <Box display="flex" justifyContent="flex-end" sx={{ marginTop: "24px" }}>
            <Button variant="contained" onClick={onNext} size="large">
                Get Started
            </Button>
        </Box>
    </Box>
)

interface SpotifySetupStepProps {
    credentials: APICredentials
    errors: Record<string, string>
    onChange: (field: keyof APICredentials) => (event: React.ChangeEvent<HTMLInputElement>) => void
    onNext: () => void
    onBack: () => void
}

const SpotifySetupStep: React.FC<SpotifySetupStepProps> = ({
    credentials,
    errors,
    onChange,
    onNext,
    onBack
}) => (
    <Box>
        <Typography variant="h4" gutterBottom>
            Spotify API Setup
        </Typography>
        
        <Alert severity="info" sx={{ marginBottom: "24px" }}>
            <AlertTitle>How to Get Spotify Credentials</AlertTitle>
            <ol style={{ paddingLeft: "20px", margin: "8px 0" }}>
                <li>Go to <Link href="https://developer.spotify.com/dashboard" target="_blank" rel="noopener">Spotify Developer Dashboard</Link></li>
                <li>Log in with your Spotify account</li>
                <li>Click "Create app"</li>
                <li>Fill in app name (e.g., "WISP") and description</li>
                <li>Add Redirect URI: <code>wisp-login://callback</code></li>
                <li>Check "Web API" and accept terms</li>
                <li>Copy your <strong>Client ID</strong> and <strong>Client Secret</strong></li>
            </ol>
        </Alert>

        <TextField
            fullWidth
            label="Spotify Client ID"
            value={credentials.spotifyClientId}
            onChange={onChange("spotifyClientId")}
            error={Boolean(errors.spotifyClientId)}
            helperText={errors.spotifyClientId || "Found in your Spotify app's Settings"}
            margin="normal"
            variant="outlined"
        />

        <TextField
            fullWidth
            label="Spotify Client Secret"
            type="password"
            value={credentials.spotifyClientSecret}
            onChange={onChange("spotifyClientSecret")}
            error={Boolean(errors.spotifyClientSecret)}
            helperText={errors.spotifyClientSecret || "Click 'View client secret' in your app settings"}
            margin="normal"
            variant="outlined"
        />

        <Box display="flex" justifyContent="space-between" sx={{ marginTop: "24px" }}>
            <Button onClick={onBack}>
                Back
            </Button>
            <Button variant="contained" onClick={onNext}>
                Next
            </Button>
        </Box>
    </Box>
)

interface YoutubeSetupStepProps {
    credentials: APICredentials
    errors: Record<string, string>
    onChange: (field: keyof APICredentials) => (event: React.ChangeEvent<HTMLInputElement>) => void
    onNext: () => void
    onBack: () => void
}

const YoutubeSetupStep: React.FC<YoutubeSetupStepProps> = ({
    credentials,
    errors,
    onChange,
    onNext,
    onBack
}) => (
    <Box>
        <Typography variant="h4" gutterBottom>
            YouTube API Setup
        </Typography>
        
        <Alert severity="info" sx={{ marginBottom: "24px" }}>
            <AlertTitle>How to Get YouTube Credentials</AlertTitle>
            <ol style={{ paddingLeft: "20px", margin: "8px 0" }}>
                <li>Go to <Link href="https://console.cloud.google.com/" target="_blank" rel="noopener">Google Cloud Console</Link></li>
                <li>Click Control + O and create a new project or select an existing one</li>
                <li>Go to "APIs & Services" → "Library"</li>
                <li>Search for "YouTube Data API v3" and enable it</li>
                <li>Go to "Credentials" → "Create Credentials" → "OAuth client ID"</li>
                <li>Select application type: <strong>"Web application"</strong></li>
                <li>Add Authorized redirect URI: <code>http://127.0.0.1:8080/callback</code></li>
                <li>Copy your <strong>Client ID</strong> and <strong>Client Secret</strong></li>
            </ol>
        </Alert>

        <Alert severity="warning" sx={{ marginBottom: "24px" }}>
            <strong>Note:</strong> YouTube API has daily quota limits (10,000 units/day for free tier).
            This is usually sufficient for personal use.
        </Alert>

        <TextField
            fullWidth
            label="YouTube Client ID"
            value={credentials.youtubeClientId}
            onChange={onChange("youtubeClientId")}
            error={Boolean(errors.youtubeClientId)}
            helperText={errors.youtubeClientId || "Found in your OAuth 2.0 Client"}
            margin="normal"
            variant="outlined"
        />

        <TextField
            fullWidth
            label="YouTube Client Secret"
            type="password"
            value={credentials.youtubeClientSecret}
            onChange={onChange("youtubeClientSecret")}
            error={Boolean(errors.youtubeClientSecret)}
            helperText={errors.youtubeClientSecret || "Found in your OAuth 2.0 Client"}
            margin="normal"
            variant="outlined"
        />

        <Box display="flex" justifyContent="space-between" sx={{ marginTop: "24px" }}>
            <Button onClick={onBack}>
                Back
            </Button>
            <Button variant="contained" onClick={onNext}>
                Next
            </Button>
        </Box>
    </Box>
)

interface AuthenticationStepProps {
    authStatus: AuthStatus
    onSpotifyAuth: () => void
    onYoutubeAuth: () => void
    onNext: () => void
    onBack: () => void
}

const AuthenticationStep: React.FC<AuthenticationStepProps> = ({
    authStatus,
    onSpotifyAuth,
    onYoutubeAuth,
    onNext,
    onBack
}) => {
    const allAuthenticated = authStatus.spotify === "success" && authStatus.youtube === "success"

    return (
        <Box>
            <Typography variant="h4" gutterBottom>
                Authenticate Your Accounts
            </Typography>
            
            <Typography variant="body1" paragraph>
                Now let's connect your Spotify and YouTube accounts to WISP.
            </Typography>

            {/* Spotify Authentication */}
            <Card sx={{ marginBottom: "16px", backgroundColor: "rgba(30, 215, 96, 0.1)" }}>
                <CardContent>
                    <Box display="flex" alignItems="center" justifyContent="space-between">
                        <Box>
                            <Typography variant="h6">Spotify</Typography>
                            <Typography variant="body2" color="textSecondary">
                                Connect your Spotify account
                            </Typography>
                        </Box>
                        <Box display="flex" alignItems="center" gap={2}>
                            {authStatus.spotify === "success" && (
                                <CheckCircleIcon color="success" />
                            )}
                            {authStatus.spotify === "error" && (
                                <ErrorIcon color="error" />
                            )}
                            {authStatus.spotify === "loading" ? (
                                <CircularProgress size={24} />
                            ) : (
                                <Button
                                    variant="contained"
                                    onClick={onSpotifyAuth}
                                    disabled={authStatus.spotify === "success"}
                                    color={authStatus.spotify === "success" ? "success" : "primary"}
                                >
                                    {authStatus.spotify === "success" ? "Connected" : "Connect Spotify"}
                                </Button>
                            )}
                        </Box>
                    </Box>
                </CardContent>
            </Card>

            {/* YouTube Authentication */}
            <Card sx={{ marginBottom: "16px", backgroundColor: "rgba(255, 0, 0, 0.1)" }}>
                <CardContent>
                    <Box display="flex" alignItems="center" justifyContent="space-between">
                        <Box>
                            <Typography variant="h6">YouTube</Typography>
                            <Typography variant="body2" color="textSecondary">
                                Connect your YouTube account
                            </Typography>
                        </Box>
                        <Box display="flex" alignItems="center" gap={2}>
                            {authStatus.youtube === "success" && (
                                <CheckCircleIcon color="success" />
                            )}
                            {authStatus.youtube === "error" && (
                                <ErrorIcon color="error" />
                            )}
                            {authStatus.youtube === "loading" ? (
                                <CircularProgress size={24} />
                            ) : (
                                <Button
                                    variant="contained"
                                    onClick={onYoutubeAuth}
                                    disabled={authStatus.youtube === "success"}
                                    color={authStatus.youtube === "success" ? "success" : "error"}
                                >
                                    {authStatus.youtube === "success" ? "Connected" : "Connect YouTube"}
                                </Button>
                            )}
                        </Box>
                    </Box>
                </CardContent>
            </Card>

            <Box display="flex" justifyContent="space-between" sx={{ marginTop: "24px" }}>
                <Button onClick={onBack}>
                    Back
                </Button>
                <Button
                    variant="contained"
                    onClick={onNext}
                    disabled={!allAuthenticated}
                >
                    Continue
                </Button>
            </Box>
        </Box>
    )
}

interface DownloadToolsStepProps {
    downloadStatus: DownloadStatus
    onDownload: () => void
    onNext: () => void
    onBack: () => void
}

const DownloadToolsStep: React.FC<DownloadToolsStepProps> = ({
    downloadStatus,
    onDownload,
    onNext,
    onBack
}) => {
    const allDownloaded = downloadStatus.ytdlp === "success" && downloadStatus.ffmpeg === "success"
    const isDownloading = downloadStatus.ytdlp === "downloading" || downloadStatus.ffmpeg === "downloading"

    return (
        <Box>
            <Typography variant="h4" gutterBottom>
                Download Required Tools
            </Typography>
            
            <Typography variant="body1" paragraph>
                To download YouTube audio, WISP needs two tools: <strong>yt-dlp</strong> and <strong>ffmpeg</strong>.
                Don't worry—they'll be downloaded automatically and stored in your app data folder.
            </Typography>

            <Alert severity="info" sx={{ marginBottom: "24px" }}>
                <AlertTitle>What will be downloaded?</AlertTitle>
                <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
                    <li><strong>yt-dlp</strong> (~10 MB) - Downloads YouTube videos and extracts audio</li>
                    <li><strong>ffmpeg</strong> (~50-100 MB) - Converts audio to the correct format</li>
                </ul>
                Total download: ~60-110 MB depending on your platform
            </Alert>

            {/* yt-dlp Download Status */}
            <Card sx={{ marginBottom: "16px", backgroundColor: "rgba(255, 255, 255, 0.05)" }}>
                <CardContent>
                    <Box display="flex" alignItems="center" justifyContent="space-between">
                        <Box>
                            <Typography variant="h6">yt-dlp</Typography>
                            <Typography variant="body2" color="textSecondary">
                                YouTube downloader tool
                            </Typography>
                        </Box>
                        <Box display="flex" alignItems="center" gap={2}>
                            {downloadStatus.ytdlp === "success" && (
                                <CheckCircleIcon color="success" />
                            )}
                            {downloadStatus.ytdlp === "error" && (
                                <ErrorIcon color="error" />
                            )}
                            {downloadStatus.ytdlp === "downloading" && (
                                <CircularProgress size={24} />
                            )}
                            {downloadStatus.ytdlp === "idle" && (
                                <Typography variant="body2" color="textSecondary">
                                    Ready to download
                                </Typography>
                            )}
                        </Box>
                    </Box>
                </CardContent>
            </Card>

            {/* ffmpeg Download Status */}
            <Card sx={{ marginBottom: "16px", backgroundColor: "rgba(255, 255, 255, 0.05)" }}>
                <CardContent>
                    <Box display="flex" alignItems="center" justifyContent="space-between">
                        <Box>
                            <Typography variant="h6">ffmpeg</Typography>
                            <Typography variant="body2" color="textSecondary">
                                Audio processing tool
                            </Typography>
                        </Box>
                        <Box display="flex" alignItems="center" gap={2}>
                            {downloadStatus.ffmpeg === "success" && (
                                <CheckCircleIcon color="success" />
                            )}
                            {downloadStatus.ffmpeg === "error" && (
                                <ErrorIcon color="error" />
                            )}
                            {downloadStatus.ffmpeg === "downloading" && (
                                <CircularProgress size={24} />
                            )}
                            {downloadStatus.ffmpeg === "idle" && (
                                <Typography variant="body2" color="textSecondary">
                                    Ready to download
                                </Typography>
                            )}
                        </Box>
                    </Box>
                </CardContent>
            </Card>

            {/* Download Button */}
            {!allDownloaded && !isDownloading && (
                <Box display="flex" justifyContent="center" sx={{ marginTop: "24px", marginBottom: "24px" }}>
                    <Button
                        variant="contained"
                        size="large"
                        onClick={onDownload}
                        disabled={isDownloading}
                    >
                        Download Tools
                    </Button>
                </Box>
            )}

            {isDownloading && (
                <Alert severity="info" sx={{ marginTop: "24px" }}>
                    Downloading tools... This may take a minute depending on your internet speed.
                </Alert>
            )}

            {allDownloaded && (
                <Alert severity="success" sx={{ marginTop: "24px" }}>
                    <AlertTitle>Download Complete!</AlertTitle>
                    Both tools have been successfully downloaded and verified.
                </Alert>
            )}

            <Box display="flex" justifyContent="space-between" sx={{ marginTop: "24px" }}>
                <Button onClick={onBack} disabled={isDownloading}>
                    Back
                </Button>
                <Button
                    variant="contained"
                    onClick={onNext}
                    disabled={!allDownloaded}
                >
                    Continue
                </Button>
            </Box>
        </Box>
    )
}

const CompleteStep: React.FC<{ onComplete: () => void }> = ({ onComplete }) => (
    <Box textAlign="center">
        <CheckCircleIcon sx={{ fontSize: 64, color: "success.main", marginBottom: "16px" }} />
        
        <Typography variant="h4" gutterBottom>
            All Set! 🎉
        </Typography>
        
        <Typography variant="body1" paragraph>
            Your WISP setup is complete. You can now enjoy music from Spotify and YouTube
            in one unified player!
        </Typography>

        <Alert severity="success" sx={{ marginTop: "24px", marginBottom: "24px" }}>
            <AlertTitle sx={{ textAlign: "left" }}>What's Next?</AlertTitle>
            <ul style={{ paddingLeft: "20px", margin: "8px 0", textAlign: "left" }}>
                <li>Browse your Spotify playlists and albums</li>
                <li>Search for songs on YouTube</li>
                <li>Create custom queues mixing both platforms</li>
                <li>Access settings anytime to update your credentials</li>
            </ul>
        </Alert>

        <Button variant="contained" size="large" onClick={onComplete}>
            Launch WISP
        </Button>
    </Box>
)
