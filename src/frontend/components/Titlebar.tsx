import IconButton from "@mui/material/IconButton"
import Typography from "@mui/material/Typography"
import Box from "@mui/material/Box"
import React, { useState } from "react"
import CloseIcon from '@mui/icons-material/Close';
import MinimizeIcon from '@mui/icons-material/Minimize';
import CheckBoxOutlineBlankIcon from '@mui/icons-material/CheckBoxOutlineBlank';
import SettingsIcon from '@mui/icons-material/Settings';

export const Titlebar: React.FC = () => {
    const [maximize, setMaximized] = useState<boolean>(false)

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