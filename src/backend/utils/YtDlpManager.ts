import { app } from 'electron'
import fs from 'node:fs'
import path from 'node:path'
import https from 'node:https'
import { spawn } from 'node:child_process'

const YT_DLP_URLS: Record<string, string> = {
    win32: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe',
    darwin: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos',
    linux: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp'
}

const FFMPEG_URLS: Record<string, string> = {
    win32: 'https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-win32-x64',
    darwin: 'https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-darwin-x64',
    linux: 'https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-linux-x64'
}

class YtDlpManager {
    private ytDlpPath: string
    private ffmpegPath: string
    private ytDlpDir: string
    private platform: NodeJS.Platform

    constructor() {
        this.platform = process.platform
        this.ytDlpDir = path.join(app.getPath('userData'), 'bin')
        
        // Set the correct filenames based on platform
        const ytDlpFilename = this.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp'
        const ffmpegFilename = this.platform === 'win32' ? 'ffmpeg.exe' : 'ffmpeg'
        
        this.ytDlpPath = path.join(this.ytDlpDir, ytDlpFilename)
        this.ffmpegPath = path.join(this.ytDlpDir, ffmpegFilename)
    }

    /**
     * Ensures yt-dlp is available, downloading it if necessary
     */
    async ensureYtDlp(): Promise<string> {
        if (fs.existsSync(this.ytDlpPath)) {
            const stats = fs.statSync(this.ytDlpPath)
            
            if (stats.size < 1000000) {
                console.log('Existing yt-dlp file is too small, re-downloading...')
                fs.unlinkSync(this.ytDlpPath)
            } else {
                // Verify it's executable (for Unix-like systems)
                if (this.platform !== 'win32') {
                    try {
                        fs.chmodSync(this.ytDlpPath, 0o755)
                    } catch (err) {
                        console.error('Failed to set executable permissions:', err)
                    }
                }
                
                // Verify it actually works
                const works = await this.verifyYtDlp()
                if (works) {
                    return this.ytDlpPath
                } else {
                    console.log('Existing yt-dlp failed verification, re-downloading...')
                    fs.unlinkSync(this.ytDlpPath)
                }
            }
        }

        console.log('yt-dlp not found, downloading...')
        await this.downloadYtDlp()
        
        // Verify the download worked
        const works = await this.verifyYtDlp()
        if (!works) {
            throw new Error('Downloaded yt-dlp failed verification')
        }
        
        return this.ytDlpPath
    }

    /**
     * Verifies that yt-dlp is working by running --version
     */
    private async verifyYtDlp(): Promise<boolean> {
        return new Promise((resolve) => {
            try {
                const child = spawn(this.ytDlpPath, ['--version'])
                let output = ''
                
                child.stdout.on('data', (data) => {
                    output += data.toString()
                })
                
                child.on('close', (code) => {
                    if (code === 0 && output.length > 0) {
                        console.log(`yt-dlp version: ${output.trim()}`)
                        resolve(true)
                    } else {
                        resolve(false)
                    }
                })
                
                child.on('error', () => {
                    resolve(false)
                })
                
                // Timeout after 5 seconds
                setTimeout(() => {
                    child.kill()
                    resolve(false)
                }, 5000)
            } catch (err) {
                resolve(false)
            }
        })
    }

    /**
     * Downloads yt-dlp from GitHub releases
     */
    private async downloadYtDlp(): Promise<void> {
        // Create bin directory if it doesn't exist
        if (!fs.existsSync(this.ytDlpDir)) {
            fs.mkdirSync(this.ytDlpDir, { recursive: true })
        }

        const url = YT_DLP_URLS[this.platform]
        if (!url) {
            throw new Error(`Unsupported platform: ${this.platform}`)
        }

        return new Promise((resolve, reject) => {
            this.downloadFromUrl(url, resolve, reject)
        })
    }

    /**
     * Recursively handles redirects and downloads
     */
    private downloadFromUrl(
        url: string,
        resolve: () => void,
        reject: (err: Error) => void,
        redirectCount = 0
    ): void {
        if (redirectCount > 5) {
            reject(new Error('Too many redirects'))
            return
        }

        https.get(url, (response) => {
            if (response.statusCode === 301 || response.statusCode === 302 || response.statusCode === 303 || response.statusCode === 307 || response.statusCode === 308) {
                const redirectUrl = response.headers.location
                if (redirectUrl) {
                    console.log(`Following redirect to: ${redirectUrl}`)
                    this.downloadFromUrl(redirectUrl, resolve, reject, redirectCount + 1)
                } else {
                    reject(new Error('Redirect with no location header'))
                }
                return
            }

            if (response.statusCode !== 200) {
                reject(new Error(`Failed to download yt-dlp: ${response.statusCode} ${response.statusMessage}`))
                return
            }

            this.saveYtDlp(response, resolve, reject)
        }).on('error', reject)
    }

