// Spotify Lyrics Provider for Wisp
// Line-synced and unsynced lyrics directly from Spotify Color Lyrics API.
// Powered by Service Realm Vault (wisp.service) for independent authentication & token caching.

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

  async getTokens(forceRefresh = false) {
    const session = await this.getSession();
    const now = Date.now();

    if (!forceRefresh && session && session.accessToken && (now < (session.expiresAtMs - 60000))) {
      return session;
    }

    // Attempt token refresh protected by host mutex lock to prevent concurrent refresh stampedes
    if (!wisp.service || typeof wisp.service.withRefreshLock !== 'function') {
      // Fallback to legacy bridge if available
      if (wisp.spotify && typeof wisp.spotify.getTokens === 'function') {
        return await wisp.spotify.getTokens({ forceRefresh: forceRefresh });
      }
      console.warn('[Spotify] Neither wisp.service nor wisp.spotify available in JS environment');
      return null;
    }

    return await wisp.service.withRefreshLock(this.serviceId, async () => {
      // Re-check after acquiring lock in case another plugin/request refreshed it concurrently
      const current = await this.getSession();
      if (!forceRefresh && current && current.accessToken && (Date.now() < (current.expiresAtMs - 60000))) {
        return current;
      }

      let spDc = (current && current.cookies && current.cookies.sp_dc) || (current && current.cookie) || null;

      if (!spDc) {
        // Fallback check to legacy credentials bridge
        if (wisp.spotify && typeof wisp.spotify.getTokens === 'function') {
          const legacy = await wisp.spotify.getTokens({ forceRefresh: true });
          if (legacy && legacy.accessToken) {
            return legacy;
          }
        }
        console.warn('[Spotify] NOT_AUTHENTICATED: sp_dc cookie missing from vault session. Please log in.');
        return null;
      }

      console.log('[Spotify] Refreshing Spotify tokens via TOTP web authentication sequence...');

      // 1. Fetch latest TOTP secrets
      const secretUrls = [
        'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json',
        'https://raw.githubusercontent.com/spotandfly/spotify-secrets/main/secrets.json'
      ];

      let latestSecret = null;
      for (let i = 0; i < secretUrls.length; i++) {
        try {
          const secretsRes = await wisp.fetch(secretUrls[i]);
          if (secretsRes.status === 200) {
            const secrets = await secretsRes.json();
            if (Array.isArray(secrets) && secrets.length > 0) {
              latestSecret = secrets[secrets.length - 1];
              break;
            }
          }
        } catch (e) {
          console.warn('[Spotify] Could not fetch secrets from ' + secretUrls[i] + ': ' + e);
        }
      }

      if (!latestSecret || !latestSecret.secret) {
        console.error('[Spotify] No TOTP secret available from any remote secrets repository');
        return null;
      }

      // 2. Compute TOTP code from secret
      const otp = await this._generateOtp(latestSecret.secret);

      // 3. Request Access Token
      const cleanCookie = spDc.startsWith('sp_dc=') ? spDc : ('sp_dc=' + spDc);
      const accessUrl = 'https://open.spotify.com/api/token?reason=transport&productType=web-player' +
        '&totp=' + encodeURIComponent(otp) +
        '&totpServer=' + encodeURIComponent(otp) +
        '&totpVer=' + encodeURIComponent(String(latestSecret.version));

      const accessRes = await wisp.fetch(accessUrl, {
        headers: {
          'Cookie': cleanCookie,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/'
        }
      });

      if (accessRes.status !== 200) {
        console.error('[Spotify] Access token request failed with status ' + accessRes.status);
        return null;
      }

      const accessData = await accessRes.json();
      if (!accessData || !accessData.accessToken) {
        console.error('[Spotify] Response JSON missing accessToken');
        return null;
      }

      // 4. Request Client Token
      let clientToken = null;
      try {
        const deviceId = await wisp.crypto.randomHex(32);
        const clientTokenRes = await wisp.fetch('https://clienttoken.spotify.com/v1/clienttoken', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            client_data: {
              client_id: accessData.clientId,
              client_version: '1.2.96.238.g5c95ebca',
              js_sdk_data: {
                device_brand: 'unknown',
                device_id: deviceId,
                device_model: 'unknown',
                device_type: 'computer',
                os: 'windows',
                os_version: 'NT 10.0'
              }
            }
          })
        });

        if (clientTokenRes.status === 200) {
          const clientData = await clientTokenRes.json();
          if (clientData && clientData.response_type === 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
            clientToken = (clientData.granted_token && clientData.granted_token.token) || null;
          }
        }
      } catch (e) {
        console.warn('[Spotify] Client token acquisition warning: ' + e);
      }

      const cleanSpDc = cleanCookie.replace(/^sp_dc=/, '');
      const newSession = {
        accessToken: accessData.accessToken,
        clientToken: clientToken || '',
        cookies: { sp_dc: cleanSpDc },
        expiresAtMs: accessData.accessTokenExpirationTimestampMs || (Date.now() + 3600000),
        clientId: accessData.clientId
      };

      await wisp.service.setSession(this.serviceId, newSession);
      console.log('[Spotify] Tokens refreshed successfully and persisted to vault (expires in: ' +
        Math.round((newSession.expiresAtMs - Date.now()) / 1000) + 's)');

      return newSession;
    });
  }

  async _generateOtp(secretValue) {
    const secretCipherBytes = [];
    for (let i = 0; i < secretValue.length; i++) {
      secretCipherBytes.push(secretValue.charCodeAt(i) ^ ((i % 33) + 9));
    }
    const cipherString = secretCipherBytes.join('');
    const cipherBytes = [];
    for (let i = 0; i < cipherString.length; i++) {
      cipherBytes.push(cipherString.charCodeAt(i));
    }

    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let t = 0;
    let n = 0;
    let base32Secret = '';
    for (let i = 0; i < cipherBytes.length; i++) {
      n = (n << 8) | cipherBytes[i];
      t += 8;
      while (t >= 5) {
        base32Secret += alphabet[(n >> (t - 5)) & 31];
        t -= 5;
      }
    }
    if (t > 0) {
      base32Secret += alphabet[(n << (5 - t)) & 31];
    }

    return await wisp.crypto.totp(base32Secret);
  }

  async login() {
    if (!wisp.auth || typeof wisp.auth.openLogin !== 'function') {
      console.warn('[Spotify] wisp.auth.openLogin is not available in JS runtime');
      return null;
    }
    const res = await wisp.auth.openLogin({
      url: 'https://accounts.spotify.com/en/login',
      title: 'Log in to Spotify',
      targetCookies: ['sp_dc']
    });
    if (res && res.cookies && res.cookies.sp_dc) {
      await wisp.service.setSession(this.serviceId, {
        cookies: { sp_dc: res.cookies.sp_dc }
      });
      return await this.getTokens(true);
    }
    return null;
  }

  async logout() {
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
