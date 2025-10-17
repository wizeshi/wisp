import { useState, useCallback } from 'react';
import { GenericAlbum, GenericArtist, GenericSimpleAlbum, GenericSimpleArtist, GenericSong, GenericPlaylist } from '../../common/types/SongTypes';
import { ContextMenuState } from '../components/ContextMenu';

export const useContextMenu = () => {
    const [menuState, setMenuState] = useState<ContextMenuState>({
        position: null,
        context: null
    });

    const openContextMenu = useCallback((
        event: React.MouseEvent,
        context: GenericSong | GenericAlbum | GenericSimpleAlbum | GenericArtist | GenericSimpleArtist | GenericPlaylist
    ) => {
        event.preventDefault();
        event.stopPropagation();
        
        setMenuState({
            position: {
                mouseX: event.clientX,
                mouseY: event.clientY,
            },
            context: context
        });
    }, []);

    const closeContextMenu = useCallback(() => {
        setMenuState({
            position: null,
            context: null
        });
    }, []);

    return {
        menuState,
        openContextMenu,
        closeContextMenu
    };
};
