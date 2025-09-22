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

export const App: React.FC = () => {
    const { app } = useAppContext()

    let mainContent

    switch (app.screen.currentView) {
        default:
        case "home":
            mainContent = <HomeScreen />
    }

    return (
            <ThemeProvider theme={theme}>
                <Titlebar />
                <Sidebar />

                <Box display="flex" position="relative" left={app.sidebar.open ? "240px" : `calc(${theme.spacing(11)} + 1px)`} maxWidth={app.sidebar.open ? `calc(100% - 240px)` : `calc(100% - calc(${theme.spacing(11)} + 1px))`}>
                    { mainContent }
                </Box>


                <PlayerBar />
            </ThemeProvider>
    )
}