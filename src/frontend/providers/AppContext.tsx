import React, { createContext, useCallback, useContext, useState } from "react";
import { Album, Artist, Playlist, Song } from "../utils/types";

export type AppContextType = {
    app: {
        sidebar: {
            open: boolean,
            setOpen: (value: boolean) => void,
        },
    },
    music: {
        currentSong: Song | undefined,
        songQueue: Song[] | undefined,
        avaliableLists: Array<Artist | Album | Playlist> | undefined,

    }
}


const AppContext = createContext<AppContextType | undefined>(undefined)

export const useAppContext = () => {
    const ctx = useContext(AppContext)
    if (!ctx) throw new Error("useAppContext must be used withing an AppContextProvider!")
    return ctx
}

export const AppContextProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [sidebarOpen, setSidebarOpen] = useState(false)
    
    return (
        <AppContext.Provider value={{
            app: {
                sidebar: {
                    open: sidebarOpen,
                    setOpen: setSidebarOpen,
                }
            },
            music: {
                currentSong: undefined,
                songQueue: undefined,
                avaliableLists: undefined
            }
        }}>
            {children}
        </AppContext.Provider>
    )
}