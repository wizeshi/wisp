import React, { useEffect, useState } from "react"
import { useAppContext } from "../providers/AppContext"
import { usePlayer } from "../providers/PlayerContext"
import { GenericAlbum, GenericPlaylist, GenericSong, PlaylistItem } from "../../common/types/SongTypes"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import List from "@mui/material/List"
import ListItem from "@mui/material/ListItem"
import ListItemButton from "@mui/material/ListItemButton"
import Link from "@mui/material/Link"
import ExplicitIcon from '@mui/icons-material/Explicit';
import IconButton from "@mui/material/IconButton"
import PlayArrow from "@mui/icons-material/PlayArrow"
import Fab from "@mui/material/Fab"
import Button from "@mui/material/Button"
import Menu from "@mui/material/Menu"
import MenuItem from "@mui/material/MenuItem"
import Dialog from "@mui/material/Dialog"
import DialogTitle from "@mui/material/DialogTitle"
import DialogContent from "@mui/material/DialogContent"
import DialogContentText from "@mui/material/DialogContentText"
import DialogActions from "@mui/material/DialogActions"
import AddIcon from '@mui/icons-material/Add';
import AudioFileIcon from '@mui/icons-material/AudioFile';
import SearchIcon from '@mui/icons-material/Search';
import WarningIcon from '@mui/icons-material/Warning';
import { useSettings } from "../hooks/useSettings"
import Skeleton from "@mui/material/Skeleton"
import { DotRowSeparator } from "../components/DotRowSeparator"
import { getServiceIcon, isAlbum, isPlaylist } from "../utils/Helpers"
import { useContextMenuContext } from "../providers/ContextMenuProvider"

