import fs from "node:fs"
import path from "node:path"
import { app } from "electron"
import { ShuffleType, UserSettings } from "./utils/types"

const settingsPath = path.join(app.getPath('userData'), 'userSettings.json')


const defaultSettings: UserSettings = {
    shuffleType: "Fisher-Yates"
}

export const loadSettings = async (): Promise<UserSettings> => {
    try {
        const data = await fs.promises.readFile(settingsPath, "utf-8")
        const settings = JSON.parse(data) as UserSettings
        
        // Merge with defaults in case new settings were added
        return { ...defaultSettings, ...settings }
    } catch (err) {
        // File doesn't exist or is invalid, return defaults and create file
        console.log("Settings file not found, creating with defaults")
        await saveSettings(defaultSettings)
        return defaultSettings
    }
}

export const saveSettings = async (settings: UserSettings): Promise<void> => {
    try {
        await fs.promises.writeFile(settingsPath, JSON.stringify(settings, null, 2), "utf8")
    } catch (err) {
        console.error("Error saving settings:", err)
        throw err
    }
}