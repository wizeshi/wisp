import React, { createContext, useContext, useEffect, useState } from "react";
import { Album, Artist, LoopingEnum, Playlist, SidebarItemType, Song } from "../types/SongTypes";
import { AudioPlayer, useAudioPlayer } from "../hooks/useAudioPlayer";
import { useData } from "../hooks/useData";
import { DownloadManager, useDownloadManager } from "../hooks/useDownloadManager";

type CurrentViewType = "home" | "listView" | "artistView" | "lyricsView" | "search" | "songQueue" | "settings"

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
        downloads: DownloadManager,
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
    const [lastPlayedIndex, setLastPlayedIndex] = useState<number>(-1)
    const lastLoadedPathRef = React.useRef<string>("")
    
    const { data, loading, updateData } = useData()
    const audioPlayer = useAudioPlayer()
    const downloadManager = useDownloadManager()

    // Load saved data on mount
    useEffect(() => {
        if (!loading) {
            if (data.lastPlayed) {
                const index = audioPlayer.addToQueue(data.lastPlayed)
                audioPlayer.goToIndex(index)
                let i = 1
                const playEventListener = () => {
                    if (i >= 1) {
                        audioPlayer.pause()
                        i--
                    } else {
                        // Do nothing
                    }
                }

                audioPlayer.player.addEventListener('play', playEventListener)

                return () => {
                    audioPlayer.player.removeEventListener('play', playEventListener)
                }
            }
        }
    }, [loading])

    // Handle song changes and downloads
    useEffect(() => {
        const currentSong = audioPlayer.getCurrentSong()
        
        if (!currentSong || audioPlayer.currentIndex === lastPlayedIndex) {
            return
        }
        
        setLastPlayedIndex(audioPlayer.currentIndex)
        
        // Generate download ID for current song
        const downloadId = downloadManager.requestDownload(currentSong)
        
        // Check if already downloaded
        if (downloadManager.hasDownloaded(downloadId)) {
            const path = downloadManager.getDownloadPath(downloadId)
            if (path) {
                const audioPath = `wisp-audio://${path}`
                // Only load if it's different from current
                if (lastLoadedPathRef.current !== audioPath) {
                    console.log(`Song already downloaded, loading: ${path}`)
                    lastLoadedPathRef.current = audioPath
                    audioPlayer.load(audioPath)
                    audioPlayer.play()
                }
                setSongLoading(false)
            }
        } else {
            // Wait for download
            setSongLoading(true)
            console.log(`Requesting download for song: ${currentSong.title}`)
        }

        // Preload next songs in queue
        const queue = audioPlayer.queue
        const upcomingCount = Math.min(3, queue.length - audioPlayer.currentIndex - 1)
        for (let i = 1; i <= upcomingCount; i++) {
            const nextSong = queue[audioPlayer.currentIndex + i]
            if (nextSong) {
                downloadManager.requestDownload(nextSong)
            }
        }
    }, [audioPlayer.currentIndex])

    // Monitor download status of current song
    useEffect(() => {
        // Don't interfere with playback during seeking
        if (audioPlayer.isSeeking) return
        
        const currentSong = audioPlayer.getCurrentSong()
        if (!currentSong) return

        const artists = currentSong.artists.map(a => a.name).join(", ")
        const downloadId = `${currentSong.title} - ${artists}`
        const status = downloadManager.getDownloadStatus(downloadId)

        console.log(`Checking download status for ${downloadId}:`, status)

        if (!status) return

        // Handle downloading/pending state
        if (status.status === 'downloading' || status.status === 'pending') {
            if (!songLoading) {
                setSongLoading(true)
                // Don't pause if user is actively seeking
                if (audioPlayer.isPlaying && !audioPlayer.isSeeking) {
                    audioPlayer.pause()
                }
            }
            return // Don't process further if still downloading
        }

        // Handle completed download
        if (status.status === 'done' && status.downloadPath) {
            const audioPath = `wisp-audio://${status.downloadPath}`
            
            // Only load if it's a different path from what's currently loaded
            if (lastLoadedPathRef.current !== audioPath) {
                console.log(`Download complete, loading: ${status.downloadPath}`)
                lastLoadedPathRef.current = audioPath
                audioPlayer.load(audioPath)
                audioPlayer.play()
            } else {
                // Path already loaded, just ensure loading state is cleared
                console.log(`Audio already loaded: ${audioPath}`)
            }
            
            // Always clear loading state when done
            if (songLoading) {
                setSongLoading(false)
            }
        }

        // Handle error state
        if (status.status === 'error') {
            console.error(`Download error: ${status.message}`)
            if (songLoading) {
                setSongLoading(false)
            }
            // Optionally skip to next song on error
            // audioPlayer.skipNext()
        }
    }, [audioPlayer.currentIndex, downloadManager.statusVersion]) // Depend on index and download version

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
                downloads: downloadManager,
                isDownloading: songLoading
            }
        }}>
            {children}
        </AppContext.Provider>
    )
}