export const ListScreen: React.FC = () => {
    const { app } = useAppContext()
    const player = usePlayer()
    const { openContextMenu } = useContextMenuContext()
    // Remove global overIndex, use local hover state in each row component

    // SongRow component for each song row
    const SongRow: React.FC<{
        song: GenericSong,
        index: number,
        list: GenericAlbum | GenericPlaylist,
        handlePlay: (song: GenericSong) => void,
        openContextMenu: (e: React.MouseEvent, song: GenericSong) => void,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        app: any
    }> = ({ song, index, list, handlePlay, openContextMenu, app }) => {
        const [isHovered, setIsHovered] = React.useState(false)
        const isAlbumList = isAlbum(list)
        return (
            <ListItem
                sx={{
                    paddingTop: "0",
                    paddingRight: "0px",
                    paddingLeft: "0px",
                    paddingBottom: "0px",
                    marginBottom: "8px",
                }}
            >
                <ListItemButton
                    onMouseOver={() => setIsHovered(true)}
                    onMouseLeave={() => setIsHovered(false)}
                    onDoubleClick={() => handlePlay(song)}
                    onContextMenu={(e) => openContextMenu(e, song)}
                    sx={[{
                        display: "grid",
                        gridTemplateColumns: "0.075fr 2fr 1fr 0.1fr",
                        alignItems: "center",
                        borderRadius: "12px",
                        zIndex: "5",
                    }, (player.getCurrentSong() && player.getCurrentSong().title == song.title) &&  {
                        backgroundColor: "rgba(255, 255, 255, 0.075)",
                        color: "#90ee90"
                    }, !isAlbumList && {
                        gridTemplateColumns: "0.075fr 3em 2fr 1.5fr 1fr 0.1fr",
                    }]}
                >
                    {isHovered ?
                        <IconButton onClick={() => handlePlay(song)} size="small" sx={{ left: "-12px" }}>
                            <PlayArrow />
                        </IconButton>
                    : <Typography variant="body2" sx={{ textAlign: "left" }} color="textSecondary">{index + 1}</Typography>
                    }

                    {!isAlbumList && (
                        <Avatar variant="rounded" src={song.thumbnailURL}/>
                    )}

                    <Box>
                        <Box display="flex" flexDirection="row">
                            <Typography variant="body1">{song.title}</Typography>
                            {song.explicit && <ExplicitIcon color="disabled" sx={{ paddingLeft: "8px" }} />}
                        </Box>
                        {song.artists.map((artist: { id: string; name: string }, artistIndex: number) => (
                            <React.Fragment key={artistIndex}>
                                <Link onClick={() => {
                                    app.screen.setShownThing({id: artist.id, type: "Artist"})
                                    app.screen.setCurrentView("artistView")
                                }} variant="body2" underline="hover" color="textSecondary" position="sticky" zIndex="10">{artist.name}</Link>
                                {artistIndex < song.artists.length - 1 && <Typography variant="caption" color="textSecondary">,&nbsp;</Typography>}
                            </React.Fragment>
                        ))}
                    </Box>
                    {!isAlbumList && (
                        <Box>
                            {song.album ? (
                                <Link onClick={() => {
                                    app.screen.setShownThing({id: song.album.id, type: "Album"})
                                    app.screen.setCurrentView("listView")
                                }} variant="body2" underline="hover" color="textSecondary">{song.album.title}</Link>
                            ) : (
                                <Typography variant="body2" color="textSecondary">—</Typography>
                            )}
                        </Box>
                    )}
                    <Box>
                        <Typography variant="body2" sx={{ textAlign: "center" }}>{song.durationFormatted}</Typography>
                    </Box>
                    <Box display="flex" sx={{ justifyContent: "right" }}>
                        <Typography variant="body2" sx={{ textAlign: "right" }}>
                            { getServiceIcon(song.source, { width: "24px", height: "24px" }) }
                        </Typography>
                    </Box>
                </ListItemButton>
            </ListItem>
        )
    }
    const [list, setList] = useState<GenericAlbum | GenericPlaylist | undefined>(undefined)
    const [hoverOverHeader, setHoverOverHeader] = useState(false)
    const [artistImages, setArtistImages] = useState<string[]>([])
    const { settings, loading, updateSettings }= useSettings()
    const [addMenuAnchor, setAddMenuAnchor] = useState<null | HTMLElement>(null)
    const addMenuOpen = Boolean(addMenuAnchor)
    const [refreshDialogOpen, setRefreshDialogOpen] = useState(false)

    useEffect(() => {
        const fetchLists = async () => {
            if (app.screen.shownThing.type == "Album") {
                const album = await window.electronAPI.extractors.getListDetails("Album", app.screen.shownThing.id)
                const artistImagesPromise = album.artists.map(async (artist: { id: string }) => {
                    const artistInfo = await window.electronAPI.extractors.getArtistInfo(artist.id)
                    return artistInfo.thumbnailURL
                })

                const artistImagesURL = await Promise.all(artistImagesPromise)
                setArtistImages(artistImagesURL)
                setList(album)
            }

            if (app.screen.shownThing.type == "Playlist") {
                const playlist = await window.electronAPI.extractors.getListDetails("Playlist", app.screen.shownThing.id)
                const userDetails = await window.electronAPI.extractors.getUserDetails(playlist.author.id)
                setArtistImages([userDetails.avatarURL || ''])
                setList(playlist)
            }
        }

        fetchLists()
    }, [app.screen.shownThing])

    const handlePlay = (song: GenericSong) => {
        const songInQueueIndex = player.queue.findIndex(queueSong => queueSong == song)
        if (songInQueueIndex != -1) {
            // Song already in queue, just play it
            player.goToIndex(songInQueueIndex)
        } else {
            switch(settings.listPlay) {
                case "Single": {
                    // Add only this song to queue and play it
                    player.setQueue([song], 0)
                    break
                }
                case "Multiple": {
                    // Add all songs from the list to queue
                    // Find and play the selected song (comparing by title and artists)
                    const songIndex = list.songs.findIndex((s: GenericSong) => 
                        s.title === song.title && 
                        s.artists.length === song.artists.length &&
                        s.artists.every((artist: { name: string }, i: number) => artist.name === song.artists[i].name)
                    )
                    player.setQueue(list.songs, songIndex !== -1 ? songIndex : 0)
                    break
                }
            }
        }
    }

    const handlePlayList = (list: GenericSong[]) => {
        player.setQueue(list, 0)
    }

    const handleAddMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
        setAddMenuAnchor(event.currentTarget)
    }

    const handleAddMenuClose = () => {
        setAddMenuAnchor(null)
    }

    const handleAddLocalFiles = async () => {
        handleAddMenuClose()
        
        // Open file picker
        const filePaths = await window.electronAPI.local.selectAudioFiles()
        
        if (filePaths.length === 0) return
        
        // Import the files
        const importedSongs: PlaylistItem[] = (await window.electronAPI.local.importAudioFiles(filePaths)).map((song) => {
            return {
                ...song,
                addedAt: new Date(),
                trackNumber: list.songs.length + 1 // Append to end of list
            }
        })
        
        if (!list || !list.songs || !isPlaylist(list)) return
        
        // Add imported songs to the current list
        const updatedSongs = [...list.songs, ...importedSongs]
        const updatedList = { ...list, songs: updatedSongs }
        setList(updatedList)
        
        // Save the updated playlist
        try {
            await window.electronAPI.local.savePlaylist(updatedList)
            console.log(`Added ${importedSongs.length} local songs to playlist and saved`)
        } catch (error) {
            console.error("Failed to save playlist:", error)
        }
    }

    const handleAddFromSearch = () => {
        handleAddMenuClose()
        // TODO: Open search dialog to add songs from Spotify/YouTube
        console.log("Add from search - to be implemented")
    }

    const handleAddFromLibrary = () => {
        handleAddMenuClose()
        // TODO: Open library browser to add existing songs
        console.log("Add from library - to be implemented")
    }

    const handleRefreshClick = () => {
        setRefreshDialogOpen(true)
    }

    const handleRefreshCancel = () => {
        setRefreshDialogOpen(false)
    }

    const handleRefreshConfirm = async () => {
        setRefreshDialogOpen(false)
        
        if (!list) return
        
        try {
            // Force refresh from API, removing local songs
            if (isPlaylist(list)) {
                const refreshedList = await window.electronAPI.extractors.forceRefreshList(
                    "Playlist", 
                    app.screen.shownThing.id,
                    list.source
                )
                setList(refreshedList)
                console.log("Refreshed playlist and reset local songs")
            } else if (isAlbum(list)) {
                const refreshedList = await window.electronAPI.extractors.forceRefreshList(
                    "Album", 
                    app.screen.shownThing.id,
                    list.source
                )
                setList(refreshedList)
                console.log("Refreshed album and reset local songs")
            }
        } catch (error) {
            console.error("Failed to refresh list:", error)
        }
    }

    let artistElement 

    if (list && isAlbum(list)) {
        artistElement = list.artists.map((artist: { name: string }, index: number) => (
            <React.Fragment key={index}>
                <Typography variant="h6" fontWeight={200}>
                    { artist.name }
                </Typography>
                { index < list.artists.length - 1 && <Typography variant="h6" fontWeight={200} sx={{ letterSpacing: "-6px" }}>, &nbsp; </Typography> }
            </React.Fragment>
        ))
    } else if (list && isPlaylist(list)) {
        artistElement = <Typography variant="h6" fontWeight={200}> { list.author.displayName } </Typography>
    }
    
    const explicit = true

    return (
        <React.Fragment>
        <Box display="flex" sx={{ 
            maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, 
            height: "calc(100% - 64px)", 
            flexGrow: 1, 
            flexDirection: "column", 
            padding: "24px", 
            overflow: "hidden",
            position: "relative"
        }}>
            {/* Blurred background */}
            {list && (
                <Box sx={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    right: 0,
                    height: "50%",
                    backgroundImage: `url(${list.thumbnailURL})`,
                    backgroundSize: "cover",
                    backgroundPosition: "center",
                    filter: "blur(2px)",
                    opacity: 0.65,
                    zIndex: 0,
                    '&::after': {
                        content: '""',
                        position: "absolute",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: "100%",
                        background: "linear-gradient(to bottom, transparent 0%, var(--mui-palette-background-default) 100%)",
                    }
                }}/>
            )}

            <Box display="flex" sx={{ padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", flexShrink: 0, position: "relative", zIndex: 1 }}
                onMouseEnter={() => setHoverOverHeader(true)}
                onMouseLeave={() => setHoverOverHeader(false)}>
                <Box sx={{ position: "relative" }}>
                    {!list ?
                        <Skeleton variant="rounded" sx={{ height: "200px", width: "200px"}}/>
                    : <Avatar variant="rounded" src={list.thumbnailURL} sx={{ height: "200px", width: "200px"}}/>}
                
                    <Box sx={{ position: "absolute", left: "4px", bottom: "4px", display: "flex", gap: "8px" }}>
                        {hoverOverHeader && (
                            <Fab color="success" onClick={() => {handlePlayList(list.songs); console.log(list.songs)}}>
                                <PlayArrow />    
                            </Fab>
                        )}
                    </Box>
                </Box>
                
                {/* Add Songs Menu */}
                <Menu
                    anchorEl={addMenuAnchor}
                    open={addMenuOpen}
                    onClose={handleAddMenuClose}
                    anchorOrigin={{
                        vertical: 'bottom',
                        horizontal: 'left',
                    }}
                    transformOrigin={{
                        vertical: 'top',
                        horizontal: 'left',
                    }}
                >
                    <MenuItem onClick={handleAddLocalFiles}>
                        <AudioFileIcon sx={{ mr: 1 }} />
                        Add Local Files
                    </MenuItem>
                    <MenuItem onClick={handleAddFromSearch}>
                        <SearchIcon sx={{ mr: 1 }} />
                        Search & Add
                    </MenuItem>
                    <MenuItem onClick={handleAddFromLibrary}>
                        {getServiceIcon('spotify', { width: '24px', height: '24px', marginRight: '8px' })}
                        Add from Library
                    </MenuItem>
                </Menu>
                
                <Box display="flex" sx={{ width: "100%", flexDirection: "row", paddingLeft: "18px", marginTop: "auto", position: "relative" }}>
                    <Box>
                        <Box display="flex" flexDirection="row">
                            <Typography variant="h4" fontWeight={900} sx={{ textWrap: "nowrap" }}>
                                {!list ?
                                <Skeleton />
                                : list.title }
                            </Typography>
                            
                            {!list ?
                                <Skeleton />
                            : ((isAlbum(list)) && explicit) &&
                                <ExplicitIcon sx={{ marginTop: "auto", marginBottom: "auto", paddingLeft: "12px" }} color="disabled"/>
                            }
                            
                        </Box>
                        
                        <Box display="flex" sx={{ flexDirection: "row", paddingLeft: "12px" }}>
                            <Box display="flex" sx={{ gap: "8px"}}>
                                {artistImages && artistImages.map((url) => (
                                    <Avatar variant="rounded" src={url} 
                                    sx={{ margin: "auto 0 auto 0", height: "24px", width: "24px"}}/>
                                ))}
                            </Box>

                            <Box display="flex" sx={{ marginLeft: "12px" }}>
                                { artistElement }
                            </Box>

                            {!list ?
                                <Skeleton />
                            : (isAlbum(list)) && (
                                <React.Fragment>
                                    <DotRowSeparator />
                                    <Typography variant="h6" fontWeight={200} color="textSecondary"> { list.releaseDate.getFullYear() } </Typography>
                                </React.Fragment>
                            )}

                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { !list ?
                                    <Skeleton />
                                : (list.songs.length > 1) ? `${list.songs.length} songs` : `${list.songs.length} song`}
                            </Typography>
                            <DotRowSeparator />
                            <Typography variant="h6" fontWeight={200}
                                sx={{ color: "var(--mui-palette-text-secondary)" }}>
                                { !list ? <Skeleton /> : list.durationFormatted }
                            </Typography>               
                        </Box>
                    </Box>
                    
                    <Box display="flex" sx={{  marginLeft: "auto", marginTop: "auto", gap: "8px", alignItems: "center" }}>
                        {/* Show buttons for playlists, or albums with local songs */}
                        {list && (isPlaylist(list) || (isAlbum(list) && list.songs.some(song => song.source === 'local'))) && (
                            <>
                                <Button 
                                    variant="outlined" 
                                    size="small"
                                    startIcon={<AddIcon />}
                                    onClick={handleAddMenuOpen}
                                >
                                    Add Songs
                                </Button>
                                <Button 
                                    variant="outlined" 
                                    size="small"
                                    onClick={handleRefreshClick}
                                >
                                    Refresh & Reset
                                </Button>
                            </>
                        )}
                        
                        {/* Show label for albums without local songs */}
                        <Box display="flex">
                            {!list ?
                                <Skeleton />
                            : (isAlbum(list) && !list.songs.some(song => song.source === 'local')) && (
                                <Typography variant="caption" color="textSecondary" sx={{ textAlign: "right" }}> { list.label } </Typography>
                            )}
                        </Box>
                    </Box>
                </Box>
            </Box>
            <Box display="flex" sx={{ flexDirection:"column", marginTop: "16px", padding: "12px", border: "1px solid rgba(255, 255, 255, 0.15)", borderRadius: "12px", backgroundColor: "rgba(0, 0, 0, 0.25)", minHeight: 0, overflow: "hidden", position: "relative", zIndex: 1 }}>
                <Box display="grid" sx={{ 
                    gridTemplateColumns: list && !(isAlbum(list)) ? "0.075fr 3em 2fr 1.5fr 1fr 0.1fr" : "0.075fr 2fr 1fr 0.1fr", 
                    paddingLeft: "16px", 
                    paddingRight: "16px", 
                    flexShrink: 0 
                }}>
                    <Typography color="textSecondary">#</Typography>
                    {list && !(isAlbum(list)) && <Box />}
                    <Typography color="textSecondary">Title</Typography>
                    {list && !(isAlbum(list)) && <Typography color="textSecondary">Album</Typography>}
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Duration</Typography>
                    <Typography sx={{ textAlign: "right" }} color="textSecondary">Source</Typography>
                </Box>
                
                <List sx={{ overflowY: "auto", minHeight: 0 }}>
                    {!list ?

                        (Array.from({ length: 10 }, (_, index) => (
                            <ListItem
                                key={index}
                                sx={{
                                    paddingTop: "0",
                                    paddingRight: "0px",
                                    paddingLeft: "0px",
                                    paddingBottom: "0px",
                                    marginBottom: "8px",
                            }}
                            >

                            </ListItem>
                        )))
                    : list.songs.map((song: GenericSong, index: number) => (
                        <SongRow
                            key={index}
                            song={song}
                            index={index}
                            list={list}
                            handlePlay={handlePlay}
                            openContextMenu={openContextMenu}
                            app={app}
                        />
                    ))}
                </List>
            </Box>      
        </Box>

        {/* Refresh Confirmation Dialog */}
        <Dialog
            open={refreshDialogOpen}
            onClose={handleRefreshCancel}
            maxWidth="sm"
            fullWidth
        >
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <WarningIcon color="warning" />
                Refresh & Reset {list && (isPlaylist(list) ? 'Playlist' : 'Album')}?
            </DialogTitle>
            <DialogContent>
                <DialogContentText>
                    This will refresh the {list && (isPlaylist(list) ? 'playlist' : 'album')} from {list?.source} and remove all content not native to that source.
                    <br /><br />
                    <strong>All local songs and other added content will be permanently removed.</strong>
                    <br /><br />
                    Are you sure you want to continue?
                </DialogContentText>
            </DialogContent>
            <DialogActions>
                <Button onClick={handleRefreshCancel} color="inherit">
                    Cancel
                </Button>
                <Button onClick={handleRefreshConfirm} color="warning" variant="contained" autoFocus>
                    Refresh & Reset
                </Button>
            </DialogActions>
        </Dialog>
        </React.Fragment>
    )
}