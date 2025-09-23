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
import React from "react"
import { useAppContext } from "../providers/AppContext"
import ViewWeekIcon from '@mui/icons-material/ViewWeek';
import MenuOpenIcon from '@mui/icons-material/MenuOpen';
import ListItemText from "@mui/material/ListItemText"

const drawerWidth = 240

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

export const Sidebar: React.FC = () => {
    const { app } = useAppContext()

    const handleToggle = () => {
        if (!app.sidebar.open) {
            return app.sidebar.setOpen(true)
        } else {
            return app.sidebar.setOpen(false)
        }

    }

    // Needs backend; Placeholders for now.
    const sidebarThings = [
        { id: "pl1", label: "Playlist 1", origin: "username", thumbnail: "" },
        { id: "ar1", label: "Artist 1", origin: "username", thumbnail: "" },
        { id: "ab1", label: "Album 1", origin: "username", thumbnail: "" },
        { id: "ar2", label: "Artist 2", origin: "username", thumbnail: "" },
        { id: "pl2", label: "Playlist 2", origin: "username", thumbnail: "" },
        { id: "ab2", label: "Album 2", origin: "username", thumbnail: "" },
        { id: "ab2", label: "Album 2", origin: "username", thumbnail: "" },
        { id: "ab2", label: "Album 2", origin: "username", thumbnail: "" },
        { id: "ab2", label: "Album 2", origin: "username", thumbnail: "" },
    ]

    return (
        <Drawer variant="permanent" open={app.sidebar.open} anchor="left">
            <Box display="inherit">
                {app.sidebar.open ? 
                    <>  
                        <Box sx={{ marginTop: "auto", marginBottom: "auto", marginLeft: "auto", marginRight: "auto" }}>
                            <Typography variant="h6" fontSize="16px">
                                Your Library
                            </Typography>
                            <Typography variant="body2" color="textSecondary">
                                username
                            </Typography>  
                        </Box>
                        <Divider orientation="vertical" sx={{  }}/>
                    </>
                    : <></>
                }
                

                <IconButton onClick={handleToggle} sx={[
                    app.sidebar.open ? {
                        /* marginLeft: "auto" */
                    } : {
                        marginLeft: "auto",
                        marginRight: "auto",
                    },
                    {
                        height: "80px",
                        width: "80px",
                        fontSize: "80px"
                    }
                ]}>
                    {app.sidebar.open ? <MenuOpenIcon fontSize="large"/> : <ViewWeekIcon fontSize="large" />}
                </IconButton>
            </Box>

            <Divider />

            <List sx={[{ overflowY: "scroll", padding: "0 0 0 0" }, app.sidebar.open ? {}: { scrollbarWidth: "none" }]}>

                {sidebarThings.map((thing, index) => (
                    <ListItem key={thing.id} sx={{ padding: "0px 0px 0px 0px" }}>
                        <ListItemButton onClick={() => {app.screen.setCurrentView("sidebarList")}} sx={{ height: "80px", padding: "8 8 0 0" }}>
                            <ListItemAvatar>
                                <Avatar variant="rounded" src="" sx={{ height: "60px", width: "60px" }}/>
                            </ListItemAvatar>
                            {app.sidebar.open ? <ListItemText primary={thing.label} secondary={thing.origin} sx={{ marginLeft: "16px" }}/> : <></>}
                        </ListItemButton>
                    </ListItem>
                ))}

            </List>

        </Drawer>
    )
}