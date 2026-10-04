// SpicyLyrics Provider for wisp
// Powered by Service Realm Vault (wisp.service) for independent authentication & token caching.

// ---------------------------------------------------------------------------
// Authentication & Session Vault Manager (delegates to auth/spotify provider)
// ---------------------------------------------------------------------------
class SpotifyAuthManager {
    constructor(serviceId = 'spotify') {
        this.serviceId = serviceId;
    }

    async getSession() {
        if (!wisp.service || typeof wisp.service.getSession !== 'function') {
            return null;
        }
        return await wisp.service.getSession(this.serviceId);
    }

    async getAccessToken() {
        const tokens = await this.getTokens();
        return tokens ? tokens.accessToken : null;
    }

    async getTokens(forceRefresh = false) {
        if (wisp.auth && typeof wisp.auth.getTokens === 'function') {
            const tokens = await wisp.auth.getTokens({ serviceId: this.serviceId, forceRefresh: forceRefresh });
            if (tokens) return tokens;
        }
        if (wisp.spotify && typeof wisp.spotify.getTokens === 'function') {
            return await wisp.spotify.getTokens({ forceRefresh: forceRefresh });
        }
        return await this.getSession();
    }

    async login() {
        if (wisp.auth && typeof wisp.auth.login === 'function') {
            return await wisp.auth.login(this.serviceId);
        }
        return null;
    }

    async logout() {
        if (wisp.auth && typeof wisp.auth.logout === 'function') {
            return await wisp.auth.logout(this.serviceId);
        }
        if (wisp.service && typeof wisp.service.clearSession === 'function') {
            await wisp.service.clearSession(this.serviceId);
        }
    }
}

const authManager = new SpotifyAuthManager('spotify');

function normalizeTrackId(trackId) {
    if (!trackId || typeof trackId !== 'string') return '';
    let id = trackId.trim();
    if (id.includes('?')) {
        id = id.split('?')[0];
    }
    if (id.includes('spotify:')) {
        const parts = id.split(':');
        id = parts.length > 0 ? parts[parts.length - 1] : id;
    }
    if (id.includes('/')) {
        const parts = id.split('/');
        id = parts.length > 0 ? parts[parts.length - 1] : id;
    }
    return id.trim();
}

async function searchTrackId(title, artist, tokens) {
    try {
        const queries = [];
        if (title && artist) {
            queries.push('track:' + title + ' artist:' + artist);
            queries.push(title + ' ' + artist);
        } else if (title) {
            queries.push(title);
        }

        for (let i = 0; i < queries.length; i++) {
            const q = encodeURIComponent(queries[i]);
            const url = 'https://api.spotify.com/v1/search?type=track&limit=1&q=' + q;
            console.log('[SpicyLyrics] Searching track: ' + queries[i]);
            const res = await wisp.fetch(url, {
                headers: {
                    'Authorization': 'Bearer ' + tokens.accessToken,
                    'Accept': 'application/json'
                }
            });
            if (res.status === 200) {
                const data = await res.json();
                const items = data.tracks && data.tracks.items;
                if (items && items.length > 0 && items[0].id) {
                    console.log('[SpicyLyrics] Found matching Spotify track: ' + items[0].id + ' (' + items[0].name + ')');
                    return items[0].id;
                }
            } else {
                console.warn('[SpicyLyrics] Search query "' + queries[i] + '" failed with status: ' + res.status);
            }
        }
    } catch (e) {
        console.error('[SpicyLyrics] Search error: ' + e);
    }
    return null;
}

let sessionTk = null;
let sessionPromise = null;

