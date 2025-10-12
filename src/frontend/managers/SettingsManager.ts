import { UserSettings } from "../../backend/utils/types";

class SettingsManager {
    private settings: UserSettings | null = null
    private listeners: Set<(settings: UserSettings) => void> = new Set()

    async load(): Promise<UserSettings> {
        this.settings = await window.electronAPI.info.settings.load()
        this.notifyListeners()
        return this.settings
    }

    async save(newSettings: UserSettings): Promise<void> {
        await window.electronAPI.info.settings.save(newSettings)
        this.settings = newSettings
        this.notifyListeners()
    }

    async update(partial: Partial<UserSettings>) {
        const updated = { ...this.settings, ...partial }
        await this.save(updated)
        return updated
    }

    getCached(): UserSettings | null {
        return this.settings
    }

    subscribe(listener: (settings: UserSettings) => void) {
        this.listeners.add(listener)
        return () => this.listeners.delete(listener)
    }

    private notifyListeners() {
        if (this.settings) {
            this.listeners.forEach(listener => listener(this.settings))
        }
    }
}

export const settingsManager = new SettingsManager()