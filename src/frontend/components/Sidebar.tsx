import Avatar from "@mui/material/Avatar"
import { CSSObject, styled, Theme } from "@mui/material/styles"
import Divider from "@mui/material/Divider"
import IconButton from "@mui/material/IconButton"
import List from "@mui/material/List"
import ListItem from "@mui/material/ListItem"
import ListItemAvatar from "@mui/material/ListItemAvatar"
import ListItemButton from "@mui/material/ListItemButton"
import Typography from "@mui/material/Typography"
import MuiDrawer from "@mui/material/Drawer"
import Box from "@mui/material/Box"
import React, { useEffect, useState, useCallback, useMemo, memo } from "react"
import { useAppContext } from "../providers/AppContext"
import ViewWeekIcon from '@mui/icons-material/ViewWeek';
import MenuOpenIcon from '@mui/icons-material/MenuOpen';
import ListItemText from "@mui/material/ListItemText"
import { Album, Artist, SidebarListType, SidebarListTypes, Playlist, BaseSongList } from "../types/SongTypes"
import Stack from "@mui/material/Stack"
import ButtonBase from "@mui/material/ButtonBase"
import { spotifyArtistToArtist } from "../utils/Helpers"
import Skeleton from "@mui/material/Skeleton"
import ExplicitIcon from '@mui/icons-material/Explicit'

const drawerWidth = 320

const LoadingSkeletonList = memo<{ isOpen: boolean }>(({ isOpen }) => (
  <List sx={[{ overflowY: "scroll", padding: "0 0 0 0" }, isOpen ? {} : { scrollbarWidth: "none" }]}>
    {Array.from({ length: 5 }, (_, index) => (
      <ListItem key={index} sx={{ padding: "0px 0px 0px 0px", overflowX: "clip" }}>
        <ListItemButton sx={{ height: "80px", padding: "8 8 0 0" }}>
          <ListItemAvatar>
            <Skeleton variant="rounded" sx={{ height: "60px", width: "60px" }}/>
          </ListItemAvatar>
          {isOpen && <ListItemText primary={<Skeleton />} secondary={<Skeleton />} sx={{ marginLeft: "16px", textOverflow: "ellipsis" }}/>}
        </ListItemButton>
      </ListItem>
    ))}
  </List>
))

LoadingSkeletonList.displayName = 'LoadingSkeletonList'

const openedMixin = (theme: Theme): CSSObject => ({
  width: drawerWidth,
  transition: theme.transitions.create('width', {
    easing: theme.transitions.easing.sharp,
    duration: theme.transitions.duration.enteringScreen,
  }),
  overflowX: 'hidden',
});

const closedMixin = (theme: Theme): CSSObject => ({
  transition: theme.transitions.create('width', {
    easing: theme.transitions.easing.sharp,
    duration: theme.transitions.duration.leavingScreen,
  }),
  overflowX: 'hidden',
  width: `calc(${theme.spacing(7)} + 1px)`,
  [theme.breakpoints.up('sm')]: {
    width: `calc(${theme.spacing(11)} + 1px)`,
  },
});

const Drawer = styled(MuiDrawer, { shouldForwardProp: (prop) => prop !== 'open' })(
  ({ theme }) => ({
    width: drawerWidth,
    flexShrink: 0,
    whiteSpace: 'nowrap',
    boxSizing: 'border-box',
    variants: [
      {
        props: ({ open }) => open,
        style: {
          ...openedMixin(theme),
          '& .MuiDrawer-paper': openedMixin(theme),
        },
      },
      {
        props: ({ open }) => !open,
        style: {
          ...closedMixin(theme),
          '& .MuiDrawer-paper': closedMixin(theme),
        },
      },
    ],
  }),
);

const iconButtonStyles = {
    height: "80px",
    width: "80px",
    fontSize: "80px"
}

