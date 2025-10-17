/**
 * Custom Context Menu Component
 * 
 * A Spotify-like right-click context menu for songs, albums, playlists, and artists.
 * 
 * How to use:
 * 1. Import the context menu hook in your component like this
 *    import { useContextMenuContext } from '../providers/ContextMenuProvider';
 * 
 * 2. Get the openContextMenu function
 *    const { openContextMenu } = useContextMenuContext();
 * 
 * 3. Add onContextMenu handler to any clickable element
 *    <ButtonBase onContextMenu={(e) => openContextMenu(e, song)}>
 *      ...
 *    </ButtonBase>
 * 
 * The context menu will automatically display appropriate options based on the item type.
 */

import React from 'react';
import { GenericAlbum, GenericArtist, GenericSimpleAlbum, GenericSimpleArtist, GenericSong, GenericPlaylist } from '../../common/types/SongTypes';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';
import Divider from '@mui/material/Divider';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import QueueMusicIcon from '@mui/icons-material/QueueMusic';
import AlbumIcon from '@mui/icons-material/Album';
import PersonIcon from '@mui/icons-material/Person';
import ShareIcon from '@mui/icons-material/Share';
import InfoIcon from '@mui/icons-material/Info';
import PlaylistAddIcon from '@mui/icons-material/PlaylistAdd';
import FavoriteIcon from '@mui/icons-material/Favorite';
import DownloadIcon from '@mui/icons-material/Download';
import { useAppContext } from '../providers/AppContext';
import { isAlbum, isPlaylist, isArtist, isSimpleArtist, isSong } from '../utils/Helpers';
import Box from '@mui/material/Box';
import { usePlayer } from '../providers/PlayerContext';

type ContextMenuPosition = {
    mouseX: number;
    mouseY: number;
} | null;

export type ContextMenuState = {
    position: ContextMenuPosition;
    context: GenericSong | GenericAlbum | GenericSimpleAlbum | GenericArtist | GenericSimpleArtist | GenericPlaylist | null;
};

