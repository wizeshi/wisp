// SpicyLyrics Provider for wisp
// Fetches word-synced and syllable-synced lyrics using the SpicyLyrics Public v1 API.
// Normalizes responses into the universal Wisp Lyrics Format (WLF).

const ZeroWidthRegex = /[\u200B\u200E\u200F\u2060\uFEFF]/g;

function cleanText(text) {
    if (typeof text !== 'string') return '';
    return text.replace(ZeroWidthRegex, '');
}

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

async function getApiKey() {
    if (wisp.service && typeof wisp.service.getSession === 'function') {
        const session = await wisp.service.getSession('spicylyrics');
        if (session && (session.apiKey || session.accessToken)) {
            return session.apiKey || session.accessToken;
        }
    }
    return null;
}

/**
 * Resolves lyrics attribution string from SpicyLyrics payload.
 */
function resolveAttribution(body) {
    if (!body) return null;
    const source = (body.source || '').toLowerCase();

    if (source === 'apple_music') {
        return 'Sourced using Apple Music';
    }
    if (source === 'spotify') {
        return 'Sourced using Spotify';
    }

    const ua = body.UploadAttribution;
    if (ua && typeof ua === 'object') {
        const lines = [];
        if (ua.Uploader && ua.Uploader.username) {
            const uUrl = ua.Uploader.url || '';
            const uName = ua.Uploader.username;
            lines.push(uUrl ? ('Lyrics uploaded by [' + uName + '](' + uUrl + ')') : ('Lyrics uploaded by ' + uName));
        }
        if (ua.Maker && ua.Maker.username) {
            const mUrl = ua.Maker.url || '';
            const mName = ua.Maker.username;
            lines.push(mUrl ? ('Lyrics written by [' + mName + '](' + mUrl + ')') : ('Lyrics written by ' + mName));
        }
        if (lines.length > 0) {
            return lines.join('\n');
        }
    }

    if (source === 'spicy_lyrics') {
        return 'Sourced using SpicyLyrics';
    }

    return null;
}

/**
 * Converts SpicyLyrics API payload into Wisp Lyrics Format (WLF).
 */
function parseSpicyLyricsToWlf(data) {
    if (!data || !data.Body) {
        console.warn('[SpicyLyrics] Invalid API response: missing Body');
        return null;
    }

    const body = data.Body;
    const type = body.Type || '';
    const attribution = resolveAttribution(body);
    console.log('[SpicyLyrics] Processing lyrics response: Type="' + type + '", source="' + (body.source || '') + '"');

    const lines = [];

    if (type === 'Syllable') {
        const content = Array.isArray(body.Content) ? body.Content : [];
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
                    endTimeMs: sEndMs,
                    partOfWord: Boolean(s.IsPartOfWord)
                });
            }

            const trimmedLine = lineText.trim();
            if (!trimmedLine) continue;

            const lineStartMs = typeof lead.StartTime === 'number'
                ? Math.round(lead.StartTime * 1000)
                : (words.length > 0 ? words[0].startTimeMs : 0);
            const lineEndMs = typeof lead.EndTime === 'number'
                ? Math.round(lead.EndTime * 1000)
                : (words.length > 0 ? words[words.length - 1].endTimeMs : null);

            // Background vocals parsing
            const background = [];
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
                            endTimeMs: typeof bs.EndTime === 'number' ? Math.round(bs.EndTime * 1000) : null,
                            partOfWord: Boolean(bs.IsPartOfWord)
                        });
                    }

                    if (bgText.trim()) {
                        background.push({
                            content: bgText.trim(),
                            startTimeMs: typeof bg.StartTime === 'number' ? Math.round(bg.StartTime * 1000) : (bgWords[0]?.startTimeMs || lineStartMs),
                            endTimeMs: typeof bg.EndTime === 'number' ? Math.round(bg.EndTime * 1000) : (bgWords[bgWords.length - 1]?.endTimeMs || lineEndMs),
                            words: bgWords
                        });
                    }
                }
            }

            lines.push({
                content: trimmedLine,
                startTimeMs: lineStartMs,
                endTimeMs: lineEndMs,
                speaker: item.OppositeAligned ? 'right' : 'left',
                words: words,
                background: background
            });
        }

        if (lines.length === 0) return null;

        return {
            version: '1.0',
            provider: 'spicylyrics',
            syncMode: 'word',
            attribution: attribution,
            lines: lines
        };
    }

    if (type === 'Line') {
        const content = Array.isArray(body.Content) ? body.Content : [];
        for (let i = 0; i < content.length; i++) {
            const item = content[i];
            const text = cleanText(item.Text || (item.Lead && item.Lead.Text) || '');
            if (!text) continue;
            const startMs = typeof item.StartTime === 'number' ? Math.round(item.StartTime * 1000) : 0;
            const endMs = typeof item.EndTime === 'number' ? Math.round(item.EndTime * 1000) : null;
            lines.push({
                content: text.trim(),
                startTimeMs: startMs,
                endTimeMs: endMs,
                speaker: item.OppositeAligned ? 'right' : 'left',
                words: []
            });
        }

        if (lines.length === 0) return null;

        return {
            version: '1.0',
            provider: 'spicylyrics',
            syncMode: 'line',
            attribution: attribution,
            lines: lines
        };
    }

    if (type === 'Static') {
        const rawLines = Array.isArray(body.Lines) ? body.Lines : [];
        for (let i = 0; i < rawLines.length; i++) {
            const item = rawLines[i];
            const text = cleanText(typeof item === 'string' ? item : (item.Text || ''));
            if (!text) continue;
            lines.push({
                content: text.trim(),
                startTimeMs: 0,
                endTimeMs: null,
                speaker: 'left',
                words: []
            });
        }

        if (lines.length === 0) return null;

        return {
            version: '1.0',
            provider: 'spicylyrics',
            syncMode: 'unsynced',
            attribution: attribution,
            lines: lines
        };
    }

    console.warn('[SpicyLyrics] Unsupported Body.Type: ' + type);
    return null;
}

