import fs from "node:fs"
import path from "node:path"
import { app, safeStorage } from "electron"
import { APICredentials } from "./utils/types"

const credentialsPath = path.join(app.getPath('userData'), 'api_credentials.enc')

/**
 * Save API credentials securely using Electron's safeStorage
 */
export const saveCredentials = async (credentials: APICredentials): Promise<void> => {
    try {
        if (!safeStorage.isEncryptionAvailable()) {
            console.warn("Encryption not available, storing in plain text (NOT RECOMMENDED)")
            await fs.promises.writeFile(
                credentialsPath.replace('.enc', '.json'),
                JSON.stringify(credentials, null, 2),
                "utf8"
            )
            return
        }

        const encrypted = safeStorage.encryptString(JSON.stringify(credentials))
        await fs.promises.writeFile(credentialsPath, encrypted)
        console.log("Credentials saved securely")
    } catch (err) {
        console.error("Error saving credentials:", err)
        throw err
    }
}

/**
 * Load API credentials from secure storage
 */
export const loadCredentials = async (): Promise<APICredentials | null> => {
    try {
        if (fs.existsSync(credentialsPath)) {
            const encrypted = await fs.promises.readFile(credentialsPath)
            const decrypted = safeStorage.decryptString(encrypted)
            return JSON.parse(decrypted) as APICredentials
        }

        const plainTextPath = credentialsPath.replace('.enc', '.json')
        if (fs.existsSync(plainTextPath)) {
            const data = await fs.promises.readFile(plainTextPath, "utf-8")
            return JSON.parse(data) as APICredentials
        }

        return null
    } catch (err) {
        console.error("Error loading credentials:", err)
        return null
    }
}

/**
 * Check if credentials exist
 */
export const hasCredentials = (): boolean => {
    return fs.existsSync(credentialsPath) || 
           fs.existsSync(credentialsPath.replace('.enc', '.json'))
}

/**
 * Validate credentials format (basic validation)
 */
export const validateCredentials = (credentials: Partial<APICredentials>): boolean => {
    return Boolean(
        credentials.spotifyClientId?.trim() &&
        credentials.spotifyClientSecret?.trim() &&
        credentials.youtubeClientId?.trim() &&
        credentials.youtubeClientSecret?.trim()
    )
}

/**
 * Delete stored credentials
 */
export const deleteCredentials = async (): Promise<void> => {
    try {
        if (fs.existsSync(credentialsPath)) {
            await fs.promises.unlink(credentialsPath)
        }
        const plainTextPath = credentialsPath.replace('.enc', '.json')
        if (fs.existsSync(plainTextPath)) {
            await fs.promises.unlink(plainTextPath)
        }
        console.log("Credentials deleted")
    } catch (err) {
        console.error("Error deleting credentials:", err)
        throw err
    }
}
