import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { randomUUID } from 'node:crypto'
// eslint-disable-next-line import/no-unresolved
import * as mm from 'music-metadata'
import { GenericAlbum, GenericArtist, GenericPlaylist, GenericSong, GenericSimpleAlbum, GenericSimpleArtist, SongSources, SongSourcesList } from '../common/types/SongTypes'

class LocalManager {
    private baseCacheDir: string
    private audioDir: string

    constructor() {
        this.baseCacheDir = path.join(app.getPath('userData'), 'Cache', 'Data')
        this.audioDir = path.join(app.getPath('userData'), 'Cache', 'Downloads', 'Songs')
    }

    // Helper methods to get paths organized by type and source
    private getSongPath(source: SongSources): string {
        return path.join(this.baseCacheDir, 'Songs', source)
    }

    private getArtistPath(source: SongSources): string {
        return path.join(this.baseCacheDir, 'Artists', source)
    }

    private getAlbumPath(source: SongSources): string {
        return path.join(this.baseCacheDir, 'Albums', source)
    }

    private getPlaylistPath(source: SongSources): string {
        return path.join(this.baseCacheDir, 'Playlists', source)
    }

    private getAudioSourcePath(source: SongSources): string {
        return path.join(this.audioDir, source)
    }

    // ===== Song Methods =====
    async saveSong(song: GenericSong): Promise<boolean> {
        const songsPath = this.getSongPath(song.source);

        if (!fs.existsSync(songsPath)) {
            await fs.promises.mkdir(songsPath, { recursive: true });
        }

        const songFilePath = path.join(songsPath, `${song.id}.json`);
        await fs.promises.writeFile(songFilePath, JSON.stringify(song, null, 2), 'utf-8');
        return true;
    }

    async loadSong(id: string, source: SongSources): Promise<GenericSong | null> {
        const songPath = path.join(this.getSongPath(source), `${id}.json`);
        if (fs.existsSync(songPath)) {
            const data = await fs.promises.readFile(songPath, 'utf-8');
            return JSON.parse(data) as GenericSong;
        }

        return null;
    }

    async deleteSong(id: string, source: SongSources): Promise<boolean> {
        const songPath = path.join(this.getSongPath(source), `${id}.json`);
        if (fs.existsSync(songPath)) {
            fs.unlinkSync(songPath);
            return true;
        }
        return false;
    }

    // ===== Playlist Methods =====
    async savePlaylist(playlist: GenericPlaylist): Promise<boolean> {
        const playlistDir = this.getPlaylistPath(playlist.source);
        if (!fs.existsSync(playlistDir)) {
            await fs.promises.mkdir(playlistDir, { recursive: true });
        }

        const playlistFilePath = path.join(playlistDir, `${playlist.id}.json`);
        await fs.promises.writeFile(playlistFilePath, JSON.stringify(playlist, null, 2), 'utf-8');
        return true;
    }

    async loadPlaylist(id: string, source: SongSources): Promise<GenericPlaylist | null> {
        const playlistFilePath = path.join(this.getPlaylistPath(source), `${id}.json`);
        if (fs.existsSync(playlistFilePath)) {
            const data = await fs.promises.readFile(playlistFilePath, 'utf-8');
            return JSON.parse(data) as GenericPlaylist;
        }
        return null;
    }

    async loadAllPlaylists(): Promise<GenericPlaylist[]> {
        const playlists: GenericPlaylist[] = [];

        for (const src of SongSourcesList) {
            const playlistDir = this.getPlaylistPath(src);
            if (!fs.existsSync(playlistDir)) {
                continue;
            }

            const files = await fs.promises.readdir(playlistDir);
            for (const file of files) {
                if (file.endsWith('.json')) {
                    const filePath = path.join(playlistDir, file);
                    const data = await fs.promises.readFile(filePath, 'utf-8');
                    const playlist = JSON.parse(data) as GenericPlaylist;
                    playlists.push(playlist);
                }
            }
        }

        return playlists;
    }

    async deletePlaylist(id: string, source: SongSources): Promise<boolean> {
        const playlistPath = path.join(this.getPlaylistPath(source), `${id}.json`);
        if (fs.existsSync(playlistPath)) {
            fs.unlinkSync(playlistPath);
            return true;
        }

        return false;
    }
    
