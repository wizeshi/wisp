import React, { useEffect, useState, useRef, useCallback, useMemo } from "react"
import { FixedSizeList } from "react-window"
import { useAppContext } from "../providers/AppContext"
import { usePlayer } from "../providers/PlayerContext"
import { GenericSong, PlaylistItem } from "../../common/types/SongTypes"
import Box from "@mui/material/Box"
import Typography from "@mui/material/Typography"
import Avatar from "@mui/material/Avatar"
import ListItem from "@mui/material/ListItem"
import ListItemButton from "@mui/material/ListItemButton"
import Link from "@mui/material/Link"
import ExplicitIcon from '@mui/icons-material/Explicit';
import IconButton from "@mui/material/IconButton"
import PlayArrow from "@mui/icons-material/PlayArrow"
import Fab from "@mui/material/Fab"
import FavoriteIcon from '@mui/icons-material/Favorite';
import CircularProgress from "@mui/material/CircularProgress"
import { useSettings } from "../hooks/useSettings"
import Skeleton from "@mui/material/Skeleton"
import { DotRowSeparator } from "../components/DotRowSeparator"
import { getServiceIcon } from "../utils/Helpers"
import { useContextMenuContext } from "../providers/ContextMenuProvider"
import { secondsToSecMinHour } from "../utils/Utils"

