import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import React, { useEffect, useState } from "react"
import Divider from "@mui/material/Divider"
import Stack from '@mui/material/Stack';
import Avatar from "@mui/material/Avatar"
import ButtonBase from "@mui/material/ButtonBase"
import Skeleton from "@mui/material/Skeleton";
import { GenericUserHome } from "../../common/types/SourcesTypes";
import { GenericAlbum, GenericSimpleArtist, GenericPlaylist, SidebarItemType, SongSources, GenericSong, GenericArtist } from "../../common/types/SongTypes";
import { useAppContext } from "../providers/AppContext";
import { getServiceIcon } from "../utils/Helpers";
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import IconButton from "@mui/material/IconButton";
import Link from "@mui/material/Link";
import { useContextMenuContext } from "../providers/ContextMenuProvider";
import { usePlayer } from "../providers/PlayerContext";

export const HomeScreen: React.FC = () => {
    const [username, setUsername] = useState("(username)")
    const [loading, setLoading] = useState(true)
    const [hoveredTrack, setHoveredTrack] = useState<GenericSong | null>(null)
    const [hoveredArtist, setHoveredArtist] = useState<GenericArtist | GenericSimpleArtist | null>(null)
    const [userHome, setUserHome] = useState<GenericUserHome | null>(null)
    const { openContextMenu } = useContextMenuContext()
    const { app } = useAppContext()
    const player = usePlayer()
    
    useEffect(() => {
        let cancelled = false;
        Promise.all([
            window.electronAPI.extractors.getUserInfo(),
            window.electronAPI.extractors.getUserHome()
        ]).then(([userInfo, userHome]) => {

            if (!cancelled) {
                setUsername(userInfo.displayName)
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

            <Box display="flex" flexDirection="column" sx={{ gap: "12px" }}>
                <CustomRow
                    rowType="Playlists"
                    rowContent={userHome ? userHome.savedPlaylists : []}
                    title="your saved playlists"
                />

                <CustomRow
                    rowType="Albums"
                    rowContent={userHome ? userHome.followedAlbums : []}
                    title="your followed albums"
                />

                <CustomRow
                    rowType="Artists"
                    rowContent={userHome ? userHome.followedArtists : []}
                    title="your followed artists"
                />
            </Box>

            <Box sx={{ marginTop: "12px"}}>
                <Typography variant="h5">this past month</Typography>

                <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>

                <Box display="flex" flexDirection="column" sx={{ gap: "12px" }}>
                    <Typography fontWeight="300" variant="h6" sx={{ marginLeft: "12px" }}>your top tracks</Typography>

                    {userHome && userHome.topTracks && userHome.topTracks.map((track, index) => {
                        const handleTrackClick = () => {
                            app.screen.setShownThing({ type: "Album", id: track.album.id })
                            app.screen.setCurrentView("listView");
                        }

                        const handleTrackDoubleClickOrPlay = () => {
                            player.setQueue(userHome.topTracks, index);
                        }

                        return (
                            <ButtonBase 
                                onClick={handleTrackClick}
                                onDoubleClick={handleTrackDoubleClickOrPlay}
                                onContextMenu={(e) => openContextMenu(e, track)}
                                onMouseEnter={() => setHoveredTrack(track)}
                                onMouseLeave={() => setHoveredTrack(null)}
                            sx={{
                                display: "grid",
                                gridTemplateColumns: "40px 40px 1fr 1fr 100px 40px",
                                alignItems: "center",
                                padding: "12px",
                                borderRadius: "12px",
                                border: "1px solid rgba(255, 255, 255, 0.25)",
                                gap: "12px",
                                backgroundColor: "rgba(0, 0, 0, 0.35)"
                            }}>
                                <Box sx={{ textAlign: "center" }}>
                                    {hoveredTrack && hoveredTrack === track ? (
                                        <IconButton onClick={(event) => {event.stopPropagation(); handleTrackDoubleClickOrPlay()}} size="small">
                                            <PlayArrowIcon />
                                        </IconButton>
                                    ) : (
                                        <Typography variant="body2" color="textSecondary">{index + 1}</Typography>
                                    )}
                                </Box>
                                <Box>
                                    <Avatar variant="rounded" src={track.thumbnailURL}/>
                                </Box>
                                <Box textAlign="left">
                                    <Typography>{track.title}</Typography>
                                    {track.artists.map((artist, index) => (
                                        <>
                                            <Typography key={index} variant="body2" color="textSecondary">{artist.name}</Typography>
                                            <Typography variant="body2" color="textSecondary">{index < track.artists.length - 1 ? ", " : ""}</Typography>
                                        </>
                                    ))}
                                </Box>
                                <Box textAlign="center">
                                    <Link variant="body2" color="textSecondary">{track.album.title}</Link>
                                </Box>
                                <Box textAlign="right">
                                    <Typography variant="body2" color="textSecondary">{track.durationFormatted}</Typography>
                                </Box>
                                <Box sx={{ display: "flex", justifyContent: "center" }}>
                                    { getServiceIcon(track.source, { width: "24px", height: "24px" }) }
                                </Box>
                            </ButtonBase>
                        )
                    })}

                </Box>

                <Divider variant="fullWidth" sx={{ marginTop: "12px", marginBottom: "12px" }}/>

                <Box display="flex" flexDirection="column" sx={{ gap: "12px" }}>
                    <Typography fontWeight="300" variant="h6" sx={{ marginLeft: "12px" }}>your top artists</Typography>


                    {userHome && userHome.topArtists && userHome.topArtists.map((artist, index) => {
                        const handleTrackClick = () => {
                            app.screen.setShownThing({ type: "Artist", id: artist.id })
                            app.screen.setCurrentView("artistView");
                        }

                        const handleTrackDoubleClickOrPlay = () => {
                            window.electronAPI.extractors.getArtistDetails(artist.id).then((fullArtist) => {
                                player.setQueue(fullArtist.topSongs, 0);
                            })
                        }

                        return (
                            <ButtonBase 
                                onClick={handleTrackClick}
                                onDoubleClick={handleTrackDoubleClickOrPlay}
                                onContextMenu={(e) => openContextMenu(e, artist)}
                                onMouseEnter={() => setHoveredArtist(artist)}
                                onMouseLeave={() => setHoveredArtist(null)}
                            sx={{
                                display: "grid",
                                gridTemplateColumns: "40px 40px 1fr 40px",
                                alignItems: "center",
                                padding: "12px",
                                borderRadius: "12px",
                                border: "1px solid rgba(255, 255, 255, 0.25)",
                                gap: "12px",
                                backgroundColor: "rgba(0, 0, 0, 0.35)"
                            }}>
                                <Box sx={{ textAlign: "center" }}>
                                    {hoveredArtist && hoveredArtist === artist ? (
                                        <IconButton onClick={(event) => {event.stopPropagation(); handleTrackDoubleClickOrPlay()}} size="small">
                                            <PlayArrowIcon />
                                        </IconButton>
                                    ) : (
                                        <Typography variant="body2" color="textSecondary">{index + 1}</Typography>
                                    )}
                                </Box>
                                <Box>
                                    <Avatar variant="rounded" src={artist.thumbnailURL}/>
                                </Box>
                                <Box textAlign="left">
                                    <Typography>{artist.name}</Typography>
                                </Box>

                                <Box sx={{ display: "flex", justifyContent: "center" }}>
                                    { getServiceIcon(artist.source, { width: "24px", height: "24px" }) }
                                </Box>
                            </ButtonBase>
                        )
                    })}
                </Box>
            </Box>
        </Box>
    )
}

const CustomRow: React.FC<
    | { rowType: "Albums", rowContent: GenericAlbum[], title: string }
    | { rowType: "Artists", rowContent: GenericSimpleArtist[], title: string }
    | { rowType: "Playlists", rowContent: GenericPlaylist[], title: string }
> = ({ rowType, rowContent, title }) => {
    return (
        <Box display="flex" sx={{ flexGrow: 1, flexDirection: "column" }}>
            <Typography fontWeight="300" variant="h6" sx={{ marginLeft: "12px" }}>
                {title}
            </Typography>

            <Stack direction="row" sx={{ overflowX: "auto", marginTop: "8px", backgroundColor: "rgba(0, 0, 0, 0.25)", borderRadius: "8px", border: "1px solid rgba(255, 255, 255, 0.15)", padding: "12px" }}>
                {rowType === "Albums" && rowContent.map((album, index) => (
                    <CustomButton 
                        key={index}
                        name={album.title} 
                        artist={album.artists.map((artist: { name: string }) => artist.name).join(", ")} 
                        type="Album"
                        id={album.id}
                        source={album.source}
                        thumbnailURL={album.thumbnailURL}
                        item={album}
                    />
                ))}
                {rowType === "Artists" && rowContent.map((artist, index) => (
                    <CustomButton 
                        key={index}
                        name={artist.name} 
                        artist="Artist" 
                        type="Artist"
                        id={artist.id}
                        source={artist.source}
                        thumbnailURL={artist.thumbnailURL}
                        item={artist}
                    />
                ))}
                {rowType === "Playlists" && rowContent.map((playlist, index) => (
                    <CustomButton 
                        key={index}
                        name={playlist.title} 
                        artist={playlist.author.displayName} 
                        type="Playlist"
                        id={playlist.id}
                        source={playlist.source}
                        thumbnailURL={playlist.thumbnailURL}
                        item={playlist}
                    />
                ))}
            </Stack>
        </Box>
    )
}

const CustomButton: React.FC<{ 
    name: string, 
    artist: string, 
    type: SidebarItemType, 
    id: string, 
    source: SongSources, 
    thumbnailURL: string,
    item: GenericAlbum | GenericSimpleArtist | GenericPlaylist
}>
= ({ name, artist, type, id, source, thumbnailURL, item }) => {
    const { app } = useAppContext()
    const { openContextMenu } = useContextMenuContext()


    const handleClick = () => {
        app.screen.setShownThing({ type, id })
        if (type === "Playlist" || type === "Album" ) {
            app.screen.setCurrentView("listView")
        } else {
            app.screen.setCurrentView("artistView")
        }
    }

    return (
        <ButtonBase 
            onClick={handleClick} 
            onContextMenu={(e) => openContextMenu(e, item)}
            sx={{ justifyContent: "left", minWidth: "240px", maxWidth: "240px", marginRight: "12px", backgroundColor: "rgba(0, 0, 0, 0.35)", padding: "12px", borderRadius: "12px", border: "1px solid rgba(255, 255, 255, 0.25)" }}>
            <Avatar variant="rounded" sx={{ height: "80px", width: "80px" }} src={thumbnailURL} />
                            
            <Box display="flex" sx={{ textAlign: "left", flexDirection: "column", paddingLeft: "16px", marginTop: "8px", marginBottom: "auto" }}>
                <Typography variant="body1" sx={{ color: "var(--mui-palette-text-primary)" }}>{ name }</Typography>
                <Typography variant="body2" sx={{ color: "var(--mui-palette-text-secondary)" }}>{ artist }</Typography>
            </Box>
        </ButtonBase>
    )
}