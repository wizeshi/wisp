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
import { GenericAlbum, SidebarListType,SidebarListTypes, GenericPlaylist, GenericSimpleArtist } from "../../common/types/SongTypes"
import Stack from "@mui/material/Stack"
import ButtonBase from "@mui/material/ButtonBase"
import Skeleton from "@mui/material/Skeleton"
import ExplicitIcon from '@mui/icons-material/Explicit'
import { isAlbum, isPlaylist, isSimpleArtist } from "../utils/Helpers"

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
    fontSize: "80px",
    borderRadius: "0px"
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
    const [lists, setLists] = useState<GenericPlaylist[] | GenericAlbum[] | GenericSimpleArtist[] | null>(null)
    const [username, setUsername] = useState<string | null>(null)

    const handleToggle = useCallback(() => {
        app.sidebar.setOpen(!app.sidebar.open)
    }, [app.sidebar])

    // Fetch username on mount
    useEffect(() => {
        const fetchUsername = async () => {
            try {
                const userInfo = await window.electronAPI.extractors.getUserInfo()
                setUsername(userInfo.displayName || userInfo.id || "User")
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
            let realList: GenericAlbum[] | GenericPlaylist[] | GenericSimpleArtist[]
            switch (typeShown) {
              case "Playlists": {
                const resultList = await window.electronAPI.extractors.getUserLists("Playlists", "spotify")
                realList = resultList
                break
              }
              case "Albums": {
                const resultList = await window.electronAPI.extractors.getUserLists("Albums", "spotify")
                realList = resultList
                break
              }
              case "Artists": {
                const resultList = await window.electronAPI.extractors.getUserLists("Artists")
                realList = resultList
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
      <Drawer variant="permanent" open={app.sidebar.open} anchor="left" slotProps={{
        paper: {
          sx: { marginTop: "32px"}
        }
      }}>
        <SidebarHeader isOpen={app.sidebar.open} onToggle={handleToggle} username={username} />
        <Divider />
        <ButtonBase onClick={() => {app.screen.setCurrentView("likesView")}} sx={{ justifyContent: "unset", display: "flex", padding: "8px 8px 8px 16px", overflowX: "clip" }}>
          <Avatar variant="rounded" src="https://misc.scdn.co/liked-songs/liked-songs-300.jpg" sx={{ height: "60px", width: "60px" }}/>
          {app.sidebar.open && (
            <Typography variant="body1" sx={{ alignSelf: "center", margin: "6px 0px 6px 16px", fontWeight: "bold", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>Liked Songs</Typography>
          )}
        </ButtonBase>
        <Divider />
        <TypeFilterButtons isOpen={app.sidebar.open} typeShown={typeShown} onTypeChange={setTypeShown} />
        {loading || !lists ? <LoadingSkeletonList isOpen={app.sidebar.open} /> : <SidebarList sidebarThings={lists} />}
      </Drawer>
    )
}

const getItemDetails = (thing: GenericAlbum | GenericPlaylist | GenericSimpleArtist) => {
  if (isAlbum(thing)) {
    const desc = thing.artists.map(artist => artist.name).join(", ")
    return { name: thing.title, desc, explicit: thing.explicit, thumbnailURL: thing.thumbnailURL }
  }
  if (isPlaylist(thing)) {
    return { name: thing.title, desc: thing.author.displayName, explicit: false, thumbnailURL: thing.thumbnailURL }
  }
  if (isSimpleArtist(thing)) {
    return { name: thing.name, desc: "Artist", explicit: false, thumbnailURL: thing.thumbnailURL }
  }
  return { name: "", desc: "", explicit: false, thumbnailURL: "" }
}

const SidebarListItem = memo<{ 
  thing: GenericAlbum | GenericPlaylist | GenericSimpleArtist
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

export const SidebarList: React.FC<{ sidebarThings: GenericAlbum[] | GenericPlaylist[] | GenericSimpleArtist[] }> = memo(({ sidebarThings }) => {
  const { app } = useAppContext()
  
  const handleItemClick = useCallback((item: GenericAlbum | GenericPlaylist | GenericSimpleArtist) => {
    // Check by properties instead of instanceof since objects come from IPC
    if ('author' in item && 'title' in item) {
      // It's a GenericPlaylist
      app.screen.setShownThing({ id: item.id, type: "Playlist" })
      app.screen.setCurrentView("listView")
    } else if ('artists' in item && 'explicit' in item && 'releaseDate' in item) {
      // It's a GenericAlbum
      app.screen.setShownThing({ id: item.id, type: "Album" })
      app.screen.setCurrentView("listView")
    } else if ('name' in item && !('title' in item)) {
      // It's a GenericSimpleArtist
      app.screen.setShownThing({ id: item.id, type: "Artist" })
      app.screen.setCurrentView("artistView")
    }
  }, [app.screen])

  const listSx = useMemo(() => [
    { overflowY: "scroll", padding: "0 0 0 0" }, 
    app.sidebar.open ? {} : { scrollbarWidth: "none" }
  ], [app.sidebar.open])

  return (
    <List sx={listSx}>
      {sidebarThings.map((thing, index) => {
        return(
          <SidebarListItem 
            key={`${thing.id}-${index}`}
            thing={thing}
            isOpen={app.sidebar.open}
            onItemClick={() => handleItemClick(thing)}
          />)
      })}
    </List>
  )
})

SidebarList.displayName = 'SidebarList'