const openIconButtonStyles = {}
const closedIconButtonStyles = {
    marginLeft: "auto",
    marginRight: "auto",
}
const SidebarHeader = memo<{ isOpen: boolean; onToggle: () => void; username: string | null }>(({ isOpen, onToggle, username }) => (
  <Box display="inherit">
    {isOpen && (
      <>  
        <Box sx={{ marginTop: "auto", marginBottom: "auto", marginLeft: "32px", marginRight: "auto" }}>
          <Typography variant="h6" fontSize="16px">
            Your Library
          </Typography>
          <Typography variant="body2" color="textSecondary">
            {username || <Skeleton width={80} />}
          </Typography>  
        </Box>
        <Divider orientation="vertical" sx={{  }}/>
      </>
    )}

    <IconButton 
      onClick={onToggle} 
      sx={[
        isOpen ? openIconButtonStyles : closedIconButtonStyles,
        iconButtonStyles
      ]}
    >
      {isOpen ? <MenuOpenIcon fontSize="large"/> : <ViewWeekIcon fontSize="large" />}
    </IconButton>
  </Box>
))

SidebarHeader.displayName = 'SidebarHeader'

const TypeFilterButtons = memo<{ 
  isOpen: boolean
  typeShown: SidebarListType
  onTypeChange: (type: SidebarListType) => void 
}>(({ isOpen, typeShown, onTypeChange }) => {
  if (!isOpen) return null
  
  return (
    <React.Fragment>
      <Stack 
        direction="row"
        divider={<Divider orientation="vertical" sx={{ margin: "0px 8px 0px 8px" }}/>}
        sx={{ maxWidth: "inherit", padding: "4px 0px 4px 4px", margin: "0 auto", flexShrink: 0 }}
      >
        {SidebarListTypes.map((type) => (
          <ButtonBase 
            key={type}
            sx={{ 
              height: "32px", 
              padding: "12px", 
              backgroundColor: typeShown === type ? "rgba(0, 0, 0, 0.55)" : "rgba(0, 0, 0, 0.35)",
              borderRadius: "12px",
            }}
            onClick={() => onTypeChange(type)}
          >
            <Typography variant="body2">
              {type}
            </Typography>
          </ButtonBase>
        ))}
      </Stack>
      <Divider />
    </React.Fragment>
  )
})

TypeFilterButtons.displayName = 'TypeFilterButtons'

export const Sidebar: React.FC = () => {
    const { app } = useAppContext()
    const [typeShown, setTypeShown] = useState<SidebarListType>("Playlists")
    const [loading, setLoading] = useState(true)
    const [lists, setLists] = useState<Playlist[] | Album[] | Artist[] | null>(null)
    const [username, setUsername] = useState<string | null>(null)

    const handleToggle = useCallback(() => {
        app.sidebar.setOpen(!app.sidebar.open)
    }, [app.sidebar])

    // Fetch username on mount
    useEffect(() => {
        const fetchUsername = async () => {
            try {
                const userInfo = await window.electronAPI.extractors.spotify.getUserInfo()
                setUsername(userInfo.display_name || userInfo.id || "User")
            } catch (err) {
                console.error('Error fetching user info:', err)
                setUsername("User")
            }
        }

        fetchUsername()
    }, [])

    useEffect(() => {
      let cancelled = false

        const fetchLists = async () => {
          setLoading(true)
          
          try {
            let realList: Album[] | Playlist[] | Artist[]
            switch (typeShown) {
              case "Playlists": {
                const resultList = await window.electronAPI.extractors.spotify.getUserLists("Playlists")
                const playlists: Playlist[] = []
                resultList.forEach((item) => {
                  const thumbnailUrl = item.images && item.images.length > 0 ? item.images[0].url : ""
                  const result = new Playlist(item.name, item.owner.display_name ?? "Unknown", [], thumbnailUrl, item.id)
                  playlists.push(result)
                })
                realList = playlists
                break
              }
              case "Albums": {
                const resultList = await window.electronAPI.extractors.spotify.getUserLists("Albums")
                const albums: Album[] = []
                resultList.forEach((item) => {
                  const artists: Artist[] = []
                  item.album.artists.forEach((artist) => {
                    artists.push(spotifyArtistToArtist(artist))
                  })

                  const label = item.album.copyrights && item.album.copyrights.length > 0 
                    ? item.album.copyrights[0].text 
                    : "Unknown"
                  const thumbnailUrl = item.album.images && item.album.images.length > 0 
                    ? item.album.images[0].url
                    : ""
                  const releaseDate = item.album.release_date ? new Date(item.album.release_date) : new Date()
                  
                  const result = new Album(
                    item.album.name, 
                    artists, 
                    label, 
                    releaseDate, 
                    false, 
                    [], 
                    thumbnailUrl,
                    item.album.id
                  )
                  albums.push(result)
                })
                realList = albums
                break
              }
              case "Artists": {
                const resultList = await window.electronAPI.extractors.spotify.getUserLists("Artists")
                const artists: Artist[] = []
                resultList.forEach((item) => {
                  const thumbnailUrl = item.images && item.images.length > 0 ? item.images[0].url : ""
                  artists.push(new Artist(item.name, thumbnailUrl))
                })
                realList = artists
                break
              }
            }      

            if (!cancelled) {
              setLists(realList)
            }
          } catch (err) {
            if (!cancelled) {
              console.error('Error fetching lists:', err)
            }
          } finally {
            if (!cancelled) {
              setLoading(false)
            }
          }
        }

        fetchLists()

        return () => {
          cancelled = true
        }
    }, [typeShown])

    return (
      <Drawer variant="permanent" open={app.sidebar.open} anchor="left">
        <SidebarHeader isOpen={app.sidebar.open} onToggle={handleToggle} username={username} />
        <Divider />
        <TypeFilterButtons isOpen={app.sidebar.open} typeShown={typeShown} onTypeChange={setTypeShown} />
        {loading || !lists ? <LoadingSkeletonList isOpen={app.sidebar.open} /> : <SidebarList sidebarThings={lists} />}
      </Drawer>
    )
}

