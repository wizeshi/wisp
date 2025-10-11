import { useEffect, useState } from "react"
import { UserData } from "../../backend/utils/types"
import { dataManager } from "../managers/DataManager"

export const useData = () => {
    const [data, setData] = useState<UserData | null>(null)
    const [loading, setLoading] = useState(true)
    const [error, setError] = useState<Error | null>(null)

    useEffect(() => {
        // Load data on mount
        dataManager.load()
            .then((loadedData) => {
                setData(loadedData)
                setLoading(false)
            })
            .catch((err) => {
                setError(err)
                setLoading(false)
            })

        // Subscribe to data changes
        const unsubscribe = dataManager.subscribe((updatedData) => {
            setData(updatedData)
        })

        return () => {
            unsubscribe()
        }
    }, [])

    const updateData = async (partial: Partial<UserData>) => {
        try {
            const updated = await dataManager.update(partial)
            return updated
        } catch (err) {
            setError(err as Error)
            throw err
        }
    }

    return {
        data,
        loading,
        error,
        updateData
    }
}
