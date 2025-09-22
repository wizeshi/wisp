import React, { useState } from "react"
import { useAppContext } from "../providers/AppContext"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"
import Link from "@mui/material/Link"

export const PlayerBar: React.FC = () => {
    const [playing, setPlaying] = useState(false)
    const { music } = useAppContext()
    
    return (
        <Box display="flex" sx={{ height: "15%", width: "calc(100% - 24px)", marginLeft: "12px", marginBottom: "12px", backgroundColor: "rgba(0, 0, 0, 0.5)",
                                position: "absolute", zIndex: "calc(var(--mui-zIndex-drawer) + 1)", bottom: "0", }}>
            
            <Box sx={{ padding: "12px", display: "flex" }}>
                <ButtonBase sx={{ marginTop: "auto", marginBottom: "auto" }}>
                    <Avatar variant="rounded" src="" sx={{ height: "64px", width: "64px" }}/>

                </ButtonBase>
    
                <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "auto", marginBottom: "auto" }}>
                    <Link href="" underline="hover" variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>gurt</Link>
                    <Link href="" underline="hover" variant="caption" fontWeight="200" sx={{ color: "var(--mui-palette-text-secondary)" }}>yo</Link>
                </Box>
    
            </Box>

        </Box>
    )
}