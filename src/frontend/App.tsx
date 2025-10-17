import React, { useEffect, useState } from "react"
import { Titlebar } from "./components/Titlebar"
import { theme } from "./utils/Theme"
import { useAppContext } from "./providers/AppContext"
import { PlayerProvider, usePlayer } from "./providers/PlayerContext"
import { Sidebar } from "./components/Sidebar"
import { HomeScreen } from "./views/HomeScreen"
import Box from "@mui/material/Box"
import { PlayerBar } from "./components/PlayerBar"
import { ListScreen } from "./views/ListScreen"
import { SearchScreen } from "./views/SearchScreen"
import { Settings } from "./views/Settings"
import { SongQueue } from "./views/SongQueue"
import { ArtistScreen } from "./views/ArtistScreen"
import { FirstTimeScreen } from "./views/FirstTimeScreen"
import CircularProgress from "@mui/material/CircularProgress"
import { LyricsScreen } from "./views/LyricsScreen"
import { LikesView } from "./views/LikesView"
import { ContextMenuProvider } from "./providers/ContextMenuProvider"

export const App: React.FC = () => {
    const { app } = useAppContext()
    const [isFirstTimeSetup, setIsFirstTimeSetup] = useState<boolean>(false)
    const [isCheckingSetup, setIsCheckingSetup] = useState<boolean>(true)

    // Check if user is new on mount
    useEffect(() => {
        const checkFirstTimeSetup = async () => {
            try {
                const userData = await window.electronAPI.info.data.load()
                const hasCredentials = await window.electronAPI.info.credentials.has()
                setIsFirstTimeSetup(userData.isNewUser || !hasCredentials)
            } catch (error) {
                console.error("Error checking setup status:", error)
                setIsFirstTimeSetup(true)
            } finally {
                setIsCheckingSetup(false)
            }
        }
        checkFirstTimeSetup()
    }, [])

    if (isCheckingSetup) {
        return (
            <Box sx={{ 
                height: "100vh", 
                width: "100vw", 
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: "linear-gradient(135deg, rgba(25,25,25,1) 0%, rgba(15,15,15,1) 100%)"
            }}>
                <CircularProgress />
            </Box>
        )
    }

    let mainContent
    switch (app.screen.currentView) {
        default:
        case "home":
            mainContent = <HomeScreen />
            break
        case "likesView":
            mainContent = <LikesView />
            break
        case "listView":
            mainContent = <ListScreen />
            break
        case "artistView":
            mainContent = <ArtistScreen artistId={app.screen.shownThing.id}/>
            break
        case "lyricsView":
            mainContent = <LyricsScreen />
            break
        case "search":
            mainContent = <SearchScreen searchQuery={app.screen.search} />
            break
        case "settings":
            mainContent = <Settings />
            break
        case "songQueue":
            mainContent = <SongQueue />
            break
    }

    if (isFirstTimeSetup) {
        return (
            <Box sx={{ 
                height: "100vh", 
                width: "100vw", 
                overflow: "hidden",
                display: "flex",
                flexDirection: "column"
            }}>
                <Titlebar />
                <FirstTimeScreen />
            </Box>
        )
    }

    return (
        <>
            <Titlebar />
            <Sidebar />
            <PlayerProviderContent mainContent={mainContent} app={app} />
        </>
    )

}

// Helper component to use usePlayer inside PlayerProvider
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const PlayerProviderContent: React.FC<{ mainContent: React.ReactNode, app: any }> = ({ mainContent, app }) => {
    const player = usePlayer();
    const currentSong = player.getCurrentSong();
    const backgroundImage = currentSong?.thumbnailURL || "";
    return (
        <>
            <Box 
                display="flex" 
                sx={{ 
                    maxHeight: "calc(100vh - 32px)",
                    position: "relative",
                    height: "100%",
                    overflow: "hidden",
                    ...(backgroundImage && {
                        "&::before": {
                            content: '""',
                            position: "absolute",
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            backgroundImage: `url("${backgroundImage}")`,
                            backgroundSize: "cover",
                            backgroundPosition: "center",
                            backgroundRepeat: "no-repeat",
                            filter: "blur(28px) brightness(0.4)",
                            transform: "scale(1.1)",
                            zIndex: 0,
                            maxHeight: "calc(100% - 64px)" 
                        },
                        "&::after": {
                            content: '""',
                            position: "absolute",
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            background: "linear-gradient(to bottom, rgba(0,0,0,0.4), rgba(0,0,0,0.7))",
                            zIndex: 1,
                        }
                    })
                }} 
                position="relative" 
                left={app.sidebar.open ? "320px" : `calc(${theme.spacing(11)} + 1px)`} 
                maxWidth={app.sidebar.open ? `calc(100% - 320px)` : `calc(100% - calc(${theme.spacing(11)} + 1px))`}
            >
                <Box sx={{ position: "relative", zIndex: 2, width: "100%", maxHeight: "inherit", display: "flex", overflowY: "auto" }}>
                    { mainContent }
                </Box>
            </Box>
            <PlayerBar />
        </>
    );
}