    /**
     * Saves the downloaded yt-dlp binary
     */
    private saveYtDlp(
        response: NodeJS.ReadableStream,
        resolve: () => void,
        reject: (err: Error) => void
    ): void {
        const fileStream = fs.createWriteStream(this.ytDlpPath, { mode: 0o755 })
        let downloadedBytes = 0
        
        response.on('data', (chunk) => {
            downloadedBytes += chunk.length
        })

        response.pipe(fileStream)

        fileStream.on('finish', () => {
            fileStream.close(() => {
                console.log(`yt-dlp downloaded successfully (${downloadedBytes} bytes)`)
                
                // Verify file size (yt-dlp should be at least 1MB)
                if (downloadedBytes < 1000000) {
                    fs.unlink(this.ytDlpPath, () => {})
                    reject(new Error(`Downloaded file too small (${downloadedBytes} bytes). Download may be corrupted.`))
                    return
                }
                
                // Make executable on Unix-like systems
                if (this.platform !== 'win32') {
                    try {
                        fs.chmodSync(this.ytDlpPath, 0o755)
                    } catch (err) {
                        reject(new Error(`Failed to set executable permissions: ${err}`))
                        return
                    }
                }
                
                resolve()
            })
        })

        fileStream.on('error', (err) => {
            fs.unlink(this.ytDlpPath, () => {}) // Clean up partial file
            reject(err)
        })

        response.on('error', (err) => {
            fileStream.close()
            fs.unlink(this.ytDlpPath, () => {})
            reject(err)
        })
    }

    /**
     * Gets the path to the yt-dlp executable
     */
    getYtDlpPath(): string {
        return this.ytDlpPath
    }

    /**
     * Checks if yt-dlp is available (either system or bundled)
     */
    async isAvailable(): Promise<boolean> {
        if (fs.existsSync(this.ytDlpPath)) {
            return true
        }

        // Check if yt-dlp is in system PATH
        return new Promise((resolve) => {
            const testCommand = this.platform === 'win32' ? 'where yt-dlp' : 'which yt-dlp'
            const shell = this.platform === 'win32' ? 'cmd.exe' : '/bin/sh'
            const args = this.platform === 'win32' ? ['/c', testCommand] : ['-c', testCommand]

            const child = spawn(shell, args)
            child.on('close', (code) => {
                resolve(code === 0)
            })
            child.on('error', () => {
                resolve(false)
            })
        })
    }

    /**
     * Updates yt-dlp to the latest version
     */
    async update(): Promise<void> {
        console.log('Updating yt-dlp...')
        
        if (fs.existsSync(this.ytDlpPath)) {
            fs.unlinkSync(this.ytDlpPath)
        }

        await this.downloadYtDlp()
        
        // Verify the download worked
        const works = await this.verifyYtDlp()
        if (!works) {
            throw new Error('Updated yt-dlp failed verification')
        }
    }

    /**
     * Force re-download yt-dlp (useful for fixing corrupted downloads)
     */
    async forceRedownload(): Promise<string> {
        console.log('Force re-downloading yt-dlp...')
        
        // Delete existing file
        if (fs.existsSync(this.ytDlpPath)) {
            fs.unlinkSync(this.ytDlpPath)
        }

        // Download new version
        await this.downloadYtDlp()
        
        // Verify the download worked
        const works = await this.verifyYtDlp()
        if (!works) {
            throw new Error('Re-downloaded yt-dlp failed verification')
        }
        
        return this.ytDlpPath
    }

    /**
     * Ensures ffmpeg is available, downloading it if necessary
     */
    async ensureFfmpeg(): Promise<string> {
        // Check if ffmpeg already exists and is valid
        if (fs.existsSync(this.ffmpegPath)) {
            const stats = fs.statSync(this.ffmpegPath)
            
            // Verify file size is reasonable (ffmpeg should be > 10MB)
            if (stats.size < 10000000) {
                console.log('Existing ffmpeg file is too small, re-downloading...')
                fs.unlinkSync(this.ffmpegPath)
            } else {
                // Verify it's executable (for Unix-like systems)
                if (this.platform !== 'win32') {
                    try {
                        fs.chmodSync(this.ffmpegPath, 0o755)
                    } catch (err) {
                        console.error('Failed to set executable permissions:', err)
                    }
                }
                
                // Verify it actually works
                const works = await this.verifyFfmpeg()
                if (works) {
                    return this.ffmpegPath
                } else {
                    console.log('Existing ffmpeg failed verification, re-downloading...')
                    fs.unlinkSync(this.ffmpegPath)
                }
            }
        }

        // Download ffmpeg
        console.log('ffmpeg not found, downloading...')
        await this.downloadFfmpeg()
        
        // Verify the download worked
        const works = await this.verifyFfmpeg()
        if (!works) {
            throw new Error('Downloaded ffmpeg failed verification')
        }
        
        return this.ffmpegPath
    }

