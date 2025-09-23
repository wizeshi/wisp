import React, { createContext, useCallback, useContext, useState } from "react";
import { Album, Artist, Playlist, Song } from "../utils/types";

type CurrentViewType = "home" | "sidebarList" 

export type AppContextType = {
    app: {
        sidebar: {
            open: boolean,
            setOpen: (value: boolean) => void,
        },
        screen: {
            currentView: CurrentViewType,
            setCurrentView: (newView: CurrentViewType) => void
        }
    },
    music: {
        current: {
            song: Song | undefined,
            setSong: (song: Song) => void,
            second: number,
            setSecond: (second: number) => void,
        },
        playing: boolean,
        setPlaying: (value: boolean) => void
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
    const [currentView, setCurrentView] = useState<CurrentViewType>("home")
    const [currentSong, setCurrentSong] = useState<Song | undefined>(undefined)
    const [playing, setPlaying] = useState(false)
    const [second, setSecond] = useState(0)
    
    return (
        <AppContext.Provider value={{
            app: {
                sidebar: {
                    open: sidebarOpen,
                    setOpen: setSidebarOpen,
                },
                screen: {
                    currentView: currentView,
                    setCurrentView: setCurrentView,
                }
            },
            music: {
                current: {
                    song: currentSong,
                    setSong: setCurrentSong,
                    second: second,
                    setSecond: setSecond,
                },
                playing: playing,
                setPlaying: setPlaying,
                songQueue: undefined,
                avaliableLists: undefined
            }
        }}>
            {children}
        </AppContext.Provider>
    )
}