export const LikesView: React.FC = () => {
    const { app } = useAppContext()
    const player = usePlayer()
    const { openContextMenu } = useContextMenuContext()
    const [likedSongs, setLikedSongs] = useState<PlaylistItem[]>([])
    const [loading, setLoading] = useState(true)
    const [loadingMore, setLoadingMore] = useState(false)
    const [hasMore, setHasMore] = useState(true)
    const [total, setTotal] = useState(0)
    const [hoverOverHeader, setHoverOverHeader] = useState(false)
    const [hoveredIndex, setHoveredIndex] = useState<number | null>(null)
    const { settings } = useSettings()
    const listRef = useRef<FixedSizeList>(null)
    const containerRef = useRef<HTMLDivElement>(null)
    const currentOffset = useRef(0)
    const [listHeight, setListHeight] = useState(600)

    // Batch state updates for performance
    const fetchLikedSongs = useCallback(async (offset = 0, append = false) => {
        try {
            if (!append) setLoading(true)
            else setLoadingMore(true)

            const likedPlaylist = await window.electronAPI.extractors.getUserLikes("spotify", offset)
            const newSongs = likedPlaylist.songs || []

            // Batch state updates
            setLikedSongs(prev => append ? [...prev, ...newSongs] : newSongs)
            setHasMore(likedPlaylist.hasMore ?? false)
            setTotal(likedPlaylist.total ?? newSongs.length)
            currentOffset.current = offset + newSongs.length
            // Remove or guard console.log in production
            // console.log(`Loaded ${newSongs.length} songs (offset: ${offset}, total: ${likedPlaylist.total}, hasMore: ${likedPlaylist.hasMore})`)
        } catch (error) {
            console.error("Failed to fetch liked songs:", error)
        } finally {
            setLoading(false)
            setLoadingMore(false)
        }
    }, [])

    useEffect(() => {
        fetchLikedSongs(0, false)
    }, [fetchLikedSongs])

    // Calculate list height based on container size
    // Debounce updateHeight for resize
    useEffect(() => {
        let timeout: NodeJS.Timeout | null = null
        const updateHeight = () => {
            if (timeout) clearTimeout(timeout)
            timeout = setTimeout(() => {
                if (containerRef.current) {
                    const rect = containerRef.current.getBoundingClientRect()
                    setListHeight(window.innerHeight - rect.top - 40)
                }
            }, 100)
        }
        updateHeight()
        window.addEventListener('resize', updateHeight)
        return () => {
            window.removeEventListener('resize', updateHeight)
            if (timeout) clearTimeout(timeout)
        }
    }, [])

    // Infinite scroll handler for react-window
    // Memoize handleScroll with minimal dependencies
    const handleScroll = useCallback(({ scrollOffset, scrollUpdateWasRequested }: { scrollOffset: number; scrollUpdateWasRequested: boolean }) => {
        if (scrollUpdateWasRequested || loadingMore || !hasMore) return
        const totalHeight = likedSongs.length * 56
        const viewportHeight = listHeight
        const scrollBottom = totalHeight - scrollOffset - viewportHeight
        if (scrollBottom < 300) {
            fetchLikedSongs(currentOffset.current, true)
        }
    }, [loadingMore, hasMore, fetchLikedSongs, listHeight, likedSongs.length])

    // Define handlePlay before Row component
    const handlePlay = useCallback((song: GenericSong, startIndex: number) => {
        const songInQueueIndex = player.queue.findIndex(queueSong => queueSong.id === song.id)
        if (songInQueueIndex !== -1) {
            // Song already in queue, just play it
            player.goToIndex(songInQueueIndex)
        } else {
            if (!settings || !settings.listPlay) {
                // Fallback to single if settings or listPlay is not set
                player.setQueue([song], 0)
                return;
            }
            switch(settings.listPlay) {
                case "Single": {
                    // Add only this song to queue and play it
                    player.setQueue([song], 0)
                    break
                }
                case "Multiple": {
                    // Add all liked songs to queue and play from the selected one
                    player.setQueue(likedSongs, startIndex)
                    break
                }
                default: {
                    // Fallback to single if listPlay is not set
                    player.setQueue([song], 0)
                }
            }
        }
    }, [player, settings, likedSongs])

    // Memoized Row component for react-window
    // Extract as a stable component to prevent recreation
    const Row = useCallback(({ index, style }: { index: number; style: React.CSSProperties }) => {
        if (loading) {
            const isLast = index === likedSongs.length - 1;
            return (
                <div style={{ ...style, height: 64, marginBottom: isLast ? 0 : 8 }}>
                    <ListItem
                        sx={{
                            padding: 0,
                            margin: 0,
                            height: 56,
                            minHeight: 56,
                        }}
                    >
                        <Skeleton variant="rectangular" width="100%" height={48} sx={{ borderRadius: "12px" }} />
                    </ListItem>
                </div>
            )
        }

        const song = likedSongs[index]
        if (!song) return null

        const isHovered = hoveredIndex === index
        const isCurrentSong = player.getCurrentSong()?.id === song.id

        const isLast = index === likedSongs.length - 1;
        return (
            <div style={{ ...style, height: 64, marginBottom: isLast ? 0 : 8 }}>
                <ListItem
                    sx={{
                        padding: 0,
                        margin: 0,
                        height: 56,
                        minHeight: 56,
                    }}
                >
                    <ListItemButton
                        onMouseOver={() => setHoveredIndex(index)}
                        onMouseLeave={() => setHoveredIndex(null)}
                        onDoubleClick={() => handlePlay(song, index)}
                        onContextMenu={(e) => openContextMenu(e, song)}
                        sx={[{
                            display: "grid",
                            gridTemplateColumns: "0.075fr 3em 2fr 1.55fr 1.1fr 1fr 0.1fr",
                            alignItems: "center",
                            borderRadius: "12px",
                            zIndex: "5",
                            height: 56,
                            minHeight: 56,
                        }, isCurrentSong &&  {
                            backgroundColor: "rgba(255, 255, 255, 0.075)",
                            color: "#90ee90"
                        }]}
                    >
                        {isHovered ? (
                            <IconButton onClick={() => handlePlay(song, index)} size="small" sx={{ left: "-12px" }}>
                                <PlayArrow />
                            </IconButton>
                        ) : (
                            <Typography variant="body2" sx={{ textAlign: "left" }} color="textSecondary">
                                {index + 1}
                            </Typography>
                        )}

                        <Avatar variant="rounded" src={song.thumbnailURL}/>

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
                                    }} variant="body2" underline="hover" color="textSecondary" position="sticky" zIndex="10">
                                        {artist.name}
                                    </Link>
                                    {artistIndex < song.artists.length - 1 && <Typography variant="caption" color="textSecondary">,&nbsp;</Typography>}
                                </React.Fragment>
                            ))}
                        </Box>

                        <Box>
                            {song.album ? (
                                <Link onClick={() => {
                                    app.screen.setShownThing({id: song.album.id, type: "Album"})
                                    app.screen.setCurrentView("listView")
                                }} variant="body2" underline="hover" color="textSecondary">
                                    {song.album.title}
                                </Link>
                            ) : (
                                <Typography variant="body2" color="textSecondary">—</Typography>
                            )}
                        </Box>

                        <Box>
                            {song.addedAt && (
                                <Typography variant="body2" color="textSecondary">
                                    {song.addedAt.toDateString()}
                                </Typography>
                            )}
                        </Box>

                        <Box>
                            <Typography variant="body2" sx={{ textAlign: "center" }}>
                                {song.durationFormatted}
                            </Typography>
                        </Box>
                        
                        <Box display="flex" sx={{ justifyContent: "right" }}>
                            <Typography variant="body2" sx={{ textAlign: "right" }}>
                                {getServiceIcon(song.source, { width: "24px", height: "24px" })}
                            </Typography>
                        </Box>
                    </ListItemButton>
                </ListItem>
            </div>
        )
    }, [loading, likedSongs, hoveredIndex, player, openContextMenu, app, handlePlay])

    const handlePlayAll = useCallback(() => {
        if (likedSongs.length > 0) {
            player.setQueue(likedSongs, 0)
        }
    }, [likedSongs, player])

    // Calculate total duration
    const totalDuration = likedSongs.reduce((acc, song) => acc + (song.durationSecs || 0), 0)
    const durationFormatted = secondsToSecMinHour(totalDuration)

    // Memoize skeleton array for loading
    const skeletonArray = useMemo(() => Array.from({ length: 10 }), [])

    return (
        <Box display="flex" sx={{ 
            maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, 
            height: "calc(100% - 64px)", 
            flexGrow: 1, 
            flexDirection: "column", 
            padding: "24px", 
            overflow: "hidden",
            position: "relative"
        }}>
            {/* Header Card */}
            <Box display="flex" sx={{ 
                padding: "12px", 
                border: "1px solid rgba(255, 255, 255, 0.15)", 
                borderRadius: "12px", 
                backgroundColor: "rgba(0, 0, 0, 0.25)", 
                flexShrink: 0, 
                position: "relative", 
                zIndex: 1 
            }}
                onMouseEnter={() => setHoverOverHeader(true)}
                onMouseLeave={() => setHoverOverHeader(false)}>
                <Box sx={{ position: "relative" }}>
                    <Avatar 
                        variant="rounded" 
                        src="https://misc.scdn.co/liked-songs/liked-songs-300.png" 
                        sx={{ height: "200px", width: "200px" }}
                    />
                
                    <Box sx={{ position: "absolute", left: "4px", bottom: "4px", display: "flex", gap: "8px" }}>
                        {hoverOverHeader && likedSongs.length > 0 && (
                            <Fab color="success" onClick={handlePlayAll}>
                                <PlayArrow />    
                            </Fab>
                        )}
                    </Box>
                </Box>
                
                <Box display="flex" sx={{ width: "100%", flexDirection: "row", paddingLeft: "18px", marginTop: "auto", position: "relative" }}>
                    <Box>
                        <Box display="flex" flexDirection="row" alignItems="center" gap={1}>
                            <FavoriteIcon sx={{ color: "#1db954" }} />
                            <Typography variant="h4" fontWeight={900}>
                                Liked Songs
                            </Typography>
                        </Box>
                        
                        <Box display="flex" sx={{ flexDirection: "row", paddingLeft: "12px", marginTop: "8px" }}>
                            {loading ? (
                                <Skeleton width={200} />
                            ) : (
                                <>
                                    <Typography variant="h6" fontWeight={200} color="textSecondary">
                                        {total === 1 ? '1 song' : `${total} songs`}
                                    </Typography>
                                    {likedSongs.length > 0 && (
                                        <>
                                            <DotRowSeparator />
                                            <Typography variant="h6" fontWeight={200} color="textSecondary">
                                                {durationFormatted}
                                            </Typography>
                                        </>
                                    )}
                                </>
                            )}
                        </Box>
                    </Box>
                </Box>
            </Box>

            <Box 
                ref={containerRef}
                display="flex" 
                sx={{ 
                    flexDirection:"column", 
                    marginTop: "16px", 
                    padding: "12px", 
                    border: "1px solid rgba(255, 255, 255, 0.15)", 
                    borderRadius: "12px", 
                    backgroundColor: "rgba(0, 0, 0, 0.25)", 
                    minHeight: 0, 
                    overflow: "hidden", 
                    position: "relative", 
                    zIndex: 1 
                }}
            >
                <Box display="grid" sx={{ 
                    gridTemplateColumns: "0.075fr 3em 2fr 1.5fr 1fr 1fr 0.1fr", 
                    paddingLeft: "16px", 
                    paddingRight: "16px", 
                    flexShrink: 0 
                }}>
                    <Typography color="textSecondary">#</Typography>
                    <Box />
                    <Typography color="textSecondary">Title</Typography>
                    <Typography color="textSecondary">Album</Typography>
                    <Typography color="textSecondary">Added At</Typography>
                    <Typography sx={{ textAlign: "center" }} color="textSecondary">Duration</Typography>
                    <Typography sx={{ textAlign: "right" }} color="textSecondary">Source</Typography>
                </Box>
                
                {loading ? (
                    <Box sx={{ paddingTop: "8px" }}>
                        {skeletonArray.map((_, index) => (
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
                                <Skeleton variant="rectangular" width="100%" height={48} sx={{ borderRadius: "12px" }} />
                            </ListItem>
                        ))}
                    </Box>
                ) : likedSongs.length === 0 ? (
                    <Box display="flex" justifyContent="center" alignItems="center" sx={{ height: "200px" }}>
                        <Typography variant="h6" color="textSecondary">
                            No liked songs yet. Start liking songs to see them here!
                        </Typography>
                    </Box>
                ) : (
                    <Box sx={{ paddingTop: "8px" }}>
                        <FixedSizeList
                            ref={listRef}
                            height={listHeight}
                            itemCount={likedSongs.length + (loadingMore ? 1 : 0)}
                            itemSize={56}
                            width="100%"
                            onScroll={handleScroll}
                        >
                            {({ index, style }: { index: number; style: React.CSSProperties }) => {
                                if (index === likedSongs.length && loadingMore) {
                                    return (
                                        <div style={style}>
                                            <Box display="flex" justifyContent="center" padding={2}>
                                                <CircularProgress size={30} />
                                            </Box>
                                        </div>
                                    )
                                }
                                return <Row index={index} style={style} />
                            }}
                        </FixedSizeList>
                    </Box>
                )}
            </Box>      
        </Box>
    )
}