    /**
     * Downloads ffmpeg from GitHub releases
     */
    private async downloadFfmpeg(): Promise<void> {
        // Create bin directory if it doesn't exist
        if (!fs.existsSync(this.ytDlpDir)) {
            fs.mkdirSync(this.ytDlpDir, { recursive: true })
        }

        const url = FFMPEG_URLS[this.platform]
        if (!url) {
            throw new Error(`Unsupported platform for ffmpeg: ${this.platform}`)
        }

        return new Promise((resolve, reject) => {
            this.downloadBinary(url, this.ffmpegPath, 'ffmpeg', resolve, reject)
        })
    }

    /**
     * Verifies that ffmpeg is working by running -version
     */
    private async verifyFfmpeg(): Promise<boolean> {
        return new Promise((resolve) => {
            try {
                const child = spawn(this.ffmpegPath, ['-version'])
                let output = ''
                
                child.stdout.on('data', (data) => {
                    output += data.toString()
                })
                
                child.on('close', (code) => {
                    if (code === 0 && output.includes('ffmpeg version')) {
                        const versionMatch = output.match(/ffmpeg version ([\d.]+)/)
                        const version = versionMatch ? versionMatch[1] : 'unknown'
                        console.log(`ffmpeg version: ${version}`)
                        resolve(true)
                    } else {
                        resolve(false)
                    }
                })
                
                child.on('error', () => {
                    resolve(false)
                })
                
                // Timeout after 5 seconds
                setTimeout(() => {
                    child.kill()
                    resolve(false)
                }, 5000)
            } catch (err) {
                resolve(false)
            }
        })
    }

    /**
     * Generic binary downloader
     */
    private downloadBinary(
        url: string,
        destPath: string,
        name: string,
        resolve: () => void,
        reject: (err: Error) => void,
        redirectCount = 0
    ): void {
        if (redirectCount > 5) {
            reject(new Error('Too many redirects'))
            return
        }

        https.get(url, (response) => {
            // Handle redirects
            if (response.statusCode === 301 || response.statusCode === 302 || response.statusCode === 303 || response.statusCode === 307 || response.statusCode === 308) {
                const redirectUrl = response.headers.location
                if (redirectUrl) {
                    console.log(`Following redirect to: ${redirectUrl}`)
                    this.downloadBinary(redirectUrl, destPath, name, resolve, reject, redirectCount + 1)
                } else {
                    reject(new Error('Redirect with no location header'))
                }
                return
            }

            if (response.statusCode !== 200) {
                reject(new Error(`Failed to download ${name}: ${response.statusCode} ${response.statusMessage}`))
                return
            }

            this.saveBinary(response, destPath, name, resolve, reject)
        }).on('error', reject)
    }

    /**
     * Saves a downloaded binary
     */
    private saveBinary(
        response: NodeJS.ReadableStream,
        destPath: string,
        name: string,
        resolve: () => void,
        reject: (err: Error) => void
    ): void {
        const fileStream = fs.createWriteStream(destPath, { mode: 0o755 })
        let downloadedBytes = 0
        
        response.on('data', (chunk) => {
            downloadedBytes += chunk.length
        })

        response.pipe(fileStream)

        fileStream.on('finish', () => {
            fileStream.close(() => {
                console.log(`${name} downloaded successfully (${downloadedBytes} bytes)`)
                
                // Make executable on Unix-like systems
                if (this.platform !== 'win32') {
                    try {
                        fs.chmodSync(destPath, 0o755)
                    } catch (err) {
                        reject(new Error(`Failed to set executable permissions: ${err}`))
                        return
                    }
                }
                
                resolve()
            })
        })

        fileStream.on('error', (err) => {
            fs.unlink(destPath, () => {}) // Clean up partial file
            reject(err)
        })

        response.on('error', (err) => {
            fileStream.close()
            fs.unlink(destPath, () => {})
            reject(err)
        })
    }

    /**
     * Gets the path to the ffmpeg executable
     */
    getFfmpegPath(): string {
        return this.ffmpegPath
    }

    /**
     * Gets the bin directory path
     */
    getBinDir(): string {
        return this.ytDlpDir
    }

    /**
     * Ensures both yt-dlp and ffmpeg are available
     */
    async ensureBoth(): Promise<{ ytDlpPath: string; ffmpegPath: string }> {
        const ytDlpPath = await this.ensureYtDlp()
        const ffmpegPath = await this.ensureFfmpeg()
        
        return { ytDlpPath, ffmpegPath }
    }
}

// Export singleton instance
export const ytDlpManager = new YtDlpManager()