async function ensureSession(spotifyToken, clientVersion) {
    if (sessionTk) return sessionTk;
    if (sessionPromise) return await sessionPromise;

    sessionPromise = (async () => {
        try {
            console.log('[SpicyLyrics] Registering session with Spicy Lyrics API...');
            const res = await wisp.fetch('https://api.spicylyrics.org/query', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-mode': '2',
                    'SpicyLyrics-Version': clientVersion,
                    'Origin': 'https://xpui.app.spotify.com',
                    'Referer': 'https://xpui.app.spotify.com/',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.138 Spotify/1.3.3.264 Safari/537.36',
                    'Authorization': spotifyToken
                },
                body: JSON.stringify({
                    client: { version: clientVersion },
                    queries: [
                        { operation: 'createSession', variables: {} },
                        { operation: 'pingConfig', variables: {} }
                    ]
                })
            });

            if (res.status === 200) {
                const data = await res.json();
                const sessionQuery = data.queries && data.queries.find(q => q && q.operation === 'createSession');
                if (sessionQuery && sessionQuery.result && sessionQuery.result.data && sessionQuery.result.data.tk) {
                    sessionTk = sessionQuery.result.data.tk;
                    console.log('[SpicyLyrics] Session successfully registered (tk: ' + sessionTk.slice(0, 8) + '...)');
                }
            } else {
                console.warn('[SpicyLyrics] createSession returned HTTP ' + res.status);
            }
        } catch (e) {
            console.warn('[SpicyLyrics] Session registration failed: ' + e);
        } finally {
            sessionPromise = null;
        }
        return sessionTk;
    })();

    return await sessionPromise;
}

async function fetchLyricsForTrackId(trackId, auth) {
    let tokens = await auth.getTokens();
    if (!tokens || !tokens.accessToken) {
        console.warn('[SpicyLyrics] No tokens available for lyrics fetch');
        return null;
    }

    const SPICYLYRICS_VERSION = "6.3.142";
    const url = "https://api.spicylyrics.org/query";

    // Initialize session with SpicyLyrics server if not already established
    await ensureSession(tokens.accessToken, SPICYLYRICS_VERSION);

    const headers = {
        'Accept': '*/*',
        'Content-Type': 'application/json',

        'Priority': 'u=1, i',

        'Origin': 'https://xpui.app.spotify.com',
        'Referer': 'https://xpui.app.spotify.com/',

        'Sec-Ch-Ua': '"Chromium";v="151", "Not=A?Brand";v="99"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'cross-site',

        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.138 Spotify/1.3.3.264 Safari/537.36',

        'SpicyLyrics-WebAuth': 'Bearer ' + tokens.accessToken,
        'SpicyLyrics-Version': SPICYLYRICS_VERSION,

        'X-mode': '2'
    };

    const body = JSON.stringify({
        "client": {
            "version": SPICYLYRICS_VERSION,
        },
        "queries": [
            {
                "operation": "lyrics",
                "variables": {
                    "auth": "SpicyLyrics-WebAuth",
                    "id": trackId,
                }
            }
        ]
    });

    console.log('[SpicyLyrics] Fetching lyrics for track ' + trackId + '...');

    let res = await wisp.fetch(url, {
        method: 'POST',
        headers: headers,
        body: body
    });

    if (res.status === 401) {
        console.warn('[SpicyLyrics] Got 401 Unauthorized from Spicy Lyrics API, requesting token refresh from vault...');
        const freshTokens = await auth.getTokens(true);
        if (!freshTokens || !freshTokens.accessToken) {
            console.error('[SpicyLyrics] Token refresh failed');
            return null;
        }
        tokens = freshTokens;
        headers['SpicyLyrics-WebAuth'] = 'Bearer ' + freshTokens.accessToken;
        res = await wisp.fetch(url, { 
            method: 'POST',
            headers: headers,
            body: body
        });
    }

    if (res.status === 404) {
        console.warn('[SpicyLyrics] Spicy Lyrics API returned 404 (no lyrics available for track ' + trackId + ')');
        return null;
    }

    if (res.status !== 200) {
        console.warn('[SpicyLyrics] Spicy Lyrics API returned status: ' + res.status);
        return null;
    }

    const data = await res.json();
    return parseSpicyLyrics(data);
}

