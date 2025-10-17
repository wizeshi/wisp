import React, { createContext, useContext, useEffect, useState, useMemo } from "react";
import { GenericAlbum, GenericArtist, LoopingEnum, GenericPlaylist, SidebarItemType, GenericSong } from "../../common/types/SongTypes";
// import { AudioPlayer, useAudioPlayer } from "../hooks/useAudioPlayer";
// import { useData } from "../hooks/useData";
// import { DownloadManager, useDownloadManager } from "../hooks/useDownloadManager";

type CurrentViewType = "home" | "likesView" | "listView" | "artistView" | "lyricsView" | "search" | "songQueue" | "settings"

type ShownThingType = {
    id: string, 
    type: SidebarItemType 
}

export type AppContextType = {
    app: {
        sidebar: {
            open: boolean,
            setOpen: (value: boolean) => void,
        },
        screen: {
            currentView: CurrentViewType,
            setCurrentView: (newView: CurrentViewType) => void,
            shownThing: ShownThingType,
            setShownThing: (newThing: ShownThingType) => void,
            search: string,
            setSearch: (searchQuery: string) => void,
        }
    }
}


const AppContext = createContext<AppContextType | undefined>(undefined)

export const useAppContext = () => {
    const ctx = useContext(AppContext)
    if (!ctx) throw new Error("useAppContext must be used withing an AppContextProvider!")
    return ctx
}

export const AppContextProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    // UI State
    const [sidebarOpen, setSidebarOpen] = useState(false)
    const [currentView, setCurrentView] = useState<CurrentViewType>("home")
    const [searchQuery, setSearchQuery] = useState<string>("")
    const [shownThing, setShownThing] = useState<ShownThingType | undefined>(undefined)

    const contextValue = useMemo(() => ({
        app: {
            sidebar: {
                open: sidebarOpen,
                setOpen: setSidebarOpen,
            },
            screen: {
                currentView: currentView,
                setCurrentView: setCurrentView,
                search: searchQuery,
                setSearch: setSearchQuery,
                shownThing: shownThing,
                setShownThing: setShownThing
            }
        }
    }), [sidebarOpen, currentView, searchQuery, shownThing])

    return (
        <AppContext.Provider value={contextValue}>
            {children}
        </AppContext.Provider>
    )
}