import fs from "node:fs"
import path from "node:path"
import { app } from "electron"

const cachePath = path.join(app.getPath('userData'), 'queryCache.json')

/**
 * Represents a cached query result
 */
interface CachedQuery {
    searchTerms: string
    youtubeId: string
    timestamp: number // When this cache entry was created
    hitCount: number // How many times this cache entry has been used
}

/**
 * The query cache data structure
 */
interface QueryCacheData {
    version: number
    queries: Record<string, CachedQuery> // Key is normalized search terms
}

class QueryCache {
    private cache: QueryCacheData
    private initialized = false
    private readonly MAX_CACHE_SIZE = 5000 // Maximum number of cached queries
    private readonly CACHE_VERSION = 1

    constructor() {
        this.cache = {
            version: this.CACHE_VERSION,
            queries: {}
        }
    }

    /**
     * Normalizes search terms for consistent cache key generation
     * Removes special characters, converts to lowercase, sorts words
     */
    private normalizeSearchTerms(searchTerms: string): string {
        return searchTerms
            .toLowerCase()
            .replace(/[^a-z0-9\s]/g, '') // Remove special characters
            .split(/\s+/) // Split into words
            .filter(Boolean) // Remove empty strings
            .sort() // Sort alphabetically for consistency
            .join(' ')
    }

    /**
     * Initializes the cache by loading from disk
     */
    async initialize(): Promise<void> {
        if (this.initialized) {
            return
        }

        try {
            const data = await fs.promises.readFile(cachePath, "utf-8")
            const loadedCache = JSON.parse(data) as QueryCacheData

            // Check version compatibility
            if (loadedCache.version !== this.CACHE_VERSION) {
                console.log(`Cache version mismatch (expected ${this.CACHE_VERSION}, got ${loadedCache.version}). Creating new cache.`)
                this.cache = {
                    version: this.CACHE_VERSION,
                    queries: {}
                }
                await this.save()
            } else {
                this.cache = loadedCache
                console.log(`Loaded query cache with ${Object.keys(this.cache.queries).length} entries`)
            }
        } catch (err) {
            console.log("Query cache file not found, creating new cache")
            this.cache = {
                version: this.CACHE_VERSION,
                queries: {}
            }
            await this.save()
        }

        this.initialized = true
    }

    /**
     * Saves the cache to disk
     */
    private async save(): Promise<void> {
        try {
            await fs.promises.writeFile(cachePath, JSON.stringify(this.cache, null, 2), "utf8")
        } catch (err) {
            console.error("Error saving query cache:", err)
            throw err
        }
    }

    /**
     * Checks if a search query exists in the cache
     * Returns the YouTube video ID if found, undefined otherwise
     */
    async get(searchTerms: string): Promise<string | undefined> {
        await this.initialize()

        const normalizedKey = this.normalizeSearchTerms(searchTerms)
        const cachedQuery = this.cache.queries[normalizedKey]

        if (cachedQuery) {
            // Increment hit count
            cachedQuery.hitCount++
            await this.save()

            console.log(`Cache HIT for "${searchTerms}" -> ${cachedQuery.youtubeId} (${cachedQuery.hitCount} hits)`)
            return cachedQuery.youtubeId
        }

        console.log(`Cache MISS for "${searchTerms}"`)
        return undefined
    }

    /**
     * Adds a new search query -> YouTube ID mapping to the cache
     */
    async set(searchTerms: string, youtubeId: string): Promise<void> {
        await this.initialize()

        const normalizedKey = this.normalizeSearchTerms(searchTerms)

        // Check if entry already exists
        const existingEntry = this.cache.queries[normalizedKey]
        if (existingEntry) {
            // Entry already exists, don't overwrite
            console.log(`Cache entry already exists for "${searchTerms}" -> ${existingEntry.youtubeId}`)
            return
        }

        // Check if we need to prune the cache
        if (Object.keys(this.cache.queries).length >= this.MAX_CACHE_SIZE) {
            await this.pruneCache()
        }

        // Add new cache entry
        this.cache.queries[normalizedKey] = {
            searchTerms: searchTerms, // Store original for debugging
            youtubeId: youtubeId,
            timestamp: Date.now(),
            hitCount: 0
        }

        await this.save()
        console.log(`Cached: "${searchTerms}" -> ${youtubeId}`)
    }

    /**
     * Removes least recently used entries when cache is full
     * Removes the oldest 20% of entries based on timestamp and hit count
     */
    private async pruneCache(): Promise<void> {
        const entries = Object.entries(this.cache.queries)
        
        // Score entries: lower score = more likely to be removed
        // Prioritize recent entries and frequently accessed entries
        const scoredEntries = entries.map(([key, value]) => ({
            key,
            score: value.timestamp + (value.hitCount * 86400000) // Add 1 day per hit
        }))

        // Sort by score (lowest first)
        scoredEntries.sort((a, b) => a.score - b.score)

        // Remove lowest 20%
        const removeCount = Math.floor(this.MAX_CACHE_SIZE * 0.2)
        const toRemove = scoredEntries.slice(0, removeCount)

        for (const entry of toRemove) {
            delete this.cache.queries[entry.key]
        }

        console.log(`Pruned ${removeCount} entries from query cache`)
    }

    /**
     * Clears all entries from the cache
     */
    async clear(): Promise<void> {
        await this.initialize()

        this.cache.queries = {}
        await this.save()
        console.log("Query cache cleared")
    }

    /**
     * Gets cache statistics
     */
    async getStats(): Promise<{
        totalEntries: number
        totalHits: number
        oldestEntry: number | null
        newestEntry: number | null
    }> {
        await this.initialize()

        const entries = Object.values(this.cache.queries)
        const totalHits = entries.reduce((sum, entry) => sum + entry.hitCount, 0)
        const timestamps = entries.map(e => e.timestamp)

        return {
            totalEntries: entries.length,
            totalHits: totalHits,
            oldestEntry: timestamps.length > 0 ? Math.min(...timestamps) : null,
            newestEntry: timestamps.length > 0 ? Math.max(...timestamps) : null
        }
    }

    /**
     * Checks if the cache has a specific entry
     */
    async has(searchTerms: string): Promise<boolean> {
        await this.initialize()
        
        const normalizedKey = this.normalizeSearchTerms(searchTerms)
        return normalizedKey in this.cache.queries
    }

    /**
     * Removes a specific entry from the cache
     */
    async delete(searchTerms: string): Promise<boolean> {
        await this.initialize()

        const normalizedKey = this.normalizeSearchTerms(searchTerms)
        
        if (normalizedKey in this.cache.queries) {
            delete this.cache.queries[normalizedKey]
            await this.save()
            console.log(`Deleted cache entry for "${searchTerms}"`)
            return true
        }

        return false
    }
}

export const queryCache = new QueryCache()