// SLObjPack unpacker for SpicyLyrics API responses
function unpackSLObjPack(packed) {
    if (!Array.isArray(packed) || packed.length !== 2) return null;
    const valuesList = packed[0];
    const stream = packed[1];
    if (!Array.isArray(valuesList) || !Array.isArray(stream)) return null;

    let cursor = 0;
    const streamLen = stream.length;

    function readStream() {
        if (cursor >= streamLen) return undefined;
        return stream[cursor++];
    }

    function resolvePointer(ptr) {
        return valuesList[ptr];
    }

    function readKey() {
        return resolvePointer(readStream());
    }

    function decode() {
        const op = readStream();
        if (op === undefined) return null;
        if (typeof op === 'number' && op >= 0) {
            return resolvePointer(op);
        }

        switch (op) {
            case -1: {
                const numKeys = readStream();
                const keys = new Array(numKeys);
                for (let i = 0; i < numKeys; i++) keys[i] = readKey();
                const obj = {};
                for (let i = 0; i < numKeys; i++) obj[keys[i]] = decode();
                return obj;
            }
            case -2: {
                const numItems = readStream();
                const arr = new Array(numItems);
                for (let i = 0; i < numItems; i++) arr[i] = decode();
                return arr;
            }
            case -3: {
                const numItems = readStream();
                const numKeys = readStream();
                const keys = new Array(numKeys);
                for (let i = 0; i < numKeys; i++) keys[i] = readKey();
                const arr = new Array(numItems);
                for (let i = 0; i < numItems; i++) {
                    const obj = {};
                    for (let k = 0; k < numKeys; k++) obj[keys[k]] = decode();
                    arr[i] = obj;
                }
                return arr;
            }
            case -4:
                return [];
            case -5:
                return [decode()];
            case -6:
                return {};
            default:
                throw new Error('[SpicyLyrics] Unknown opcode ' + op);
        }
    }

    return decode();
}

const ZeroWidthRegex = /[\u200B\u200E\u200F\u2060\uFEFF]/g;

function cleanText(text) {
    if (typeof text !== 'string') return '';
    return text.replace(ZeroWidthRegex, '').trim();
}

function parseSpicyLyrics(apiResponse) {
    if (!apiResponse || !Array.isArray(apiResponse.queries)) {
        console.warn('[SpicyLyrics] Invalid API response structure (missing queries array)');
        return null;
    }

    const query = apiResponse.queries.find(q => q && (q.operation === 'lyrics' || q.result));
    if (!query || !query.result) {
        console.warn('[SpicyLyrics] No lyrics query result found in response');
        return null;
    }

    if (query.result.status === 404 || query.status === 404) {
        console.warn('[SpicyLyrics] Lyrics not found for track (404 in query result)');
        return null;
    }

    let rawData = query.result.data || query.data;
    if (!rawData) {
        console.warn('[SpicyLyrics] Query result missing data payload');
        return null;
    }

    let lyrics = rawData;
    if (Array.isArray(rawData) && rawData.length === 2 && Array.isArray(rawData[0]) && Array.isArray(rawData[1])) {
        try {
            lyrics = unpackSLObjPack(rawData);
        } catch (err) {
            console.error('[SpicyLyrics] Failed to unpack SLObjPack payload: ' + err);
            return null;
        }
    }

    if (!lyrics || typeof lyrics !== 'object') {
        console.warn('[SpicyLyrics] Unpacked lyrics is not a valid object');
        return null;
    }

    const type = lyrics.Type || '';
    const source = lyrics.source || 'unknown';
    console.log('[SpicyLyrics] Lyrics response resolved: source="' + source + '", Type="' + type + '"');

    const lines = [];

    if (type === 'Static') {
        const rawLines = Array.isArray(lyrics.Lines) ? lyrics.Lines : [];
        for (let i = 0; i < rawLines.length; i++) {
            const item = rawLines[i];
            const text = cleanText(item.Text || '');
            if (!text) continue;
            lines.push({
                content: text,
                startTimeMs: 0,
                words: []
            });
        }

        if (lines.length === 0) return null;

        return {
            provider: 'spicylyrics',
            syncMode: 'unsynced',
            lines: lines
        };
    }

    if (type === 'Line') {
        const content = Array.isArray(lyrics.Content) ? lyrics.Content : [];
        for (let i = 0; i < content.length; i++) {
            const item = content[i];
            if (item.Type !== 'Vocal' && item.Text === undefined) continue;
            const text = cleanText(item.Text || '');
            if (!text) continue;
            const startMs = typeof item.StartTime === 'number' ? Math.round(item.StartTime * 1000) : 0;
            const endMs = typeof item.EndTime === 'number' ? Math.round(item.EndTime * 1000) : null;
            lines.push({
                content: text,
                startTimeMs: startMs,
                endTimeMs: endMs,
                words: []
            });
        }

        if (lines.length === 0) return null;

        return {
            provider: 'spicylyrics',
            syncMode: 'line',
            lines: lines
        };
    }

    if (type === 'Syllable') {
        const content = Array.isArray(lyrics.Content) ? lyrics.Content : [];
        for (let i = 0; i < content.length; i++) {
            const item = content[i];
            if (item.Type !== 'Vocal' && !item.Lead) continue;
            const lead = item.Lead;
            if (!lead || !Array.isArray(lead.Syllables) || lead.Syllables.length === 0) continue;

            let lineText = '';
            const words = [];
            const syllables = lead.Syllables;

            for (let j = 0; j < syllables.length; j++) {
                const s = syllables[j];
                const sText = cleanText(s.Text || '');
                if (!sText) continue;
                lineText += sText;
                if (j < syllables.length - 1 && !s.IsPartOfWord) {
                    lineText += ' ';
                }

                const sStartMs = typeof s.StartTime === 'number' ? Math.round(s.StartTime * 1000) : 0;
                const sEndMs = typeof s.EndTime === 'number' ? Math.round(s.EndTime * 1000) : null;
                words.push({
                    content: sText,
                    startTimeMs: sStartMs,
                    endTimeMs: sEndMs
                });
            }

            // Append background vocals if present
            if (Array.isArray(item.Background)) {
                for (let k = 0; k < item.Background.length; k++) {
                    const bg = item.Background[k];
                    if (!bg || !Array.isArray(bg.Syllables) || bg.Syllables.length === 0) continue;
                    let bgText = '';
                    const bgWords = [];
                    for (let m = 0; m < bg.Syllables.length; m++) {
                        const bs = bg.Syllables[m];
                        const bsText = cleanText(bs.Text || '');
                        if (!bsText) continue;
                        bgText += bsText;
                        if (m < bg.Syllables.length - 1 && !bs.IsPartOfWord) {
                            bgText += ' ';
                        }
                        bgWords.push({
                            content: bsText,
                            startTimeMs: typeof bs.StartTime === 'number' ? Math.round(bs.StartTime * 1000) : 0,
                            endTimeMs: typeof bs.EndTime === 'number' ? Math.round(bs.EndTime * 1000) : null
                        });
                    }
                    if (bgText.trim()) {
                        lineText += ' (' + bgText.trim() + ')';
                        words.push(...bgWords);
                    }
                }
            }

            const trimmedLine = lineText.trim();
            if (!trimmedLine) continue;

            const lineStartMs = typeof lead.StartTime === 'number'
                ? Math.round(lead.StartTime * 1000)
                : (words.length > 0 ? words[0].startTimeMs : 0);
            const lineEndMs = typeof lead.EndTime === 'number'
                ? Math.round(lead.EndTime * 1000)
                : (words.length > 0 ? words[words.length - 1].endTimeMs : null);

            lines.push({
                content: trimmedLine,
                startTimeMs: lineStartMs,
                endTimeMs: lineEndMs,
                words: words
            });
        }

        if (lines.length === 0) return null;

        return {
            provider: 'spicylyrics',
            syncMode: 'word',
            lines: lines
        };
    }

    console.warn('[SpicyLyrics] Unsupported lyrics Type: ' + type);
    return null;
}

