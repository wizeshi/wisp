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
    return (
        <AppContextProvider>
            <ThemeProvider theme={theme}>
                <Titlebar />
                <Sidebar />

                <MainContentWrapper>
                    <HomeScreen />
                </MainContentWrapper>

                <PlayerBar />
            </ThemeProvider>
        </AppContextProvider>
    )
}

const MainContentWrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const { app } = useAppContext()

    return (
        <Box display="flex" position="relative" left={app.sidebar.open ? "240px" : `calc(${theme.spacing(11)} + 1px)`} maxWidth={app.sidebar.open ? `calc(100% - 240px)` : `calc(100% - calc(${theme.spacing(11)} + 1px))`}>
            { children }
        </Box>
    )
}