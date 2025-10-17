import { useEffect, useState } from "react"
import { usePlayer } from "../providers/PlayerContext"

/**
 * Custom hook for components that need currentTime updates
 * This prevents components that don't need time updates from re-rendering
 * 
 * @param interval - How often to poll for time updates (in ms). Default: 500ms
 * @returns Current playback time in seconds
 */
export const usePlayerTime = () => {
    const player = usePlayer()
    const [currentTime, setCurrentTime] = useState(0)

    useEffect(() => {
        const handleTimeUpdate = () => {
            setCurrentTime(player.player.currentTime)
        }

        player.player.addEventListener('timeupdate', handleTimeUpdate)
        return () => {
            player.player.removeEventListener('timeupdate', handleTimeUpdate)
        }
    }, [player])

    return currentTime
}
