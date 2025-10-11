import React, { createContext, useContext, useEffect, useState } from "react";
import { Album, Artist, LoopingEnum, Playlist, SidebarItemType, Song } from "../types/SongTypes";
import { AudioPlayer, useAudioPlayer } from "../hooks/useAudioPlayer";
import { useData } from "../hooks/useData";

type CurrentViewType = "home" | "listView" | "artistView" | "search" | "songQueue" | "settings"

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
    },
    music: {
        player: AudioPlayer,
        isDownloading: boolean,
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
    
    // Download State
    const [songLoading, setSongLoading] = useState(false)
    const [currentSongDownloadStatus, setCurrentSongDownloadStatus] = useState<{ status: string; downloadPath: string; message: string } | null>(null)
    const [lastDownloadedIndex, setLastDownloadedIndex] = useState<number>(-1)
    
    const { data, loading, updateData } = useData()
    const audioPlayer = useAudioPlayer()

    // Load saved data on mount
    useEffect(() => {
        if (!loading) {
            if (data.lastPlayed) {
                audioPlayer.addToQueue(data.lastPlayed)
            }
            // Apply saved settings to audio player
            // Note: These are handled internally by the hook now
        }
    }, [loading])

    // Listen for YouTube download status
    useEffect(() => {
        window.electronAPI.extractors.youtube.onDownloadStatus((status) => {
            setCurrentSongDownloadStatus(status)
        })
    }, [])

    useEffect(() => {
        if (currentSongDownloadStatus?.status === 'downloading') {
            setSongLoading(true)
            audioPlayer.pause()
        }

        if (currentSongDownloadStatus?.status === 'done' && currentSongDownloadStatus.downloadPath) {
            console.log(`Download complete, loading: ${currentSongDownloadStatus.downloadPath}`)
            audioPlayer.load(`wisp-audio://${(currentSongDownloadStatus.downloadPath)}`)
            audioPlayer.play()
            setSongLoading(false)
        }

        if (currentSongDownloadStatus?.status === 'error') {
            console.error(`Download error: ${currentSongDownloadStatus.message}`)
            setSongLoading(false)
        }
    }, [currentSongDownloadStatus])

    // Track download status for current song
    useEffect(() => {
        const currentSong = audioPlayer.getCurrentSong()
        
        if (!currentSong || audioPlayer.currentIndex === lastDownloadedIndex) {
            return
        }
        
        setLastDownloadedIndex(audioPlayer.currentIndex)
        setSongLoading(true)
        
        console.log(`Requesting download for song: ${currentSong.title}`)
        
        // Build search query from song metadata for YouTube download
        // This works for both Spotify and YouTube sourced songs
        const artists = currentSong.artists.map(a => a.name).join(", ")
        const searchQuery = `${currentSong.title} - ${artists}`
        window.electronAPI.extractors.youtube.downloadYoutubeAudio("terms", searchQuery)
    }, [audioPlayer.currentIndex])

    // Media Session API Implementation
    useEffect(() => {
        const currentSong = audioPlayer.getCurrentSong()
        
        if ('mediaSession' in navigator && currentSong) {
            const artists = currentSong.artists.map(a => a.name).join(", ")

            // Update playback state based on actual playing state
            navigator.mediaSession.playbackState = audioPlayer.isPlaying ? "playing" : "paused"

            navigator.mediaSession.setActionHandler('play', () => {
                audioPlayer.play()
            })

            navigator.mediaSession.setActionHandler('pause', () => {
                audioPlayer.pause()
            })

            navigator.mediaSession.setActionHandler('previoustrack', () => {
                audioPlayer.skipPrevious()
            })

            navigator.mediaSession.setActionHandler('nexttrack', () => {
                audioPlayer.skipNext()
            })

            navigator.mediaSession.metadata = new MediaMetadata({
                title: currentSong.title,
                artist: artists,
                artwork: currentSong.thumbnailURL ? [
                    { src: currentSong.thumbnailURL, sizes: '512x512', type: 'image/jpeg' }
                ] : []
            })

            if (currentSong.durationSecs) {
                // Get current position directly from audio player to avoid stale timestamp when paused
                navigator.mediaSession.setPositionState({
                    duration: currentSong.durationSecs,
                    playbackRate: 1,
                    position: audioPlayer.currentTime
                })
            }
        }
    }, [audioPlayer.currentTime, audioPlayer.currentIndex, audioPlayer.isPlaying])

    if (loading) {
        return <></>
    }

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
                    search: searchQuery,
                    setSearch: setSearchQuery,
                    shownThing: shownThing,
                    setShownThing: setShownThing
                }
            },
            music: {
                player: audioPlayer,
                isDownloading: songLoading
            }
        }}>
            {children}
        </AppContext.Provider>
    )
}