    async saveAlbum(album: GenericAlbum): Promise<boolean> {
        if (!fs.existsSync(this.getArtistPath(album.source))) {
            await fs.promises.mkdir(this.getAlbumPath(album.source), { recursive: true });
        }

        const albumPath = path.join(this.getAlbumPath(album.source), `${album.id}.json`);
        await fs.promises.writeFile(albumPath, JSON.stringify(album, null, 2), 'utf-8');
        return true;
    }

    async loadAlbum(id: string, source: SongSources): Promise<GenericAlbum | null> {
        const albumPath = path.join(this.getAlbumPath(source), `${id}.json`);
        if (fs.existsSync(albumPath)) {
            const data = await fs.promises.readFile(albumPath, 'utf-8');
            return JSON.parse(data) as GenericAlbum;
        }
        return null;
    }

    async loadAllAlbums(): Promise<GenericAlbum[]> | null {
        const albums: GenericAlbum[] = [];

        for (const src of SongSourcesList) {
            const albumDir = this.getAlbumPath(src);
            if (!fs.existsSync(albumDir)) {
                continue;
            }

            const files = await fs.promises.readdir(albumDir);
            for (const file of files) {
                if (file.endsWith('.json')) {
                    const filePath = path.join(albumDir, file);
                    const data = await fs.promises.readFile(filePath, 'utf-8');
                    const album = JSON.parse(data) as GenericAlbum;
                    albums.push(album);
                }
            }
        }

        return albums;
    }

    async deleteAlbum(id: string, source: SongSources): Promise<boolean> {
        const albumPath = path.join(this.getAlbumPath(source), `${id}.json`);
        if (fs.existsSync(albumPath)) {
            fs.unlinkSync(albumPath);
            return true;
        }

        return false;
    }
    async saveArtist(artist: GenericArtist): Promise<boolean> {
        if (!fs.existsSync(this.getArtistPath(artist.source))) {
            await fs.promises.mkdir(this.getArtistPath(artist.source), { recursive: true });
        }

        const artistPath = path.join(this.getArtistPath(artist.source), `${artist.id}.json`);
        await fs.promises.writeFile(artistPath, JSON.stringify(artist, null, 2), 'utf-8');
        return true;
    }

    async loadArtist(id: string, source: SongSources): Promise<GenericArtist | null> {
        const artistPath = path.join(this.getArtistPath(source), `${id}.json`);
        if (fs.existsSync(artistPath)) {
            const data = await fs.promises.readFile(artistPath, 'utf-8');
            return JSON.parse(data) as GenericArtist;
        }
        return null;
    }

    async loadAllArtists(): Promise<GenericArtist[]> | null {
        const artists: GenericArtist[] = [];

        for (const src of SongSourcesList) {
            const artistDir = this.getArtistPath(src);
            if (!fs.existsSync(artistDir)) {
                continue;
            }

            const files = await fs.promises.readdir(artistDir);
            for (const file of files) {
                if (file.endsWith('.json')) {
                    const filePath = path.join(artistDir, file);
                    const data = await fs.promises.readFile(filePath, 'utf-8');
                    const artist = JSON.parse(data) as GenericArtist;
                    artists.push(artist);
                }
            }
        }

        return artists;
    }

    async deleteArtist(id: string, source: SongSources): Promise<boolean> {
        const artistPath = path.join(this.getArtistPath(source), `${id}.json`);
        if (fs.existsSync(artistPath)) {
            fs.unlinkSync(artistPath);
            return true;
        }

        return false;
    }

