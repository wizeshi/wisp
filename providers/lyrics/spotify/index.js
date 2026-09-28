// Spotify Lyrics Provider for Wisp
// Line-synced and unsynced lyrics directly from Spotify Color Lyrics API.
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
      console.log('[Spotify] Searching track: ' + queries[i]);
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
          console.log('[Spotify] Found matching Spotify track: ' + items[0].id + ' (' + items[0].name + ')');
          return items[0].id;
        }
      } else {
        console.warn('[Spotify] Search query "' + queries[i] + '" failed with status: ' + res.status);
      }
    }
  } catch (e) {
    console.error('[Spotify] Search error: ' + e);
  }
  return null;
}

async function fetchLyricsForTrackId(trackId, auth) {
  let tokens = await auth.getTokens();
  if (!tokens || !tokens.accessToken) {
    console.warn('[Spotify] No tokens available for lyrics fetch');
    return null;
  }

  const url = 'https://spclient.wg.spotify.com/color-lyrics/v2/track/' + encodeURIComponent(trackId) + '?format=json&vocalRemoval=false&market=from_token';
  const headers = {
    'App-Platform': 'WebPlayer',
    'Accept': 'application/json',
    'Authorization': 'Bearer ' + tokens.accessToken,
    'Client-Token': tokens.clientToken || '',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
    'Spotify-App-Version': '1.2.96.238.g5c95ebca'
  };

  console.log('[Spotify] Fetching Color Lyrics for track ' + trackId + '...');
  let res = await wisp.fetch(url, { headers: headers });

  if (res.status === 401) {
    console.warn('[Spotify] Got 401 Unauthorized from Color Lyrics API, requesting token refresh from vault...');
    const freshTokens = await auth.getTokens(true);
    if (!freshTokens || !freshTokens.accessToken) {
      console.error('[Spotify] Token refresh failed');
      return null;
    }
    tokens = freshTokens;
    headers['Authorization'] = 'Bearer ' + freshTokens.accessToken;
    if (freshTokens.clientToken) headers['Client-Token'] = freshTokens.clientToken;
    res = await wisp.fetch(url, { headers: headers });
  }

  if (res.status === 404) {
    console.warn('[Spotify] Color Lyrics API returned 404 (no lyrics available for track ' + trackId + ')');
    return null;
  }

  if (res.status !== 200) {
    console.warn('[Spotify] Color Lyrics API returned status: ' + res.status);
    return null;
  }

  const data = await res.json();
  const lyrics = data.lyrics;
  if (!lyrics) {
    console.warn('[Spotify] Response JSON missing lyrics field');
    return null;
  }

  const syncType = lyrics.syncType || 'LINE_UNSYNCED';
  const rawLines = lyrics.lines || [];
  const lines = [];

  for (let i = 0; i < rawLines.length; i++) {
    const item = rawLines[i];
    const content = (item.words || '').trim();
    if (!content) continue;
    let startTimeMs = 0;
    if (typeof item.startTimeMs === 'string') {
      startTimeMs = parseInt(item.startTimeMs, 10) || 0;
    } else if (typeof item.startTimeMs === 'number') {
      startTimeMs = item.startTimeMs;
    }
    lines.push({
      content: content,
      startTimeMs: startTimeMs,
      words: []
    });
  }

  if (lines.length === 0) {
    console.warn('[Spotify] No non-empty lines found in lyrics');
    return null;
  }

  const syncMode = syncType === 'LINE_SYNCED' ? 'line' : 'unsynced';
  console.log('[Spotify] Lyrics fetched successfully: ' + lines.length + ' lines (syncMode: ' + syncMode + ')');

  return {
    provider: 'spotify',
    syncMode: syncMode,
    lines: lines
  };
}

async function getLyrics(query) {
  console.log('[Spotify] getLyrics called: title="' + (query.title || '') + '", artist="' + (query.artist || '') + '", id=' + (query.id || '') + ', source=' + (query.source || ''));

  let tokens = await authManager.getTokens();
  if (!tokens || !tokens.accessToken) {
    console.warn('[Spotify] No Spotify tokens available (user may not be logged into Spotify)');
    return null;
  }

  let trackId = '';
  const isSpotifySource = query.source === 'spotify' || query.source === 'spotifyInternal';

  if (isSpotifySource && query.id) {
    trackId = normalizeTrackId(query.id);
    console.log('[Spotify] Direct trackId from Spotify playback: ' + trackId);
  }

  // If not a Spotify song or normalized ID not suitable, search Spotify catalog
  if (!trackId && query.title) {
    console.log('[Spotify] Track is from ' + (query.source || 'unknown') + ', searching Spotify catalog...');
    trackId = await searchTrackId(query.title, query.artist, tokens);
  }

  if (!trackId) {
    console.warn('[Spotify] Could not determine a Spotify track ID for "' + (query.title || '') + '"');
    return null;
  }

  return await fetchLyricsForTrackId(trackId, authManager);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getLyrics, authManager, SpotifyAuthManager };
}
