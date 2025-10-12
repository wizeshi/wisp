import { useCallback, useEffect, useRef, useState } from "react"
import { LoopingEnum, Song } from "../types/SongTypes"
import { useSettings } from "./useSettings"

export const useAudioPlayer = () => {
    const audioRef = useRef(new Audio())
    const player = audioRef.current
    const { settings, loading: settingsLoading } = useSettings()
    
    // Audio state
    const [currentTime, setCurrentTime] = useState(0)
    const [duration, setDuration] = useState(0)
    const [isPlaying, setIsPlaying] = useState(false)
    const [isLoading, setIsLoading] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const isSeekingRef = useRef(false)
    
    const [queue, setQueue] = useState<Song[]>([])
    const [currentIndex, setCurrentIndex] = useState<number>(-1)
    
    const [shuffleEnabled, setShuffleEnabled] = useState<boolean>(false)
    const [shuffleOrder, setShuffleOrder] = useState<number[]>([])
    const [shuffleIndex, setShuffleIndex] = useState<number>(0)
    
    const [loopMode, setLoopMode] = useState<LoopingEnum>(LoopingEnum.Off)

    // Get actual song index (respecting shuffle)
    const getActualIndex = () => {
        if (shuffleEnabled && shuffleOrder.length > 0) {
            return shuffleOrder[shuffleIndex]
        }
        return currentIndex
    }

    // Get current song
    const getCurrentSong = useCallback(() => {
        const index = getActualIndex()
        return queue[index] || null
    }, [shuffleEnabled, shuffleOrder, shuffleIndex, currentIndex, queue])

    // Generate shuffle order - shuffles all songs
    const generateShuffleOrder = (songs: Song[]) => {
        if (settingsLoading) return []
        
        const indices = songs.map((_, index) => index)
        
        // Fisher-Yates shuffle
        for (let i = indices.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [indices[i], indices[j]] = [indices[j], indices[i]]
        }

        if (settings.shuffleType === "Algorithmic") {
            // Smart shuffle: spread out songs by same artist
            for (let i = 0; i < indices.length - 1; i++) {
                const currentSong = songs[indices[i]]
                const nextSong = songs[indices[i + 1]]

                const sharedArtists = currentSong.artists.filter(artist1 =>
                    nextSong.artists.some(artist2 => artist1.name === artist2.name)
                )

                if (sharedArtists.length > 0 && i + 2 < indices.length) {
                    for (let j = i + 2; j < Math.min(i + 10, indices.length); j++) {
                        const candidateSong = songs[indices[j]]
                        const candidateShared = currentSong.artists.filter(artist1 =>
                            candidateSong.artists.some(artist2 => artist1.name === artist2.name)
                        )
                        if (candidateShared.length === 0) {
                            [indices[i + 1], indices[j]] = [indices[j], indices[i + 1]]
                            break
                        }
                    }
                }
            }
        }

        return indices
    }

    // Event listeners for HTML5 Audio element
    useEffect(() => {
        const handleTimeUpdate = () => setCurrentTime(player.currentTime)
        const handleDurationChange = () => setDuration(player.duration)
        const handlePlay = () => setIsPlaying(true)
        const handlePause = () => setIsPlaying(false)
        const handleLoadStart = () => setIsLoading(true)
        const handleCanPlay = () => setIsLoading(false)
        const handleWaiting = () => setIsLoading(true)
        const handleError = () => setError(player.error?.message || 'Unknown error')

        player.addEventListener('timeupdate', handleTimeUpdate)
        player.addEventListener('durationchange', handleDurationChange)
        player.addEventListener('play', handlePlay)
        player.addEventListener('pause', handlePause)
        player.addEventListener('loadstart', handleLoadStart)
        player.addEventListener('canplay', handleCanPlay)
        player.addEventListener('waiting', handleWaiting)
        player.addEventListener('error', handleError)

        return () => {
            player.removeEventListener('timeupdate', handleTimeUpdate)
            player.removeEventListener('durationchange', handleDurationChange)
            player.removeEventListener('play', handlePlay)
            player.removeEventListener('pause', handlePause)
            player.removeEventListener('loadstart', handleLoadStart)
            player.removeEventListener('canplay', handleCanPlay)
            player.removeEventListener('waiting', handleWaiting)
            player.removeEventListener('error', handleError)
        }
    }, [])

    // Auto-advance to next song
    useEffect(() => {
        const currentSong = getCurrentSong()
        if (isPlaying && currentSong && currentSong.durationSecs) {
            if (currentTime >= currentSong.durationSecs - 0.5) {
                if (loopMode === LoopingEnum.Song) {
                    seek(0)
                } else if (loopMode === LoopingEnum.List) {
                    skipNext()
                } else {
                    // No loop - advance only if not at end
                    const hasNext = shuffleEnabled 
                        ? shuffleIndex < shuffleOrder.length - 1
                        : currentIndex < queue.length - 1
                    if (hasNext) {
                        skipNext()
                    } else {
                        pause()
                    }
                }
            }
        }
    }, [currentTime, isPlaying, loopMode, shuffleEnabled, shuffleIndex, currentIndex, queue.length])

    // Playback controls
    const load = (src: string) => {
        setCurrentTime(0)
        player.src = src
    }

    const play = () => {
        player.play().catch(err => {
            console.error('Play failed:', err)
            setIsPlaying(false)
        })
    }

    const pause = () => {
        player.pause()
    }

    const seek = (seekTo: number) => {
        isSeekingRef.current = true
        player.currentTime = seekTo
        // Clear the seeking flag after a short delay to allow seek to complete
        setTimeout(() => {
            isSeekingRef.current = false
        }, 100)
    }

    const setVolume = (newVol: number) => {
        player.volume = newVol / 700
    }

    // Queue controls
    const setQueueAndPlay = (songs: Song[], startIndex = 0) => {
        setQueue(songs)
        
        if (shuffleEnabled && songs.length > 0) {
            const newShuffleOrder = generateShuffleOrder(songs)
            setShuffleOrder(newShuffleOrder)
            // Find where startIndex appears in shuffle order
            const shuffleIdx = newShuffleOrder.findIndex(s => s === startIndex)
            setShuffleIndex(shuffleIdx !== -1 ? shuffleIdx : 0)
        } else {
            // Force update even if same index by temporarily setting to -1
            setCurrentIndex(-1)
            // Use setTimeout to ensure state update happens
            setTimeout(() => setCurrentIndex(startIndex), 0)
        }
    }

    const addToQueue = (song: Song) => {
        setQueue([...queue, song])
        return queue.length
    }

    // Navigation controls
    const skipNext = () => {
        if (shuffleEnabled) {
            if (shuffleIndex < shuffleOrder.length - 1) {
                setShuffleIndex(shuffleIndex + 1)
            } else if (loopMode === LoopingEnum.List) {
                setShuffleIndex(0)
            }
        } else {
            if (currentIndex < queue.length - 1) {
                setCurrentIndex(currentIndex + 1)
            } else if (loopMode === LoopingEnum.List) {
                setCurrentIndex(0)
            }
        }
    }

    const skipPrevious = () => {
        if (shuffleEnabled) {
            if (shuffleIndex > 0) {
                setShuffleIndex(shuffleIndex - 1)
            }
        } else {
            if (currentIndex > 0) {
                setCurrentIndex(currentIndex - 1)
            }
        }
    }

    const goToIndex = (index: number) => {
        if (shuffleEnabled) {
            const shuffleIdx = shuffleOrder.findIndex(i => i === index)
            if (shuffleIdx !== -1) {
                setShuffleIndex(shuffleIdx)
            }
        } else {
            setCurrentIndex(index)
        }
    }

    // Shuffle controls
    const toggleShuffle = () => {
        if (!shuffleEnabled) {
            // Turning shuffle on
            const newShuffleOrder = generateShuffleOrder(queue)
            setShuffleOrder(newShuffleOrder)
            // Find where the current song is in the new shuffle order
            const shuffleIdx = newShuffleOrder.findIndex(i => i === currentIndex)
            setShuffleIndex(shuffleIdx !== -1 ? shuffleIdx : 0)
            setShuffleEnabled(true)
        } else {
            // Turning shuffle off
            // Set currentIndex to the actual queue position of the currently playing song
            const actualCurrentIndex = shuffleOrder[shuffleIndex]
            setShuffleEnabled(false)
            setCurrentIndex(actualCurrentIndex)
            // Clear shuffle order to prevent stale data
            setShuffleOrder([])
            setShuffleIndex(0)
        }
    }

    // Loop controls
    const toggleLoop = () => {
        setLoopMode((prev) => (prev < 2 ? prev + 1 : 0))
    }

    return {
        // Playback
        load,
        play,
        pause,
        seek,
        setVolume,
        
        // Queue
        queue,
        setQueue: setQueueAndPlay,
        addToQueue,
        getCurrentSong,
        
        // Navigation
        skipNext,
        skipPrevious,
        goToIndex,
        currentIndex: getActualIndex(),
        
        // Shuffle
        shuffleEnabled,
        toggleShuffle,
        shuffleOrder,
        shuffleIndex,
        
        // Loop
        loopMode,
        toggleLoop,
        
        // State
        currentTime,
        duration,
        isPlaying,
        isLoading,
        error,
        isSeeking: isSeekingRef.current,
        
        // Raw player (for advanced use)
        player,
    }
}

export type AudioPlayer = ReturnType<typeof useAudioPlayer>