    // ===== Audio File Methods =====
    /**
     * Import a local audio file with metadata extraction
     * Copies the file, extracts metadata, and creates a GenericSong
     * @param originalPath - The original file path on the user's computer
     * @returns The created GenericSong object
     */
    async importLocalAudioFileWithMetadata(originalPath: string): Promise<GenericSong> {
        // Generate unique ID for this song
        const songId = randomUUID()
        const extension = path.extname(originalPath).slice(1)
        
        // Copy the audio file to managed storage
        const audioSourceDir = this.getAudioSourcePath('local')
        if (!fs.existsSync(audioSourceDir)) {
            await fs.promises.mkdir(audioSourceDir, { recursive: true })
        }

        const audioFilePath = path.join(audioSourceDir, `${songId}.${extension}`)
        await fs.promises.copyFile(originalPath, audioFilePath)

        // Extract metadata from the audio file
        const metadata = await mm.parseFile(originalPath)
        
        // Get basic info with fallbacks
        const title = metadata.common.title || path.basename(originalPath, path.extname(originalPath))
        const artistName = metadata.common.artist || 'Unknown Artist'
        const albumTitle = metadata.common.album
        const duration = metadata.format.duration || 0
        const year = metadata.common.year
        
        // Create artist object
        const artist = new GenericSimpleArtist(
            `${artistName.toLowerCase().replace(/\s+/g, '-')}`,
            'local',
            artistName,
            '' // No thumbnail for local
        )

        // Create album object if available
        let album: GenericSimpleAlbum | undefined
        if (albumTitle) {
            album = new GenericSimpleAlbum(
                `${albumTitle.toLowerCase().replace(/\s+/g, '-')}`,
                'local',
                albumTitle,
                '', // No thumbnail
                [artist],
                year ? new Date(year, 0, 1) : new Date(),
                'Local'
            )
        }

        // Extract album art as base64 if available
        let thumbnailURL = ''
        if (metadata.common.picture && metadata.common.picture.length > 0) {
            const picture = metadata.common.picture[0]
            const base64 = Buffer.from(picture.data).toString('base64')
            thumbnailURL = `data:${picture.format};base64,${base64}`
        }

        // Create the GenericSong object
        const song = new GenericSong(
            title,
            [artist],
            false, // explicit
            duration,
            'local',
            songId,
            thumbnailURL,
            album
        )

        // Save the song metadata
        await this.saveSong(song)

        return song
    }

    /**
     * Import a local audio file into wisp's managed storage (without metadata extraction)
     * Copies the file from its original location
     * @param originalPath - The original file path on the user's computer
     * @param id - The song ID to save it as
     * @returns The new managed file path
     */
    async importLocalAudioFile(originalPath: string, id: string): Promise<string> {
        const extension = path.extname(originalPath).slice(1); // Remove the dot
        const audioSourceDir = this.getAudioSourcePath('local');
        
        if (!fs.existsSync(audioSourceDir)) {
            await fs.promises.mkdir(audioSourceDir, { recursive: true });
        }

        const audioFilePath = path.join(audioSourceDir, `${id}.${extension}`);
        await fs.promises.copyFile(originalPath, audioFilePath);
        return audioFilePath;
    }

    /**
     * Save an audio file from a buffer (for downloaded songs)
     * @param id - The song ID
     * @param source - The source of the song
     * @param audioBuffer - The audio file data as a buffer
     * @param extension - File extension (default: 'ogg')
     */
    async saveAudioFile(id: string, source: SongSources, audioBuffer: Buffer, extension = 'ogg'): Promise<string> {
        const audioSourceDir = this.getAudioSourcePath(source);
        if (!fs.existsSync(audioSourceDir)) {
            await fs.promises.mkdir(audioSourceDir, { recursive: true });
        }

        const audioFilePath = path.join(audioSourceDir, `${id}.${extension}`);
        await fs.promises.writeFile(audioFilePath, audioBuffer);
        return audioFilePath;
    }

    /**
     * Get the path to a local audio file
     * @param id - The song ID
     * @returns The file path if it exists, null otherwise
     */
    async getLocalAudioPath(id: string): Promise<string | null> {
        const audioDir = this.getAudioSourcePath('local');
        if (!fs.existsSync(audioDir)) {
            return null;
        }

        // Find the file with matching ID (any extension)
        const files = await fs.promises.readdir(audioDir);
        const matchingFile = files.find(file => file.startsWith(`${id}.`));
        
        if (matchingFile) {
            return path.join(audioDir, matchingFile);
        }
        
        return null;
    }

    /**
     * Delete a local audio file and its metadata
     * @param id - The song ID
     */
    async deleteLocalSong(id: string): Promise<boolean> {
        // Delete the audio file
        const audioPath = await this.getLocalAudioPath(id);
        if (audioPath && fs.existsSync(audioPath)) {
            await fs.promises.unlink(audioPath);
        }

        // Delete the metadata
        return await this.deleteSong(id, 'local');
    }

    /**
     * Get all local songs (metadata only)
     */
    async getAllLocalSongs(): Promise<GenericSong[]> {
        const songsDir = this.getSongPath('local');
        if (!fs.existsSync(songsDir)) {
            return [];
        }

        const files = await fs.promises.readdir(songsDir);
        const songs: GenericSong[] = [];

        for (const file of files) {
            if (file.endsWith('.json')) {
                const filePath = path.join(songsDir, file);
                const data = await fs.promises.readFile(filePath, 'utf-8');
                const song = JSON.parse(data) as GenericSong;
                songs.push(song);
            }
        }

        return songs;
    }
}

export const localManager = new LocalManager()