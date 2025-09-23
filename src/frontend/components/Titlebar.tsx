import IconButton from "@mui/material/IconButton"
import Typography from "@mui/material/Typography"
import Box from "@mui/material/Box"
import React, { useState } from "react"
import CloseIcon from '@mui/icons-material/Close';
import MinimizeIcon from '@mui/icons-material/Minimize';
import CheckBoxOutlineBlankIcon from '@mui/icons-material/CheckBoxOutlineBlank';
import SettingsIcon from '@mui/icons-material/Settings';
import SearchIcon from '@mui/icons-material/Search';
import HomeIcon from '@mui/icons-material/Home';
import TextField from "@mui/material/TextField";
import Input from "@mui/material/Input";
import { useAppContext } from "../providers/AppContext";

export const Titlebar: React.FC = () => {
    const [maximize, setMaximized] = useState<boolean>(false)
    const { app } = useAppContext()

    const handleHome = () => {
        app.screen.setCurrentView("home")
    }

    const handleMinimize = () => {

    }

    const handleMaximize = () => {
        
    }
    
    const handleClose = () => {

    }

    const handleSettings = () => {

    }

    return (
        <Box sx={{ display: "flex", flexDirection: "row", height: "32px", zIndex: "999", backgroundColor: "var(--mui-palette-common-background)" }}>
            <Box sx={{ padding: "4px", marginLeft: "4px" }}>
                {/* Add Icon */}
                <Typography fontSize="medium" variant="h6">wizeshi's Interfaceable Song Provider</Typography>
            </Box>

            <Box sx={{ position: "absolute", display: "flex", width: "100%", maxHeight: "inherit", justifyContent: "center", paddingTop: "4px" }}>
                <IconButton size="small" onClick={handleHome} sx={{
                    width: "24px", height: "24px", marginRight: "8px", marginTop: "auto",
                    marginBottom: "auto", borderRadius: "6px", border: "2px solid rgba(255, 255, 255, 0.75)"
                }}>
                    <HomeIcon fontSize="small"/>
                </IconButton>
                
                <TextField sx={{ margin: "auto 0 auto 0" }} size="small" variant="outlined" placeholder="Search..."
                    slotProps={{
                        htmlInput: { sx: { padding: "0px 8px 0px 8px", fontSize: "16px" } }
                    }}
                />
            </Box>

            <Box sx={{ marginLeft: "auto", marginRight: "4px" }}>
                <IconButton onChange={handleSettings} size="small">
                    <SettingsIcon fontSize="small"/>
                </IconButton>

                <IconButton onChange={handleMinimize} size="small">
                    <MinimizeIcon fontSize="small"/>
                </IconButton>
            
                <IconButton onChange={handleMaximize} size="small">
                    <CheckBoxOutlineBlankIcon fontSize="small"/>
                </IconButton>
            
                <IconButton onChange={handleClose} size="small">
                    <CloseIcon fontSize="small"/>
                </IconButton>
            </Box>
        </Box>
    )
}