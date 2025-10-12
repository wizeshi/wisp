import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import React, { useEffect, useState } from "react"
import Divider from "@mui/material/Divider"
import Stack from '@mui/material/Stack';
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"
import Skeleton from "@mui/material/Skeleton";
import { SpotifyUserHome } from "../../backend/sources/Spotify";

export const HomeScreen: React.FC = () => {
    const [username, setUsername] = useState("(username)")
    const [loading, setLoading] = useState(true)
    const [userHome, setUserHome] = useState<SpotifyUserHome | null>(null)
    
    useEffect(() => {
        let cancelled = false;
        Promise.all([
            window.electronAPI.extractors.spotify.getUserInfo(),
            window.electronAPI.extractors.spotify.getUserHome()
        ]).then(([userInfo, userHome]) => {
            console.log(userInfo)
            console.log(userHome)
            if (!cancelled) {
                setUsername(userInfo.display_name)
                setUserHome(userHome)
                setLoading(false)
            }
        })

        return () => { cancelled = true; }
    }, [])

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, flexGrow: 1, flexDirection: "column", padding: "24px" }}>
            <Typography fontWeight="700" variant="h5">
                {loading ?
                    <Skeleton />
                :   <>welcome back, { username }</>
                }
            </Typography>

            <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>

            <Box display="flex" sx={{ flexGrow: 1, flexDirection: "column" }}>
                <Typography fontWeight="300" variant="h5" sx={{ marginLeft: "12px" }}>
                    jump back in 
                </Typography>

                <Stack direction="row" sx={{ overflowX: "scroll", marginTop: "8px", backgroundColor: "rgba(0, 0, 0, 0.25)", borderRadius: "8px", border: "1px solid rgba(255, 255, 255, 0.15)", padding: "12px" }}>
                    {userHome && userHome.savedPlaylists.map((playlist) => (
                        <CustomButton name={playlist.name} artist={playlist.owner.display_name} source=""/>
                    ))}
                </Stack>
            </Box>

            <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>
        </Box>
    )
}

const CustomButton: React.FC<{ name: string, artist: string, source: string }> = ({ name, artist, source }) => {
    
    return (
        <ButtonBase sx={{ minWidth: "240px", maxWidth: "240px", marginRight: "12px", backgroundColor: "rgba(0, 0, 0, 0.35)", padding: "12px", borderRadius: "12px", border: "1px solid rgba(255, 255, 255, 0.25)" }}>
            <Avatar variant="rounded" sx={{ height: "80px", width: "80px" }} src={ source }/>
                            
            <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "8px", marginBottom: "auto" }}>
                <Typography variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>{ name }</Typography>
                <Typography variant="body2" sx={{ color: "var(--mui-palette-text-secondary)" }}>{ artist }</Typography>
            </Box>
        </ButtonBase>
    )
}