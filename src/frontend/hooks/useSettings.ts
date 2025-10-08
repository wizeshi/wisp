import { useEffect, useState } from "react"
import { UserSettings } from "../../backend/utils/types"
import { settingsManager } from "../utils/SettingsManager"

export const useSettings = () => {
    const [settings, setSettings] = useState<UserSettings | null>(null)
    const [loading, setLoading] = useState(true)
    const [error, setError] = useState<Error | null>(null)

    useEffect(() => {
        // Load settings on mount
        settingsManager.load()
            .then((loadedSettings) => {
                setSettings(loadedSettings)
                setLoading(false)
            })
            .catch((err) => {
                setError(err)
                setLoading(false)
            })

        // Subscribe to settings changes
        const unsubscribe = settingsManager.subscribe((updatedSettings) => {
            setSettings(updatedSettings)
        })

        return () => {
            unsubscribe()
        }
    }, [])

    const updateSettings = async (partial: Partial<UserSettings>) => {
        try {
            const updated = await settingsManager.update(partial)
            return updated
        } catch (err) {
            setError(err as Error)
            throw err
        }
    }

    return {
        settings,
        loading,
        error,
        updateSettings
    }
}