const getItemDetails = (thing: Album | Playlist | Artist) => {
  if (thing instanceof Album) {
    const desc = thing.artists.map(artist => artist.name).join(", ")
    return { name: thing.title, desc, explicit: thing.explicit, thumbnailURL: thing.thumbnailURL }
  }
  if (thing instanceof Playlist) {
    return { name: thing.title, desc: thing.author, explicit: false, thumbnailURL: thing.thumbnailURL }
  }
  if (thing instanceof Artist) {
    return { name: thing.name, desc: "Artist", explicit: false, thumbnailURL: thing.thumbnailURL }
  }
  return { name: "", desc: "", explicit: false, thumbnailURL: "" }
}

const SidebarListItem = memo<{ 
  thing: Album | Playlist | Artist
  isOpen: boolean
  onItemClick: () => void
}>(({ thing, isOpen, onItemClick }) => {
  const { name, desc, thumbnailURL, explicit } = useMemo(() => getItemDetails(thing), [thing])
  
  return (
    <ListItem sx={{ padding: "0px 0px 0px 0px", overflowX: "clip" }}>
      <ListItemButton onClick={onItemClick} sx={{ height: "80px", padding: "8 8 0 0" }}>
        <ListItemAvatar>
          <Avatar variant="rounded" src={thumbnailURL} sx={{ height: "60px", width: "60px" }}/>
        </ListItemAvatar>
        {isOpen && <ListItemText primary={name} secondary={
          <Box sx={{ display: "flex" }}>
            { explicit && <ExplicitIcon color="disabled" /> } 
            <p style={{ margin: "auto 0 auto 4px" }}>{ desc }</p>
          </Box>
          } sx={{ marginLeft: "16px", textOverflow: "ellipsis" }}/>}
      </ListItemButton>
    </ListItem>
  )
})

SidebarListItem.displayName = 'SidebarListItem'

export const SidebarList: React.FC<{ sidebarThings: Album[] | Playlist[] | Artist[] }> = memo(({ sidebarThings }) => {
  const { app } = useAppContext()
  
  const handleItemClick = useCallback((item: Album | Playlist | Artist) => {
    if (item instanceof BaseSongList) {
      app.screen.setShownList(item)
    } else {
      // whatever
    }
    app.screen.setCurrentView("sidebarList")
  }, [app.screen])

  const listSx = useMemo(() => [
    { overflowY: "scroll", padding: "0 0 0 0" }, 
    app.sidebar.open ? {} : { scrollbarWidth: "none" }
  ], [app.sidebar.open])

  return (
    <List sx={listSx}>
      {sidebarThings.map((thing, index) => {
        let type: "Album" | "Playlist"
        let id = ""
        if (thing instanceof Album) {
          type = "Album"
          id = thing.id
        }
        if (thing instanceof Playlist) {
          type = "Playlist"
          id = thing.id
        }
        return(
          <SidebarListItem 
            key={`${getItemDetails(thing).name}-${index}`}
            thing={thing}
            isOpen={app.sidebar.open}
            onItemClick={() => handleItemClick(thing)}
          />)
      })}
    </List>
  )
})

SidebarList.displayName = 'SidebarList'