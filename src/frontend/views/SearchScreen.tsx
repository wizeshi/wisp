import React, { useEffect, useState } from "react"
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
import { Album, Artist, BaseSongList, Playlist, Song } from "../types/SongTypes"
import { getListType, getServiceIcon, spotifyTrackToSong } from "../utils/Helpers"
import Fab from "@mui/material/Fab"
import PlayArrow from "@mui/icons-material/PlayArrow"
import { useAppContext } from "../providers/AppContext"
import Stack from "@mui/material/Stack"
import { ItemTypes, SearchResults } from "@spotify/web-api-ts-sdk"
import { secondsToSecAndMin } from "../utils/Utils"

type playAreas = "MainResult" | "SuggestedArea" | "LowerFirstArea" | "LowerSecondArea" | "LowerThirdArea"

const convertThreeAreasToTypeArea = (index: number) => {
    switch (index) {
        case 1:
            return "LowerFirstArea"
        case 2:
            return "LowerSecondArea"
        case 3:
            return "LowerThirdArea"
    }
}

export const SearchScreen: React.FC<{ searchQuery: string }> = ({ searchQuery }) => {
    const [ playSongButtonShowing, setPlaySongButtonShowing ] = useState<Map<playAreas, Map<number, boolean>>>(new Map())
    const { music } = useAppContext()
    const [ searchResults, setSearchResults ] = useState<SearchResults<readonly ItemTypes[]>>(undefined)
    const [ debouncedQuery, setDebouncedQuery ] = useState(searchQuery)
    const [ loading, setLoading ] = useState(true)

    useEffect(() => {
        const handler = setTimeout(() => setDebouncedQuery(searchQuery), 500)
        return () => clearTimeout(handler)
    }, [searchQuery])

    useEffect(() => {
        if (!debouncedQuery) return;
        const fetchResults = async () => {
            setLoading(true)
            const results = await window.electronAPI.extractors.spotify.search(searchQuery)
            console.log(results)
            setSearchResults(results)
            setLoading(false)
        }
        fetchResults()
    }, [debouncedQuery])

    const isPlayButtonShowing = (area: playAreas, index: number) => {
        if (!playSongButtonShowing.get(area)) return false

        return (playSongButtonShowing.get(area).get(index) == true)
    }

    const setPlayButtonShowing = (area: playAreas, index: number) => {
        setPlaySongButtonShowing(new Map().set(area, new Map().set(index, true)))
    }

    const handlePlay = (song: Song) => {
        const songIndex = music.player.addSongToQueue(song)
        music.player.setSongIndex(songIndex)
        music.player.audioPlayer.seek(0)
    }

    const handleMouseEnterMainResult = () => {
        setPlayButtonShowing("MainResult", 1)
    }

    const handleMouseLeaveMainResult = () => {
        setPlayButtonShowing("MainResult", 0)
    }

    const handleMouseEnterSearchedSong = (searchedSongIndex: number) => {
        setPlayButtonShowing("SuggestedArea", searchedSongIndex)
    }

    const handleMouseLeaveSearchedSong = () => {
        setPlayButtonShowing("SuggestedArea", 0)
    }

    if (!loading && searchResults) {
        const mainResult = searchResults.tracks.items[0]

        const songsToDisplay = searchResults.tracks.items.slice(1, 9)

        return (
            <Box display="flex" sx={{ maxWidth: `calc(100% - calc(calc(7 * var(--mui-spacing, 8px)) + 1px))`, maxHeight: "inherit", flexGrow: 1, flexDirection: "column", padding: "24px" }}>
                <Typography variant="h6"> Search Results | { searchQuery }</Typography>

                <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }} />

                <Box display="grid" gridTemplateColumns="25% 1.5% 73.5%">
                    <Box sx={{ width: "100%" }}>
                        <Typography variant="h6">Best Match</Typography>

                        <Box sx={{ display:"flex", flexDirection: "column", justifyContent: "flex-start",
                            padding: "12px", backgroundColor: "rgba(0, 0, 0, 0.35)",
                            marginTop: "12px", border: "1px solid rgba(255, 255, 255, 0.1)", borderRadius: "12px",
                            position:"sticky", cursor: "pointer" }}
                        onMouseEnter={handleMouseEnterMainResult} onMouseLeave={handleMouseLeaveMainResult} onClick={() => {}}
                        >
                            <Avatar src={mainResult.album.images[0].url} variant="rounded" sx={{ width: "95%", aspectRatio: "1 / 1", height: "auto", margin: "0 auto 0 auto" }} />
                            
                            <Box>
                                <Box display="flex" flexDirection="row" sx={{ alignSelf: "flex-start", width: "stretch" }}>
                                    <Link href="" variant="h4" color="textPrimary" underline="hover" 
                                    sx={{ padding: "8px 8px 0 8px", overflow: "hidden", textWrap: "nowrap"
                                    }} textOverflow="ellipsis"> { mainResult.name } </Link>

                                </Box>
                                <Box display="flex" flexDirection="row" sx={{ alignSelf: "flex-start", margin: "auto 0 auto 0", width: "stretch", textOverflow: "ellipsis", overflowX: "hidden" }}>
                                    {mainResult.explicit && 
                                        <ExplicitIcon color="disabled"
                                        sx={{ position: "relative", width: "24px", height: "auto", aspectRatio: "1 /1", margin: "4px 0px auto 8px" }}/>
                                    }

                                    {mainResult.artists.map((artist, index) => (
                                        <React.Fragment>
                                            <Link href="" variant="h5" color="textSecondary" underline="hover" textOverflow="ellipsis"
                                            sx={{ padding: "0px 8px 8px 8px", alignSelf: "flex-start", textWrap: "nowrap" }}> { artist.name } </Link>
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
                            </Box>
                            
                            {isPlayButtonShowing("MainResult", 1) &&
                                <>
                                    <Box sx={{ position: "absolute", right: "12px", bottom: "12px" }}>
                                        <Fab size="medium" color="success" onClick={() => { handlePlay(spotifyTrackToSong(mainResult)) }}>
                                            <PlayArrow />
                                        </Fab>
                                    </Box>
                                </>
                            }
                            
                        </Box>
                    </Box>

                    <Divider orientation="vertical" sx={{ marginLeft: "12px", marginRight: "12px"}}/>

                    <Box display="flex" flexDirection="column" flexGrow={1}>
                        <Typography variant="h6">Songs</Typography>

                        <List
                        sx={{ marginTop: "8px", borderRadius: "12px", border: "1px solid rgba(255, 255, 255, 0.15)" }}>
                            {songsToDisplay.map((song, index) => (
                            <ListItemButton
                                onDoubleClick={() => { handlePlay(spotifyTrackToSong(song)) } }
                                sx={{
                                display: "grid",
                                gridTemplateColumns: "3em 70fr 1fr",
                                alignItems: "center",
                                padding: "8px 16px",
                                }}
                            >
                                <Box sx={{ width: "40px", height: "40px", display: "flex", position: "relative" }}
                                    onMouseEnter={() => handleMouseEnterSearchedSong(index + 1)}
                                    onMouseLeave={handleMouseLeaveSearchedSong}>
                                    <Avatar variant="rounded" src={song.album.images[0].url}
                                        sx={{ width: "40px", height: "40px" }}>
                                    </Avatar>
                                    {isPlayButtonShowing("SuggestedArea", index + 1) &&
                                        <>
                                            <ButtonBase sx={{ width: "inherit", height: "inherit", position: "absolute", top: "0px", left: "0px", borderRadius: "4px",
                                            backgroundColor: "rgba(0, 0, 0, 0.6)"}} 
                                            onClick={(event) => { 
                                                handlePlay(spotifyTrackToSong(song)); event.stopPropagation() 
                                            }}>
                                                <PlayArrow />
                                            </ButtonBase>
                                        </>
                                    }
                                </Box>
                                <Box>
                                    <Typography variant="body1">{song.name}</Typography>
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
                                <Box display="flex">
                                    <Typography variant="body2" sx={{ textAlign: "right", marginRight: "12px", alignSelf: "center" }}>{secondsToSecAndMin(song.duration_ms / 1000)}</Typography>
                                    <Box display="flex" justifyContent="center">
                                        {getServiceIcon("spotify")}
                                    </Box>
                                </Box>
                            </ListItemButton>  
                            ))}
                        </List>
                    </Box>
                </Box>

                <Divider variant="fullWidth" sx={{ margin: "12px 0 12px 0" }}/>

                <Box display="grid" gridTemplateColumns="32.3% 1.5% 32.3% 1.5% 32.3%">
                    {['Albums', 'Playlists', 'Artists'].map((item, index, array) => {
                        // eslint-disable-next-line @typescript-eslint/no-explicit-any
                        let listItems: any[] = []

                        switch (item) {
                            case "Albums":
                                listItems = searchResults.albums.items.map((oldAlbum) => {
                                    const tempArtists = oldAlbum.artists.map((oldArtists) => {
                                        return new Artist(oldArtists.name, "")
                                    })

                                    return new Album(oldAlbum.name, tempArtists, "", new Date(oldAlbum.release_date), true, [], oldAlbum.images[0].url)
                                })
                                break
                            case "Playlists": {
                                searchResults.playlists.items.forEach((playlist, index, array) => {
                                    if (!playlist || playlist == null) { return }
                                    else listItems.push(new Playlist(playlist.name, playlist.owner.display_name, [], playlist.images[0].url))
                                })

                                break
                            }
                            case "Artists":
                                listItems = searchResults.artists.items.map((oldArtists) => {
                                    return new Artist(oldArtists.name, oldArtists.images.length != 0 ? oldArtists.images[0].url : "")
                                })

                                break
                        }

                        return (
                        <React.Fragment>
                            <ListSlider title={item} listItems={listItems}
                            isButtonShowing={(number: number) => isPlayButtonShowing(convertThreeAreasToTypeArea(index + 1), number)}
                            setButtonShowing={(number: number) => setPlayButtonShowing(convertThreeAreasToTypeArea(index + 1), number)}/>

                            {(index < array.length -1) &&
                                <Divider orientation="vertical" variant="fullWidth" sx={{ margin: "0 12px 0 12px" }}/> }
                        </React.Fragment> )
                    })}
                </Box>
            </Box>
        )
    }
}

const ListSlider: 
    React.FC<{ 
        title: string, 
        listItems: Array<Album> | Array<Artist> | Array<Playlist>, 
        isButtonShowing: (index: number) => boolean, 
        setButtonShowing: (index: number) => void
    }> 
= ({ title, listItems, isButtonShowing, setButtonShowing }) => {
    const handleMouseEnter = (index: number) => {
        setButtonShowing(index)
    }

    const handleMouseLeave = () => {
        setButtonShowing(0)
    }


    return (
        <Box sx={{ maxWidth: "inherit" }}>
            <Typography variant="h6">{ title }</Typography>

                <Stack direction="row" sx={{
                    overflowX: "scroll"
                }}>
                    {listItems.map((listItem, index) => {
                        let itemName
                        let itemArtists
                        let itemExplicit
                        const itemIcon = listItem.thumbnailURL
                        if (listItem instanceof Album) {
                            itemName = listItem.title 
                            itemArtists = listItem.artists
                            itemExplicit = listItem.explicit 
                        }
                        if (listItem instanceof Artist) {
                            itemName = listItem.name
                        }
                        if (listItem instanceof Playlist) {
                            itemName = listItem.title
                            itemArtists = [ { name: listItem.author, thumbnailURL: "" } ]
                        }


                        return (
                            <ButtonWrapper>
                                <Box display="flex" sx={{ position: "relative", maxHeight: "fit-content", overflowX: "hidden" }}
                                onMouseEnter={() => handleMouseEnter(index + 1)}
                                onMouseLeave={handleMouseLeave}>
                                    <Avatar variant="rounded" sx={{ aspectRatio: "1/1", height: "128px", width: "auto" }} src={itemIcon}/>

                                    <Box display="flex" flexDirection="column" sx={{ margin: "auto 0px 0px 12px" }}>
                                        <Box>
                                            <Typography variant="h5">{ itemName }</Typography>

                                            <Box sx={{ display: "flex", flexDirection: "row" }}>
                                                {itemArtists?.map((artist, index) => (
                                                    <React.Fragment>
                                                        <Link href="" variant="h5" color="textSecondary" underline="hover" textOverflow="ellipsis"
                                                        sx={{ padding: "0px 8px 8px 8px", alignSelf: "flex-start", overflow: "hidden" }}> { artist.name } </Link>
                                                        {index < itemArtists.length - 1 && <Typography variant="h5" color="textSecondary">,&nbsp;</Typography>}
                                                    </React.Fragment>
                                                    ))
                                                }
                                            </Box>
                                        </Box>
                                    </Box>

                                    {isButtonShowing(index + 1) &&
                                            <Fab size="small" color="success" sx={{ position: "absolute", right: "0px", bottom: "0px" }}>
                                                <PlayArrow />
                                            </Fab> }
                                </Box>
                            </ButtonWrapper>
                        )
                    })}
                </Stack>
        </Box>
    )
}

const ButtonWrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    return (
        <div role="button" style={{
            padding: "12px",
            backgroundColor: "rgba(0, 0, 0, 0.35)",
            marginRight: "8px",
            textWrap: "nowrap",
            textAlign: "left",
            display: "flex",
            flexDirection: "row",
            cursor: "pointer",
            border: "1px solid rgba(255, 255, 255, 0.175)",
            borderRadius: "12px",
            maxHeight: "128px",
            width: "auto",
            aspectRatio: "2.5 / 1",
        }}>
            { children }
        </div>
    )
}