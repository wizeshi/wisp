import React from "react"
import ButtonBase from "@mui/material/ButtonBase"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Divider from "@mui/material/Divider"
import Avatar from "@mui/material/Avatar"
import Link from "@mui/material/Link"
import ExplicitIcon from "@mui/icons-material/Explicit"
import { DotRowSeparator } from "./ListScreen"
import List from "@mui/material/List"
import ListItemButton from "@mui/material/ListItemButton"
import { Album, Artist, BaseSongList, Playlist, Song, Sources } from "../utils/types"
import { getListType, getServiceIcon } from "../utils/helpers"


export const SearchScreen: React.FC<{ searchQuery: string }> = ({ searchQuery }) => {
    const artistTest1 = new Artist("Sia", "")
    const artistTest2 = new Artist("Diplo", "")
    const artistTest3 = new Artist("Labirinth", "")
    const artistTest4 = new Artist("LSD", "")
    const songTest = new Song("Genius", [ artistTest1, artistTest2, artistTest3, artistTest4 ], true, 213, "spotify", "", "")

    const mainResult: Song | Playlist | Album | Artist = new Song("Incredible", [artistTest1, artistTest2], true, 134, "spotify", "", "")
    
    const songsToDisplay = [ 
        songTest,
        songTest,
        songTest,
        songTest,
        songTest,
        songTest,
    ]

    return (
        <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, maxHeight: "inherit", flexGrow: 1, flexDirection: "column", padding: "24px" }}>
            <Typography variant="h6"> Search Results | { searchQuery }</Typography>

            <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />

            <Box display="flex" flexDirection="row">
                <Box sx={{ width: "20%" }}>
                    <Typography variant="h6">Best Match</Typography>

                    <ButtonBase sx={{ display:"flex", flexDirection: "column", justifyContent: "flex-start",
                    width: "100%", aspectRatio: "1 / 1.2", padding: "12px", backgroundColor: "rgba(0, 0, 0, 0.35)",
                    marginTop: "12px", border: "1px solid rgba(255, 255, 255, 0.1)", borderRadius: "12px" }}>
                        <Avatar variant="rounded" sx={{ width: "95%", aspectRatio: "1 / 1", height: "auto" }}/>

                        <Box display="flex" flexDirection="row" sx={{ alignSelf: "flex-start", width: "stretch" }}>
                            <Link href="" variant="h4" color="textPrimary" underline="hover" 
                            sx={{ padding: "8px 8px 0 8px", overflow: "hidden", whiteSpace: "nowrap",
                            }} textOverflow="ellipsis"> { mainResult.title } </Link>

                            {mainResult.explicit && 
                                <ExplicitIcon color="disabled"
                                sx={{ position: "relative", width: "36px", height: "auto", aspectRatio: "1 /1", top: "4px" }}/>
                            }
                        </Box>

                        <Box display="flex" flexDirection="row" sx={{ alignSelf: "flex-start", margin: "auto 0 auto 0", width: "stretch" }}>
                            {mainResult.artists.map((artist, index) => (
                                <React.Fragment>
                                    <Link href="" variant="h5" color="textSecondary" underline="hover" textOverflow="ellipsis"
                                    sx={{ padding: "0px 8px 8px 8px", alignSelf: "flex-start", overflow: "hidden" }}> { artist.name } </Link>
                                    {index < mainResult.artists.length - 1 && <Typography variant="h5" color="textSecondary">,&nbsp;</Typography>}
                                </React.Fragment>
                            ))}


                            {(mainResult instanceof BaseSongList) && (
                                <React.Fragment>
                                    <DotRowSeparator sx={{ paddingLeft: "0px" }}/>
                                    <Typography variant="h6"> { getListType(mainResult) } </Typography>
                                </React.Fragment>
                            )}
                        </Box>
                        
                    </ButtonBase>
                </Box>

                <Divider orientation="vertical" sx={{ marginLeft: "12px", marginRight: "12px"}}/>

                <Box display="flex" flexDirection="column" flexGrow={1}>
                    <Typography variant="h6">Songs</Typography>

                    <List
                    sx={{ marginTop: "8px", borderRadius: "12px", border: "1px solid rgba(255, 255, 255, 0.15)" }}>
                        {songsToDisplay.map((song, index) => (
                          <ListItemButton
                            onClick={() => { console.log("clicked listitem")} }
                            sx={{
                              display: "grid",
                              gridTemplateColumns: "0.09fr 2fr 0.1fr 0.1fr",
                              alignItems: "center",
                              marginBottom: "8px",
                              padding: "8px 16px",
                            }}
                          >
                            <Avatar variant="rounded" src="" sx={{ width: "40px", height: "40px" }} />
                            <Box>
                                <Typography variant="body1">{song.title}</Typography>
                                <Box display="flex" flexDirection="row">
                                    {song.explicit && (
                                        <ExplicitIcon color="disabled" />
                                    )}
                                    {song.artists.map((artist, index) => (
                                        <React.Fragment key={index}>
                                            <Link href="#" variant="body2" color="textSecondary" underline="hover"
                                            sx={{ margin: "auto 0px auto 2px" }}>
                                                {artist.name}
                                            </Link>
                                            {index < song.artists.length - 1 && <Typography variant="body2" color="textSecondary">,&nbsp;</Typography>}
                                        </React.Fragment>
                                    ))}
                                </Box>
                            </Box>
                            <Typography variant="body2" sx={{ textAlign: "right" }}>{song.durationFormatted}</Typography>
                            <Box display="flex" justifyContent="center">
                                {getServiceIcon(song.source)}
                            </Box>
                          </ListItemButton>  
                        ))}
                    </List>
                </Box>
            </Box>
        </Box>
    )
}