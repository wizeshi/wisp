import { useState, useEffect, useCallback, useRef } from "react";
import { GenericSong } from "../../common/types/SongTypes";

export type DownloadStatus = {
    status: 'pending' | 'downloading' | 'done' | 'error';
    downloadPath?: string;
    message?: string;
    progress?: number;
}

export type DownloadManager = {
    getDownloadStatus: (downloadId: string) => DownloadStatus | undefined;
    requestDownload: (song: GenericSong) => string;
    isDownloading: (downloadId: string) => boolean;
    hasDownloaded: (downloadId: string) => boolean;
    getDownloadPath: (downloadId: string) => string | undefined;
    clearDownload: (downloadId: string) => void;
    getActiveDownloadsCount: () => number;
    statusVersion: number; // Expose version for reactive updates
}

const MAX_CONCURRENT_DOWNLOADS = 3;

export const useDownloadManager = (): DownloadManager => {
    const [downloadStatuses, setDownloadStatuses] = useState<Map<string, DownloadStatus>>(new Map());
    const [downloadQueue, setDownloadQueue] = useState<string[]>([]);
    const activeDownloadsRef = useRef<Set<string>>(new Set());
    const [statusVersion, setStatusVersion] = useState(0); // Track state changes

    // Generate consistent download ID from song metadata
    const generateDownloadId = useCallback((song: GenericSong): string => {
        // For YouTube sources, use the video ID directly
        if (song.source === 'youtube') {
            return song.id;
        }
        // For other sources, use title - artists format
        const artists = song.artists.map(a => a.name).join(", ");
        return `${song.title} - ${artists}`;
    }, []);

    // Process download queue
    const processQueue = useCallback(() => {
        if (downloadQueue.length === 0 || activeDownloadsRef.current.size >= MAX_CONCURRENT_DOWNLOADS) {
            return;
        }

        const nextDownloadId = downloadQueue[0];
        const status = downloadStatuses.get(nextDownloadId);

        if (!status || status.status !== 'pending') {
            // Remove from queue if already processed
            setDownloadQueue(prev => prev.slice(1));
            return;
        }

        // Check if already in active downloads (prevent duplicates)
        if (activeDownloadsRef.current.has(nextDownloadId)) {
            console.warn(`Download already active: ${nextDownloadId}, skipping`);
            setDownloadQueue(prev => prev.slice(1));
            return;
        }

        // Start download
        activeDownloadsRef.current.add(nextDownloadId);
        setDownloadStatuses(prev => {
            const newMap = new Map(prev);
            newMap.set(nextDownloadId, { ...status, status: 'downloading' });
            return newMap;
        });

        // Remove from queue
        setDownloadQueue(prev => prev.slice(1));

        console.log(`Starting download: ${nextDownloadId} (${activeDownloadsRef.current.size}/${MAX_CONCURRENT_DOWNLOADS} active)`);
        
        // Request download from backend
        // If nextDownloadId looks like a YouTube video ID (11 chars, alphanumeric), use "url"
        // Otherwise, it's a search term like "title - artists", use "terms"
        const isYouTubeId = /^[a-zA-Z0-9_-]{11}$/.test(nextDownloadId);
        const downloadType = isYouTubeId ? "url" : "terms";
        
        console.log(`Download type: ${downloadType} for ID: ${nextDownloadId}`);
        window.electronAPI.extractors.youtube.downloadAudio(downloadType, nextDownloadId);
    }, [downloadQueue, downloadStatuses]);

    // Listen for download status updates from backend
    useEffect(() => {
        window.electronAPI.extractors.youtube.onDownloadStatus((status) => {
            // Backend now sends the original search terms
            const searchTerm = status.searchTerms;
            
            if (!searchTerm) {
                console.warn('Received download status without searchTerms:', status);
                return;
            }
            
            console.log(`Download status update - Search: "${searchTerm}", Video: ${status.downloadId}, Status: ${status.status}`);
            
            setDownloadStatuses(prev => {
                const newMap = new Map(prev);
                const statusValue = status.status as 'pending' | 'downloading' | 'done' | 'error';
                newMap.set(searchTerm, {
                    status: statusValue,
                    downloadPath: status.downloadPath,
                    message: status.message
                });
                setStatusVersion(v => v + 1); // Increment version on status change
                return newMap;
            });

            // Remove from active downloads when done or error
            if (status.status === 'done' || status.status === 'error') {
                activeDownloadsRef.current.delete(searchTerm);
                console.log(`Download ${status.status}: ${searchTerm}`);
            }
        });
    }, []);

    // Process queue when it changes
    useEffect(() => {
        processQueue();
    }, [downloadQueue.length]); // Only trigger when queue length changes, not on every queue update

    // Auto-process when downloads complete (check active downloads changing)
    useEffect(() => {
        const activeCount = activeDownloadsRef.current.size;
        if (activeCount < MAX_CONCURRENT_DOWNLOADS && downloadQueue.length > 0) {
            // Use a small delay to batch multiple status updates
            const timer = setTimeout(() => {
                processQueue();
            }, 50);
            return () => clearTimeout(timer);
        }
    }, [downloadStatuses]);

    const requestDownload = useCallback((song: GenericSong): string => {
        const downloadId = generateDownloadId(song);
        
        // Check if already downloaded or in progress
        const existingStatus = downloadStatuses.get(downloadId);
        if (existingStatus) {
            if (existingStatus.status === 'done' || existingStatus.status === 'downloading') {
                return downloadId; // Already handled
            }
        }

        // Add to statuses as pending
        setDownloadStatuses(prev => {
            const newMap = new Map(prev);
            newMap.set(downloadId, { status: 'pending' });
            return newMap;
        });

        // Add to queue if not already there
        setDownloadQueue(prev => {
            if (prev.includes(downloadId)) {
                return prev;
            }
            return [...prev, downloadId];
        });

        return downloadId;
    }, [downloadStatuses, generateDownloadId]);

    const getDownloadStatus = useCallback((downloadId: string): DownloadStatus | undefined => {
        return downloadStatuses.get(downloadId);
    }, [downloadStatuses]);

    const isDownloading = useCallback((downloadId: string): boolean => {
        const status = downloadStatuses.get(downloadId);
        return status?.status === 'downloading' || status?.status === 'pending';
    }, [downloadStatuses]);

    const hasDownloaded = useCallback((downloadId: string): boolean => {
        const status = downloadStatuses.get(downloadId);
        return status?.status === 'done' && !!status.downloadPath;
    }, [downloadStatuses]);

    const getDownloadPath = useCallback((downloadId: string): string | undefined => {
        const status = downloadStatuses.get(downloadId);
        return status?.status === 'done' ? status.downloadPath : undefined;
    }, [downloadStatuses]);

    const clearDownload = useCallback((downloadId: string): void => {
        setDownloadStatuses(prev => {
            const newMap = new Map(prev);
            newMap.delete(downloadId);
            return newMap;
        });
        setDownloadQueue(prev => prev.filter(id => id !== downloadId));
        activeDownloadsRef.current.delete(downloadId);
    }, []);

    const getActiveDownloadsCount = useCallback((): number => {
        return activeDownloadsRef.current.size;
    }, []);

    return {
        getDownloadStatus,
        requestDownload,
        isDownloading,
        hasDownloaded,
        getDownloadPath,
        clearDownload,
        getActiveDownloadsCount,
        statusVersion
    };
};
