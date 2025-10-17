
import React, { createContext, useContext, useMemo, useEffect, useRef, useState, Profiler } from "react";
import { useAudioPlayer, AudioPlayer } from "../hooks/useAudioPlayer";
import { useDownloadManager, DownloadManager } from "../hooks/useDownloadManager";
import { useData } from "../hooks/useData";
import { GenericSong } from "../../common/types/SongTypes";

export type PlayerContextType = AudioPlayer & {
    downloads: DownloadManager;
    isDownloading: boolean;
};

const PlayerContext = createContext<PlayerContextType | undefined>(undefined);

export const usePlayer = () => {
    const ctx = useContext(PlayerContext);
    if (!ctx) throw new Error("usePlayer must be used within a PlayerProvider!");
    return ctx;
};

export const PlayerProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const player = useAudioPlayer();
    const downloadManager = useDownloadManager();
    const { data, loading, updateData } = useData();

    const [songLoading, setSongLoading] = useState(false);
    const lastLoadedPathRef = useRef<string>("");
    const lastPlayedSongRef = useRef<GenericSong | null>(null);

    // Load saved data on mount
    useEffect(() => {
        if (!loading) {
            if (data.lastPlayed) {
                const index = player.addToQueue(data.lastPlayed);
                player.goToIndex(index);
                let i = 1;
                const playEventListener = () => {
                    if (i >= 1) {
                        player.pause();
                        i--;
                    }
                };
                player.player.addEventListener('play', playEventListener);
                return () => {
                    player.player.removeEventListener('play', playEventListener);
                };
            }
        }
    }, [loading]);

    // Handle song changes and downloads
    useEffect(() => {
        const currentSong = player.getCurrentSong();
        if (!currentSong) return;
        // Check if this is actually the same song (by ID)
        const isSameSong = lastPlayedSongRef.current?.id === currentSong.id;
        if (isSameSong) return;
        // Update refs to track this new song
        lastPlayedSongRef.current = currentSong;
        // Handle local songs differently - they don't need to be downloaded
        if (currentSong.source === 'local') {
            window.electronAPI.local.getAudioPath(currentSong.id).then(localPath => {
                if (localPath) {
                    const audioPath = `wisp-audio://${localPath}`;
                    if (lastLoadedPathRef.current !== audioPath) {
                        lastLoadedPathRef.current = audioPath;
                        player.load(audioPath);
                        player.play();
                    }
                    setSongLoading(false);
                } else {
                    setSongLoading(false);
                }
            }).catch(() => {
                setSongLoading(false);
            });
        } else {
            // For non-local songs, use the download manager
            const downloadId = downloadManager.requestDownload(currentSong);
            if (downloadManager.hasDownloaded(downloadId)) {
                const path = downloadManager.getDownloadPath(downloadId);
                if (path) {
                    const audioPath = `wisp-audio://${path}`;
                    if (lastLoadedPathRef.current !== audioPath) {
                        lastLoadedPathRef.current = audioPath;
                        player.load(audioPath);
                        player.play();
                    }
                    setSongLoading(false);
                }
            } else {
                setSongLoading(true);
            }
        }
        // Preload next songs in queue (skip local songs as they're already cached)
        const queue = player.queue;
        const upcomingCount = Math.min(3, queue.length - player.currentIndex - 1);
        for (let i = 1; i <= upcomingCount; i++) {
            const nextSong = queue[player.currentIndex + i];
            if (nextSong && nextSong.source !== 'local') {
                downloadManager.requestDownload(nextSong);
            }
        }
    }, [player.currentIndex]);

    // Monitor download status of current song
    useEffect(() => {
        if (player.isSeeking) return;
        const currentSong = player.getCurrentSong();
        if (!currentSong) return;
        if (currentSong.source === 'local') return;
        const artists = currentSong.artists.map(a => a.name).join(", ");
        const downloadId = `${currentSong.title} - ${artists}`;
        const status = downloadManager.getDownloadStatus(downloadId);
        if (!status) return;
        if (status.status === 'downloading' || status.status === 'pending') {
            if (!songLoading) {
                setSongLoading(true);
                if (player.isPlaying && !player.isSeeking) {
                    player.pause();
                }
            }
            return;
        }
        if (status.status === 'done' && status.downloadPath) {
            const audioPath = `wisp-audio://${status.downloadPath}`;
            if (lastLoadedPathRef.current !== audioPath) {
                lastLoadedPathRef.current = audioPath;
                player.load(audioPath);
                player.play();
            }
            if (songLoading) {
                setSongLoading(false);
            }
        }
        if (status.status === 'error') {
            if (songLoading) {
                setSongLoading(false);
            }
        }
    }, [player.currentIndex, downloadManager.statusVersion]);

    // Media Session API Implementation (optional, can be added if needed)

    const value = useMemo(() => ({
        ...player,
        downloads: downloadManager,
        isDownloading: songLoading
    }), [
        // Only include dependencies that should trigger consumer re-renders
        // Exclude currentTime to prevent rapid re-renders
        player.queue,
        player.currentIndex,
        player.shuffleEnabled,
        player.shuffleOrder,
        player.shuffleIndex,
        player.loopMode,
        player.duration,
        player.isPlaying,
        player.isLoading,
        player.error,
        downloadManager,
        songLoading,
        // Include the functions by reference (they're stable from useMemo in useAudioPlayer)
        player.load,
        player.play,
        player.pause,
        player.seek,
        player.setVolume,
        player.setQueue,
        player.addToQueue,
        player.getCurrentSong,
        player.skipNext,
        player.skipPrevious,
        player.goToIndex,
        player.toggleShuffle,
        player.toggleLoop,
    ]);

    if (loading) {
        return <></>;
    }

    return (
        <PlayerContext.Provider value={value}>
            {children}
        </PlayerContext.Provider>
    );
};
