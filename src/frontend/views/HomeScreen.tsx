import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import React from "react"
import { theme } from "../utils/theme"
import Divider from "@mui/material/Divider"
import Grid from "@mui/material/Grid"
import Card from "@mui/material/Card"
import Button from "@mui/material/Button"
import Stack from '@mui/material/Stack';
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"

export const HomeScreen: React.FC = () => {
    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, flexGrow: 1, flexDirection: "column", padding: "24px" }}>
            <Typography fontWeight="700" variant="h5">welcome back, (username)</Typography>

            <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>

            <Box display="flex" sx={{ flexGrow: 1, flexDirection: "column" }}>
                <Typography fontWeight="300" variant="h5" sx={{ marginLeft: "12px" }}>
                    jump back in 
                </Typography>

                <Stack direction="row" sx={{ overflowX: "scroll", marginTop: "8px", backgroundColor: "rgba(0, 0, 0, 0.25)", borderRadius: "8px", border: "1px solid rgba(255, 255, 255, 0.15)", padding: "12px" }}>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                    <CustomButton name="Playlist 1" artist="Artist 1" source=""/>
                </Stack>
            </Box>

            <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>
        </Box>
    )
}

const CustomButton: React.FC<{ name: string, artist: string, source: string }> = ({ name, artist, source }) => {
    
    return (
        <ButtonBase sx={{ marginRight: "12px", backgroundColor: "rgba(0, 0, 0, 0.35)", padding: "12px", borderRadius: "12px", border: "1px solid rgba(255, 255, 255, 0.25)" }}>
            <Avatar variant="rounded" sx={{ height: "80px", width: "80px" }} src={ source }/>
                            
            <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "8px", marginBottom: "auto" }}>
                <Typography variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>{ name }</Typography>
                <Typography variant="body2" sx={{ color: "var(--mui-palette-text-secondary)" }}>{ artist }</Typography>
            </Box>
        </ButtonBase>
    )
}