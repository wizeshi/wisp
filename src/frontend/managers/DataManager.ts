import { UserData } from "../../backend/utils/types";

class DataManager {
    private data: UserData | null = null
    private listeners: Set<(data: UserData) => void> = new Set()

    async load(): Promise<UserData> {
        this.data = await window.electronAPI.data.load()
        this.notifyListeners()
        return this.data
    }

    async save(newData: UserData): Promise<void> {
        await window.electronAPI.data.save(newData)
        this.data = newData
        this.notifyListeners()
    }

    async update(partial: Partial<UserData>) {
        const updated = { ...this.data, ...partial }
        await this.save(updated)
        return updated
    }

    getCached(): UserData | null {
        return this.data
    }

    subscribe(listener: (data: UserData) => void) {
        this.listeners.add(listener)
        return () => this.listeners.delete(listener)
    }

    private notifyListeners() {
        if (this.data) {
            this.listeners.forEach(listener => listener(this.data))
        }
    }
}

export const dataManager = new DataManager()