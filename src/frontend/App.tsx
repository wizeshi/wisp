import { ThemeProvider } from "@mui/material/styles/"
import React from "react"
import { Titlebar } from "./components/Titlebar"
import { theme } from "./utils/theme"
/* import "@fontsource/roboto" */
import "@fontsource-variable/jetbrains-mono"
import { AppContextProvider, useAppContext } from "./providers/AppContext"
import { Sidebar } from "./components/Sidebar"
import { HomeScreen } from "./views/HomeScreen"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import { PlayerBar } from "./components/PlayerBar"
import { ListScreen } from "./views/ListScreen"
import { Album, Artist, Song } from "./utils/types"

export const App: React.FC = () => {
    const { app } = useAppContext()

    const testArtist = new Artist("Kanye West", "")

    const testSong = new Song("Intro", testArtist, true, 309, "youtube", "", "")
    const testSong2 = new Song("We Don't Care", testArtist, true, 239, "spotify", "", "")

    const testList = new Album("The College Dropout", 
        testArtist,
        "Sony Music Entertainment, Ltd.",
        true,
        [
            testSong,
            testSong2,
            testSong,
            testSong,
            testSong2,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
            testSong,
        ], 
            ""
    )

    let mainContent

    switch (app.screen.currentView) {
        default:
        case "home":
            mainContent = <HomeScreen />
            break
        case "sidebarList":
            mainContent = <ListScreen currentList={testList}/>
            break
    }

    return (
            <ThemeProvider theme={theme}>
                <Titlebar />
                <Sidebar />

                <Box display="flex" sx={{ maxHeight: "calc(100vh - 32px)" }} position="relative" left={app.sidebar.open ? "240px" : `calc(${theme.spacing(11)} + 1px)`} maxWidth={app.sidebar.open ? `calc(100% - 240px)` : `calc(100% - calc(${theme.spacing(11)} + 1px))`}>
                    { mainContent }
                </Box>

                <PlayerBar />
            </ThemeProvider>
    )
}