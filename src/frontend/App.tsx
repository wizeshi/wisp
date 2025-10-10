import { ThemeProvider } from "@mui/material/styles/"
import React from "react"
import { Titlebar } from "./components/Titlebar"
import { theme } from "./utils/Theme"
/* import "@fontsource/roboto" */
import "@fontsource-variable/jetbrains-mono"
import { AppContextProvider, useAppContext } from "./providers/AppContext"
import { Sidebar } from "./components/Sidebar"
import { HomeScreen } from "./views/HomeScreen"
import Box from "@mui/material/Box"
import { PlayerBar } from "./components/PlayerBar"
import { ListScreen } from "./views/ListScreen"
import { SearchScreen } from "./views/SearchScreen"
import { Settings } from "./views/Settings"
import { SongQueue } from "./views/SongQueue"

export const App: React.FC = () => {
    const { app, music } = useAppContext()

    let mainContent

    switch (app.screen.currentView) {
        default:
        case "home":
            mainContent = <HomeScreen />
            break
        case "sidebarList":
            mainContent = <ListScreen />
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

    const currentSong = music.player.getCurrentSong()
    const backgroundImage = currentSong?.thumbnailURL || ""

    return (
            <ThemeProvider theme={theme}>
                <Titlebar />
                <Sidebar />

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
                    <Box sx={{ position: "relative", zIndex: 2, width: "100%" }}>
                        { mainContent }
                    </Box>
                </Box>

                <PlayerBar />
            </ThemeProvider>
    )
}