async function getLyrics(query) {
    console.log('[SpicyLyrics] getLyrics called: title="' + (query.title || '') + '", artist="' + (query.artist || '') + '", id=' + (query.id || '') + ', source=' + (query.source || ''));

    let tokens = await authManager.getTokens();
    if (!tokens || !tokens.accessToken) {
        console.warn('[SpicyLyrics] No Spotify tokens available (user may not be logged into Spotify)');
        return null;
    }

    let trackId = '';
    const isSpotifySource = query.source === 'spotify';

    if (isSpotifySource && query.id) {
        trackId = normalizeTrackId(query.id);
        console.log('[SpicyLyrics] Direct trackId from Spotify playback: ' + trackId);
    }

    // If not a Spotify song or normalized ID not suitable, search Spotify catalog
    if (!trackId && query.title) {
        console.log('[SpicyLyrics] Track is from ' + (query.source || 'unknown') + ', searching Spotify catalog...');
        trackId = await searchTrackId(query.title, query.artist, tokens);
    }

    if (!trackId) {
        console.warn('[SpicyLyrics] Could not determine a Spotify track ID for "' + (query.title || '') + '"');
        return null;
    }

    return await fetchLyricsForTrackId(trackId, authManager);
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { getLyrics, authManager, SpotifyAuthManager, parseSpicyLyrics, unpackSLObjPack };
}