async function getLyrics(query) {
    console.log('[SpicyLyrics] getLyrics called: title="' + (query.title || '') + '", artist="' + (query.artist || '') + '", id=' + (query.id || '') + ', source=' + (query.source || ''));

    const apiKey = await getApiKey();
    if (!apiKey) {
        console.warn('[SpicyLyrics] No API key available. Please authenticate SpicyLyrics in Settings -> ACCOUNTS.');
        return null;
    }

    let trackId = '';
    const isSpotifySource = query.source === 'spotify' || query.source === 'spotifyInternal';

    if (isSpotifySource && query.id) {
        trackId = normalizeTrackId(query.id);
        console.log('[SpicyLyrics] Direct Spotify trackId: ' + trackId);
    }

    // Fallback: If not playing directly from Spotify or missing ID, search Spotify if Spotify auth tokens are present
    if (!trackId && query.title && wisp.auth && typeof wisp.auth.getTokens === 'function') {
        try {
            const spotifyTokens = await wisp.auth.getTokens({ serviceId: 'spotify' });
            if (spotifyTokens && spotifyTokens.accessToken) {
                const q = encodeURIComponent('track:' + query.title + ' artist:' + (query.artist || ''));
                const searchRes = await wisp.fetch('https://api.spotify.com/v1/search?type=track&limit=1&q=' + q, {
                    headers: { 'Authorization': 'Bearer ' + spotifyTokens.accessToken }
                });
                if (searchRes.status === 200) {
                    const sData = await searchRes.json();
                    const items = sData.tracks && sData.tracks.items;
                    if (items && items.length > 0) {
                        trackId = items[0].id;
                        console.log('[SpicyLyrics] Resolved track ID via Spotify catalog: ' + trackId);
                    }
                }
            }
        } catch (e) {
            console.warn('[SpicyLyrics] Catalog lookup failed: ' + e);
        }
    }

    if (!trackId) {
        console.warn('[SpicyLyrics] Could not determine track ID for "' + (query.title || '') + '"');
        return null;
    }

    const url = 'https://api.spicylyrics.org/v1/lyrics/' + encodeURIComponent(trackId);
    console.log('[SpicyLyrics] Fetching from Public API: ' + url);

    const res = await wisp.fetch(url, {
        method: 'GET',
        headers: {
            'Authorization': 'Bearer ' + apiKey,
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) wisp'
        }
    });

    if (res.status === 401) {
        console.error('[SpicyLyrics] 401 Unauthorized: Invalid SpicyLyrics API key');
        return null;
    }

    if (res.status === 404) {
        console.warn('[SpicyLyrics] 404: No lyrics available for track ' + trackId);
        return null;
    }

    if (res.status !== 200) {
        console.warn('[SpicyLyrics] API returned status ' + res.status);
        return null;
    }

    const data = await res.json();
    return parseSpicyLyricsToWlf(data);
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { getLyrics, parseSpicyLyricsToWlf };
}
