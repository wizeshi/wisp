import IconButton from "@mui/material/IconButton"
import Typography from "@mui/material/Typography"
import Box from "@mui/material/Box"
import React from "react"
import CloseIcon from '@mui/icons-material/Close';
import MinimizeIcon from '@mui/icons-material/Minimize';
import CheckBoxOutlineBlankIcon from '@mui/icons-material/CheckBoxOutlineBlank';
import SettingsIcon from '@mui/icons-material/Settings';
import HomeIcon from '@mui/icons-material/Home';
import TextField from "@mui/material/TextField";
import { useAppContext } from "../providers/AppContext";
import Avatar from "@mui/material/Avatar";
import logoImage from "../../../assets/wisp.png";

export const Titlebar: React.FC = () => {
    const { app } = useAppContext()

    const handleSearchInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        app.screen.setSearch(event.target.value)
        if (app.screen.currentView != "search") app.screen.setCurrentView("search")

        if (event.target.value == "") {
            app.screen.setCurrentView("home")
        }
    }

    const handleSearchKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
        if (event.key === "Enter") {
            // Trigger search or any action you want on Enter
            if (app.screen.search && app.screen.currentView != "search") {
                app.screen.setCurrentView("search")
            }
        }
    }

    const handleHome = () => {
        app.screen.setCurrentView("home")
    }

    const handleMinimize = () => {
        window.electronAPI.window.minimize()
    }

    const handleMaximize = () => {
        window.electronAPI.window.maximize()
    }
    
    const handleClose = () => {
        window.electronAPI.window.close(); return
    }

    const handleSettings = () => {
        app.screen.setCurrentView("settings"); return
    }

    const handleSearchInputSubmit: React.FormEventHandler<HTMLDivElement> = (event) => {
        console.log(event)
        /* app.screen.setSearch(event.)
        if (app.screen.currentView != "search") app.screen.setCurrentView("search")

        if (event.target.value == "") {
            app.screen.setCurrentView("home")
        } */
    }

    return (
        <Box sx={{ display: "flex", flexDirection: "row", height: "32px", zIndex: "999", backgroundColor: "var(--mui-palette-common-background)", WebkitAppRegion: "drag" }}>
            <Box sx={{ padding: "4px", marginLeft: "4px", display: "flex" }}>
                <Avatar variant="rounded" src={logoImage} sx={{ maxHeight: "24px",  aspectRatio: "1/1", width: "auto"}}/>
                <Typography fontSize="medium" variant="h6" sx={{ marginLeft: "8px" }}>wizeshi's Interfaceable Song Provider</Typography>
            </Box>

            <Box sx={{ position: "absolute", display: "flex", width: "100%", maxHeight: "inherit", justifyContent: "center", paddingTop: "4px" }}>
                <Box sx={{ WebkitAppRegion: "no-drag"  }}>
                    <IconButton size="small" onClick={handleHome} sx={{
                        width: "24px", height: "24px", marginRight: "8px", marginTop: "auto",
                        marginBottom: "auto", borderRadius: "6px", border: "2px solid rgba(255, 255, 255, 0.75)"
                    }}>
                        <HomeIcon fontSize="small"/>
                    </IconButton>
                    
                    <TextField 
                        onChange={handleSearchInputChange}
                        onKeyDown={handleSearchKeyDown}
                        sx={{ margin: "auto 0 auto 0" }} 
                        size="small" 
                        variant="outlined" 
                        placeholder="Search..."
                        slotProps={{
                            htmlInput: { sx: { padding: "0px 8px 0px 8px", fontSize: "16px" } },
                        }}
                    />
                </Box>
                
            </Box>

            <Box sx={{ marginLeft: "auto", marginRight: "4px" }}>
                <Box sx={{ WebkitAppRegion: "no-drag"  }}>
                    <IconButton onClick={handleSettings} size="small">
                        <SettingsIcon fontSize="small"/>
                    </IconButton>

                    <IconButton onClick={handleMinimize} size="small">
                        <MinimizeIcon fontSize="small"/>
                    </IconButton>
                
                    <IconButton onClick={handleMaximize} size="small">
                        <CheckBoxOutlineBlankIcon fontSize="small"/>
                    </IconButton>
                
                    <IconButton onClick={handleClose} size="small">
                        <CloseIcon fontSize="small"/>
                    </IconButton>
                </Box>
            </Box>
        </Box>
    )
}