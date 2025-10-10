import React, { createContext, useContext, useEffect, useState } from "react";
import { Album, LoopingEnum, Playlist, Song } from "../types/SongTypes";
import { AudioPlayer, useAudioPlayer } from "../hooks/useAudioPlayer";

type CurrentViewType = "home" | "sidebarList" | "search" | "songQueue" | "settings"

export type AppContextType = {
    app: {
        sidebar: {
            open: boolean,
            setOpen: (value: boolean) => void,
        },
        screen: {
            currentView: CurrentViewType,
            setCurrentView: (newView: CurrentViewType) => void,
            shownList: Album | Playlist,
            setShownList: (newList: Album | Playlist) => void,
            search: string,
            setSearch: (searchQuery: string) => void,
        }
    },
    music: {
        player: {
            songIndex: number,
            setSongIndex: (newIndex: number) => void,
            getCurrentSong: () => Song,
            shuffle: {
                shuffled: boolean,
                order: number[],
                index: number,
                toggle: () => void
            },
            loop: {
                type: LoopingEnum,
                setType: (newType: LoopingEnum) => void
            }
            songLoading: boolean,
            queue: Song[],
            setQueue: (queue: Song[]) => void
            addSongToQueue: (song: Song) => number,
        }
        audioPlayerElement: AudioPlayer,
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
    const [privateSongIndex, setPrivateSongIndex] = useState<number>(undefined)
    const [songIndex, setSongIndex] = useState<number>(undefined)
    const [searchQuery, setSearchQuery] = useState<string>("")
    const [queue, setQueue] = useState<Song[]>([])
    const [shuffle, setShuffle] = useState(false)
    const [shuffleOrder, setShuffleOrder] = useState<number[]>([])
    const [shuffleIndex, setShuffleIndex] = useState(0)
    const [songLoading, setSongLoading] = useState(false)
    const [currentSongDownloadStatus, setCurrentSongDownloadStatus] = useState<{ status: string; downloadPath: string; message: string } | null>(null);
    const [shownList, setShownList] = useState<Playlist | Album | undefined>(undefined)
    const [repeat, setRepeat] = useState<LoopingEnum>(LoopingEnum.Off)

    const audioPlayer = useAudioPlayer();

    useEffect(() => {
        window.electronAPI.extractors.youtube.onDownloadStatus((status) => {
            setCurrentSongDownloadStatus(status)
        })
    }, [])

    const addSongToQueue = (song: Song) => {
        let artists = ''
        song.artists.forEach((artist, index) => {
            artists += `${artist.name}`
            song.artists.length > index ? artists += ", " : artists += ""
        })

        setQueue([...queue, song])

        return queue.length
    }

    const getCurrentSong = () => {
        return queue[songIndex]
    }

    const generateShuffleOrder = () => {
        const shuffleMethod = window.electronAPI.settings.load().shuffleType

        switch (shuffleMethod) {
            default:
            case "Fisher-Yates": {
                const indices = queue.map((_, index) => index)
        
                for (let i = indices.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    [indices[i], indices[j]] = [indices[j], indices[i]]
                }
        
                setShuffleOrder(indices)
                setShuffleIndex(0)
                break
            }
            case "Algorithmic": {
                // Create indices array and shuffle it first
                const indices = queue.map((_, index) => index)
                
                // Fisher-Yates shuffle as base
                for (let i = indices.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    [indices[i], indices[j]] = [indices[j], indices[i]]
                }

                // Smart shuffle: spread out songs by same artist
                for (let i = 0; i < indices.length - 1; i++) {
                    const currentSongIdx = indices[i]
                    const nextSongIdx = indices[i + 1]
                    const currentSong = queue[currentSongIdx]
                    const nextSong = queue[nextSongIdx]

                    // Check if songs share artists
                    const sharedArtists = currentSong.artists.filter(artist1 =>
                        nextSong.artists.some(artist2 => artist1.name === artist2.name)
                    )

                    // If they share artists, try to swap the next song with a later one
                    if (sharedArtists.length > 0 && i + 2 < indices.length) {
                        // Find a song further down that doesn't share artists
                        for (let j = i + 2; j < Math.min(i + 10, indices.length); j++) {
                            const candidateSongIdx = indices[j]
                            const candidateSong = queue[candidateSongIdx]
                            
                            const candidateShared = currentSong.artists.filter(artist1 =>
                                candidateSong.artists.some(artist2 => artist1.name === artist2.name)
                            )

                            // If candidate doesn't share artists, swap it
                            if (candidateShared.length === 0) {
                                [indices[i + 1], indices[j]] = [indices[j], indices[i + 1]]
                                break
                            }
                        }
                    }
                }

                setShuffleOrder(indices)
                setShuffleIndex(0)
                break
            }
        }
    }

    const toggleShuffle = () => {
        if (!shuffle) {
            generateShuffleOrder()
        }
        setShuffle(!shuffle)
    }

    useEffect(() => {
        if (currentSongDownloadStatus?.status === 'downloading') {
            setSongLoading(true)
            audioPlayer.pause()
        }

        if (currentSongDownloadStatus?.status === 'done' && currentSongDownloadStatus.downloadPath) {
            audioPlayer.load(`wisp-audio://${(currentSongDownloadStatus.downloadPath)}`)
            audioPlayer.play()
            setSongLoading(false)
        }
    }, [currentSongDownloadStatus])

    useEffect(() => {
        if (queue[songIndex] && songIndex != privateSongIndex) {
            let artists = ""
            queue[songIndex].artists.forEach((artist, index) => {
                artists += `${artist.name}`
                index < queue[songIndex].artists.length ? artists += ", " : ""
            })
            const searchQuery = `${queue[songIndex].title} - ${artists}`
            window.electronAPI.extractors.youtube.downloadYoutubeAudio("terms", searchQuery)
            setPrivateSongIndex(songIndex)
        }
    }, [songIndex])

    // Auto-advance to next song when current song ends
    useEffect(() => {
        if (audioPlayer.isPlaying && queue.length > 0) {
            const currentSong = queue[songIndex]
            if (currentSong && currentSong.durationSecs) {
                
                // Check if song has ended (within 0.5 seconds of duration)
                if (audioPlayer.currentTime >= currentSong.durationSecs - 0.5) {
                    // Handle repeat modes
                    if (repeat === LoopingEnum.Song) {
                        // Repeat current song - seek back to start
                        audioPlayer.seek(0)
                    } else if (repeat === LoopingEnum.List) {
                        // Loop through queue
                        if (shuffle) {
                            const nextShuffleIndex = (shuffleIndex + 1) % shuffleOrder.length
                            setShuffleIndex(nextShuffleIndex)
                            setSongIndex(shuffleOrder[nextShuffleIndex])
                        } else {
                            const nextIndex = (songIndex + 1) % queue.length
                            setSongIndex(nextIndex)
                        }
                    } else {
                        // No repeat - only advance if not at the end
                        if (shuffle) {
                            if (shuffleIndex < shuffleOrder.length - 1) {
                                const nextShuffleIndex = shuffleIndex + 1
                                setShuffleIndex(nextShuffleIndex)
                                setSongIndex(shuffleOrder[nextShuffleIndex])
                            } else {
                                // End of queue - pause
                                audioPlayer.pause()
                            }
                        } else {
                            if (songIndex < queue.length - 1) {
                                setSongIndex(songIndex + 1)
                            } else {
                                // End of queue - pause
                                audioPlayer.pause()
                            }
                        }
                    }
                }
            }
        }
    }, [audioPlayer.currentTime, songIndex, queue.length, audioPlayer.isPlaying, repeat, shuffle, shuffleIndex, shuffleOrder])

    // Media Session API Implementation
    useEffect(() => {
        if ('mediaSession' in navigator && queue[songIndex]) {
            const currentSong = queue[songIndex]
            let artists = ""
            currentSong.artists.forEach((artist, index) => {
                artists += artist.name
                index < currentSong.artists.length - 1 ? artists += ", " : ""
            })

            // Update playback state based on actual playing state
            navigator.mediaSession.playbackState = audioPlayer.isPlaying ? "playing" : "paused"

            navigator.mediaSession.setActionHandler('play', () => {
                audioPlayer.play()
            })

            navigator.mediaSession.setActionHandler('pause', () => {
                audioPlayer.pause()
            })

            navigator.mediaSession.setActionHandler('previoustrack', () => {
                if (shuffle) {
                    if (shuffleIndex > 0) {
                        const prevShuffleIndex = shuffleIndex - 1
                        setShuffleIndex(prevShuffleIndex)
                        setSongIndex(shuffleOrder[prevShuffleIndex])
                    }
                } else {
                    if (songIndex > 0) {
                        setSongIndex(songIndex - 1)
                    }
                }
            })

            navigator.mediaSession.setActionHandler('nexttrack', () => {
                if (shuffle) {
                    if (shuffleIndex < shuffleOrder.length - 1) {
                        const nextShuffleIndex = shuffleIndex + 1
                        setShuffleIndex(nextShuffleIndex)
                        setSongIndex(shuffleOrder[nextShuffleIndex])
                    }
                } else {
                    if (songIndex < queue.length - 1) {
                        setSongIndex(songIndex + 1)
                    }
                }
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
    }, [audioPlayer.currentTime])

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
                    shownList: shownList,
                    setShownList: setShownList
                }
            },
            music: {
                player: {
                    songIndex: songIndex,
                    setSongIndex: setSongIndex,
                    getCurrentSong: getCurrentSong,
                    addSongToQueue: addSongToQueue,
                    shuffle: {
                        shuffled: shuffle,
                        order: shuffleOrder,
                        index: shuffleIndex,
                        toggle: toggleShuffle
                    },
                    loop: {
                        type: repeat,
                        setType: setRepeat
                    },
                    songLoading: songLoading,
                    queue: queue,
                    setQueue: setQueue,
                },
                audioPlayerElement: audioPlayer,
            }
        }}>
            {children}
        </AppContext.Provider>
    )
}