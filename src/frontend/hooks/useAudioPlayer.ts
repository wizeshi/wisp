import { useEffect, useRef, useState } from "react"

export const useAudioPlayer = () => {
    const audioRef = useRef(new Audio())
    const player = audioRef.current
    const [currentTime, setCurrentTime] = useState(0)
    const [duration, setDuration] = useState(0)
    const [isPlaying, setIsPlaying] = useState(false)
    const [isLoading, setIsLoading] = useState(false)
    const [error, setError] = useState<string | null>(null)

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
        player.currentTime = seekTo
    }

    const setVolume = (newVol: number) => {
        player.volume = newVol / 100
    }

    return {
        load,
        play,
        pause,
        seek,
        setVolume,
        currentTime,
        isPlaying,
        duration,
        isLoading,
        error,
        player,
    }
}

export type AudioPlayer = ReturnType<typeof useAudioPlayer>