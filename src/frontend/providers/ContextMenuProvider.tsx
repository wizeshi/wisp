import React, { createContext, useContext, ReactNode, useEffect } from 'react';
import { GenericAlbum, GenericArtist, GenericSimpleAlbum, GenericSimpleArtist, GenericSong, GenericPlaylist } from '../../common/types/SongTypes';
import { ContextMenu } from '../components/ContextMenu';
import { useContextMenu } from '../hooks/useContextMenu';

type ContextMenuContextType = {
    openContextMenu: (
        event: React.MouseEvent,
        context: GenericSong | GenericAlbum | GenericSimpleAlbum | GenericArtist | GenericSimpleArtist | GenericPlaylist
    ) => void;
};

const ContextMenuContext = createContext<ContextMenuContextType | undefined>(undefined);

export const useContextMenuContext = () => {
    const context = useContext(ContextMenuContext);
    if (!context) {
        throw new Error('useContextMenuContext must be used within a ContextMenuProvider');
    }
    return context;
};

export const ContextMenuProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
    const { menuState, openContextMenu, closeContextMenu } = useContextMenu();

    // Close context menu on right-click outside
    useEffect(() => {
        const handleContextMenu = (event: MouseEvent) => {
            // If the context menu is open, close it on any right-click
            // The openContextMenu in child components will handle preventDefault
            // so this only triggers for clicks outside
            if (menuState.position !== null) {
                closeContextMenu();
            }
        };

        // Add listener for context menu events
        document.addEventListener('contextmenu', handleContextMenu);

        return () => {
            document.removeEventListener('contextmenu', handleContextMenu);
        };
    }, [menuState.position, closeContextMenu]);

    return (
        <ContextMenuContext.Provider value={{ openContextMenu }}>
            {children}
            <ContextMenu menuState={menuState} onClose={closeContextMenu} />
        </ContextMenuContext.Provider>
    );
};