export const ContextMenu: React.FC<{
    menuState: ContextMenuState;
    onClose: () => void;
}> = ({ menuState, onClose }) => {
    const player = usePlayer();
    const { app } = useAppContext();
    const { position, context } = menuState;

    if (!context) return null;

    const handlePlayNow = () => {
        // Check if it's a song (has title, artists, but not songs array)
        if ('title' in context && 'artists' in context && !('songs' in context)) {
            player.setQueue([context as GenericSong], 0);
        } else if (isAlbum(context) || isPlaylist(context)) {
            player.setQueue(context.songs || [], 0);
        }
        onClose();
    };

    const handleAddToQueue = () => {
        // Check if it's a song
        if ('title' in context && 'artists' in context && !('songs' in context)) {
            player.addToQueue(context as GenericSong);
        } else if (isAlbum(context) || isPlaylist(context)) {
            context.songs?.forEach(song => player.addToQueue(song));
        }
        onClose();
    };

    const handleGoToAlbum = () => {
        // Check if it's a song with an album
        if ('title' in context && 'artists' in context && !('songs' in context)) {
            const song = context as GenericSong;
            if (song.album) {
                app.screen.setShownThing({ id: song.album.id, type: "Album" });
                app.screen.setCurrentView("listView");
            }
        }
        onClose();
    };

    const handleGoToArtist = (artistId: string) => {
        app.screen.setShownThing({ id: artistId, type: "Artist" });
        app.screen.setCurrentView("artistView");
        onClose();
    };

    const handleDownload = () => {
        if ('title' in context && 'artists' in context && !('songs' in context)) {
            player.downloads.requestDownload(context as GenericSong);
        } else if (isAlbum(context) || isPlaylist(context)) {
            if ((!context.songs) || (context.songs.length === 0)) {
                if (isAlbum(context)) {
                    window.electronAPI.extractors.getListDetails("Album", context.id).then(detailedList => 
                    detailedList.songs.forEach(
                        song => player.downloads.requestDownload(song)
                    ))
                } else if (isPlaylist(context)) {
                    window.electronAPI.extractors.getListDetails("Playlist", context.id).then(detailedList => 
                        detailedList.songs.forEach(
                            song => player.downloads.requestDownload(song)
                        )
                    )
                }
            } else {
                context.songs.forEach(song => player.downloads.requestDownload(song));
            }
        }
        onClose();
    };

    const handleShare = async () => {
        let url = ""
        switch (context.source) {
            default:
            case "spotify":
                url += "https://open.spotify.com/";

                if (isAlbum(context)) {
                    url += `album/${context.id}`;
                } else if (isPlaylist(context)) {
                    url += `playlist/${context.id}`;
                } else if (isSong(context)) {
                    url += `track/${context.id}`;
                }
                break;
            case "youtube":
                url += "https://www.youtube.com/";
                break;
            case "soundcloud":
                url += "https://soundcloud.com/";
                break;
        }

        navigator.clipboard.writeText(url)
        console.log("Share:", context);
        onClose();
    };

    // Render menu items based on context type
    const renderSongMenu = (song: GenericSong) => (
        <Box>
            <MenuItem onClick={handlePlayNow}>
                <ListItemIcon>
                    <PlayArrowIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Play Now</ListItemText>
            </MenuItem>
            <MenuItem onClick={handleAddToQueue}>
                <ListItemIcon>
                    <QueueMusicIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Add to Queue</ListItemText>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleDownload}>
                <ListItemIcon>
                    <DownloadIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Download</ListItemText>
            </MenuItem>
            <Divider />
            {song.album && (
                <MenuItem onClick={handleGoToAlbum}>
                    <ListItemIcon>
                        <AlbumIcon fontSize="small" />
                    </ListItemIcon>
                    <ListItemText>Go to Album</ListItemText>
                </MenuItem>
            )}
            {song.artists.map((artist, index) => (
                <MenuItem key={index} onClick={() => handleGoToArtist(artist.id)}>
                    <ListItemIcon>
                        <PersonIcon fontSize="small" />
                    </ListItemIcon>
                    <ListItemText>Go to Artist: {artist.name}</ListItemText>
                </MenuItem>
            ))}
            <Divider />
            <MenuItem onClick={handleShare}>
                <ListItemIcon>
                    <ShareIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Share</ListItemText>
            </MenuItem>
        </Box>
    );

    const renderAlbumMenu = (album: GenericAlbum) => (
        <Box>
            <MenuItem onClick={handlePlayNow}>
                <ListItemIcon>
                    <PlayArrowIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Play Album</ListItemText>
            </MenuItem>
            <MenuItem onClick={handleAddToQueue}>
                <ListItemIcon>
                    <QueueMusicIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Add to Queue</ListItemText>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleDownload}>
                <ListItemIcon>
                    <DownloadIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Download Album</ListItemText>
            </MenuItem>
            <Divider />
            {album.artists.map((artist, index) => (
                <MenuItem key={index} onClick={() => handleGoToArtist(artist.id)}>
                    <ListItemIcon>
                        <PersonIcon fontSize="small" />
                    </ListItemIcon>
                    <ListItemText>Go to Artist: {artist.name}</ListItemText>
                </MenuItem>
            ))}
            <Divider />
            <MenuItem onClick={() => handleShare()}>
                <ListItemIcon>
                    <ShareIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Share</ListItemText>
            </MenuItem>
        </Box>
    );

    const renderPlaylistMenu = (playlist: GenericPlaylist) => (
        <Box>
            <MenuItem onClick={handlePlayNow}>
                <ListItemIcon>
                    <PlayArrowIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Play Playlist</ListItemText>
            </MenuItem>
            <MenuItem onClick={handleAddToQueue}>
                <ListItemIcon>
                    <QueueMusicIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Add to Queue</ListItemText>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleDownload}>
                <ListItemIcon>
                    <DownloadIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Download Playlist</ListItemText>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleShare}>
                <ListItemIcon>
                    <ShareIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Share</ListItemText>
            </MenuItem>
        </Box>
    );

    const renderArtistMenu = (artist: GenericArtist | GenericSimpleArtist) => (
        <Box>
            <MenuItem onClick={() => handleGoToArtist(artist.id)}>
                <ListItemIcon>
                    <PersonIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Go to Artist</ListItemText>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleShare}>
                <ListItemIcon>
                    <ShareIcon fontSize="small" />
                </ListItemIcon>
                <ListItemText>Share</ListItemText>
            </MenuItem>
        </Box>
    );

    return (
        <Menu
            open={position !== null}
            onClose={onClose}
            anchorReference="anchorPosition"
            anchorPosition={
                position !== null
                    ? { top: position.mouseY, left: position.mouseX }
                    : undefined
            }
            slotProps={{
                paper: {
                    sx: {
                        backgroundColor: 'rgba(30, 30, 30, 0.35)',
                        backgroundImage: 'none',
                        backdropFilter: 'blur(10px)',
                        border: '1px solid rgba(255, 255, 255, 0.15)',
                        borderRadius: '8px',
                        minWidth: '200px',
                    }
                }
            }}
        >
            {('title' in context && 'artists' in context && !('songs' in context)) && renderSongMenu(context as GenericSong)}
            {isAlbum(context) && renderAlbumMenu(context)}
            {isPlaylist(context) && renderPlaylistMenu(context)}
            {(isArtist(context) || isSimpleArtist(context)) && renderArtistMenu(context)}
        </Menu>
    );
}; 