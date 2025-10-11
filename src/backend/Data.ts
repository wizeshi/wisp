import fs from "node:fs"
import path from "node:path"
import { app } from "electron"
import { UserData, UserSettings } from "./utils/types"
import { LoopingEnum } from "../frontend/types/SongTypes"

const dataPath = path.join(app.getPath('userData'), 'userData.json')

const defaultSettings: UserData = {
    lastPlayed: undefined,
    preferredVolume: 10,
    looped: LoopingEnum.Off,
    shuffled: false,
    isNewUser: true,
}

export const loadData = async (): Promise<UserData> => {
    try {
        const data = await fs.promises.readFile(dataPath, "utf-8")
        const settings = JSON.parse(data) as UserData
        
        return { ...defaultSettings, ...settings }
    } catch (err) {
        console.log("Data file not found, creating with defaults")
        await saveData(defaultSettings)
        return defaultSettings
    }
}

export const saveData = async (data: UserData): Promise<void> => {
    try {
        await fs.promises.writeFile(dataPath, JSON.stringify(data, null, 2), "utf8")
    } catch (err) {
        console.error("Error saving data:", err)
        throw err
    }
}