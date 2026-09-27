// Spotify Metadata Provider for Wisp
// Powered by Service Realm Vault (wisp.service) for independent authentication & token caching.
// Provides catalog search, tracks, albums, artists, playlists, user library, canvas, and mutations.

const SPOTIFY_BASE62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const APP_VERSION = '1.2.96.238.g5c95ebca';

// ---------------------------------------------------------------------------
// Base62 <-> Hex GID conversion
// ---------------------------------------------------------------------------
function spotifyIdToHexGid(id) {
  if (!id) return '';
  const clean = id.includes(':') ? id.split(':').pop() : id;
  if (clean.length !== 22) return clean;

  const bytes = [0];
  for (let i = 0; i < clean.length; i++) {
    const idx = SPOTIFY_BASE62.indexOf(clean[i]);
    if (idx === -1) return clean;
    let carry = idx;
    for (let j = 0; j < bytes.length; j++) {
      const val = bytes[j] * 62 + carry;
      bytes[j] = val & 0xff;
      carry = val >> 8;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  let hex = '';
  for (let i = bytes.length - 1; i >= 0; i--) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex.padStart(32, '0');
}

function hexGidToSpotifyId(hex) {
  if (!hex || hex.length !== 32) return hex || '';

  const bytes = [];
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substr(i, 2), 16));
  }
  const chars = [];
  let current = bytes;
  while (current.length > 0 && !(current.length === 1 && current[0] === 0)) {
    const next = [];
    let remainder = 0;
    for (let i = 0; i < current.length; i++) {
      const acc = remainder * 256 + current[i];
      const div = Math.floor(acc / 62);
      remainder = acc % 62;
      if (next.length > 0 || div > 0) {
        next.push(div);
      }
    }
    chars.push(SPOTIFY_BASE62[remainder]);
    current = next;
  }
  return chars.reverse().join('').padStart(22, '0');
}

// ---------------------------------------------------------------------------
// Authentication & Session Vault Manager
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
    const session = await this.getSession();
    const now = Date.now();

    if (!forceRefresh && session && session.accessToken && (now < (session.expiresAtMs - 60000))) {
      return session;
    }

    if (!wisp.service || typeof wisp.service.withRefreshLock !== 'function') {
      if (wisp.spotify && typeof wisp.spotify.getTokens === 'function') {
        return await wisp.spotify.getTokens({ forceRefresh: forceRefresh });
      }
      return null;
    }

    return await wisp.service.withRefreshLock(this.serviceId, async () => {
      const current = await this.getSession();
      if (!forceRefresh && current && current.accessToken && (Date.now() < (current.expiresAtMs - 60000))) {
        return current;
      }

      let spDc = (current && current.cookies && current.cookies.sp_dc) || (current && current.cookie) || null;

      if (!spDc) {
        if (wisp.spotify && typeof wisp.spotify.getTokens === 'function') {
          const legacy = await wisp.spotify.getTokens({ forceRefresh: true });
          if (legacy && legacy.accessToken) return legacy;
        }
        console.warn('[Spotify/Metadata] NOT_AUTHENTICATED: sp_dc cookie missing in vault.');
        return null;
      }

      console.log('[Spotify/Metadata] Refreshing Spotify tokens via TOTP web authentication...');

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
          console.warn('[Spotify/Metadata] Secrets fetch failed from ' + secretUrls[i] + ': ' + e);
        }
      }

      if (!latestSecret || !latestSecret.secret) {
        console.error('[Spotify/Metadata] Could not retrieve TOTP secret');
        return null;
      }

      const otp = await this._generateOtp(latestSecret.secret);
      const cleanCookie = spDc.startsWith('sp_dc=') ? spDc : ('sp_dc=' + spDc);
      const accessUrl = 'https://open.spotify.com/api/token?reason=transport&productType=web-player' +
        '&totp=' + encodeURIComponent(otp) +
        '&totpServer=' + encodeURIComponent(otp) +
        '&totpVer=' + encodeURIComponent(String(latestSecret.version));

      const accessRes = await wisp.fetch(accessUrl, {
        headers: {
          'Cookie': cleanCookie,
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/'
        }
      });

      if (accessRes.status !== 200) {
        console.error('[Spotify/Metadata] Access token request failed: ' + accessRes.status);
        return null;
      }

      const accessData = await accessRes.json();
      if (!accessData || !accessData.accessToken) {
        console.error('[Spotify/Metadata] No accessToken in response');
        return null;
      }

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
              client_version: APP_VERSION,
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
            clientToken = clientData.granted_token && clientData.granted_token.token;
          }
        }
      } catch (e) {
        console.warn('[Spotify/Metadata] Client token acquisition warning: ' + e);
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
      console.log('[Spotify/Metadata] Tokens successfully refreshed in vault (expires in: ' +
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
      console.warn('[Spotify/Metadata] wisp.auth.openLogin not available');
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

// ---------------------------------------------------------------------------
// Network Helpers with 401 Token Refresh Retries
// ---------------------------------------------------------------------------
async function queryGraphQL(operationName, sha256Hash, variables = {}) {
  let tokens = await authManager.getTokens();
  if (!tokens || !tokens.accessToken) {
    throw new Error('NOT_AUTHENTICATED: No Spotify tokens available');
  }

  const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
  const buildHeaders = (t) => ({
    'Authorization': 'Bearer ' + t.accessToken,
    'client-token': t.clientToken || '',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': USER_AGENT,
    'Origin': 'https://open.spotify.com',
    'Referer': 'https://open.spotify.com/',
    'app-platform': 'WebPlayer',
    'spotify-app-version': APP_VERSION,
    'Accept-Language': 'en'
  });

  const payload = {
    operationName: operationName,
    variables: variables,
    extensions: {
      persistedQuery: {
        version: 1,
        sha256Hash: sha256Hash
      }
    }
  };

  let res = await wisp.fetch(url, {
    method: 'POST',
    headers: buildHeaders(tokens),
    body: JSON.stringify(payload)
  });

  if (res.status === 401) {
    console.warn('[Spotify/Metadata] 401 Unauthorized for ' + operationName + ', refreshing tokens...');
    tokens = await authManager.getTokens(true);
    if (!tokens || !tokens.accessToken) {
      throw new Error('TOKEN_REFRESH_FAILED');
    }
    res = await wisp.fetch(url, {
      method: 'POST',
      headers: buildHeaders(tokens),
      body: JSON.stringify(payload)
    });
  }

  if (res.status !== 200) {
    const errText = await res.text();
    throw new Error('GraphQL ' + operationName + ' failed with status ' + res.status + ': ' + errText);
  }

  return await res.json();
}

async function fetchSpClient(endpoint, options = {}) {
  let tokens = await authManager.getTokens();
  if (!tokens || !tokens.accessToken) {
    throw new Error('NOT_AUTHENTICATED: No Spotify tokens available');
  }

  const url = endpoint.startsWith('http') ? endpoint : ('https://spclient.wg.spotify.com' + endpoint);
  const buildHeaders = (t) => Object.assign({
    'Authorization': 'Bearer ' + t.accessToken,
    'client-token': t.clientToken || '',
    'Accept': 'application/json',
    'User-Agent': USER_AGENT,
    'Origin': 'https://open.spotify.com',
    'Referer': 'https://open.spotify.com/',
    'app-platform': 'WebPlayer',
    'spotify-app-version': APP_VERSION
  }, options.headers || {});

  let res = await wisp.fetch(url, {
    method: options.method || 'GET',
    headers: buildHeaders(tokens),
    body: options.body || null
  });

  if (res.status === 401) {
    console.warn('[Spotify/Metadata] 401 Unauthorized for ' + url + ', refreshing tokens...');
    tokens = await authManager.getTokens(true);
    if (!tokens || !tokens.accessToken) {
      throw new Error('TOKEN_REFRESH_FAILED');
    }
    res = await wisp.fetch(url, {
      method: options.method || 'GET',
      headers: buildHeaders(tokens),
      body: options.body || null
    });
  }

  return res;
}

async function fetchWebApi(endpoint, options = {}) {
  let tokens = await authManager.getTokens();
  if (!tokens || !tokens.accessToken) {
    throw new Error('NOT_AUTHENTICATED: No Spotify tokens available');
  }

  const url = endpoint.startsWith('http') ? endpoint : ('https://api.spotify.com/v1/' + endpoint.replace(/^\//, ''));
  const buildHeaders = (t) => Object.assign({
    'Authorization': 'Bearer ' + t.accessToken,
    'Accept': 'application/json',
    'Content-Type': 'application/json'
  }, options.headers || {});

  let res = await wisp.fetch(url, {
    method: options.method || 'GET',
    headers: buildHeaders(tokens),
    body: options.body || null
  });

  if (res.status === 401) {
    tokens = await authManager.getTokens(true);
    if (!tokens || !tokens.accessToken) throw new Error('TOKEN_REFRESH_FAILED');
    res = await wisp.fetch(url, {
      method: options.method || 'GET',
      headers: buildHeaders(tokens),
      body: options.body || null
    });
  }

  return res;
}

// ---------------------------------------------------------------------------
// Normalization & Extraction Helpers
// ---------------------------------------------------------------------------
function extractImageUrl(obj) {
  if (!obj) return '';
  if (typeof obj === 'string') {
    if (obj.startsWith('http')) return obj;
    if (obj.startsWith('spotify:')) {
      const parts = obj.split(':');
      return 'https://i.scdn.co/image/' + parts[parts.length - 1];
    }
    return 'https://i.scdn.co/image/' + obj;
  }
  if (obj.url) return obj.url;
  const sources = obj.sources || 
                  obj.images || 
                  (obj.items && (obj.items[0]?.sources || obj.items[0]?.url ? obj.items : obj.items[0])) || 
                  (obj.coverArt && obj.coverArt.sources) ||
                  (obj.avatar && (obj.avatar.sources || obj.avatar));
  if (Array.isArray(sources) && sources.length > 0) {
    const first = sources[0];
    if (typeof first === 'string') return first;
    if (first && first.url) return first.url;
    if (first && Array.isArray(first.sources) && first.sources.length > 0) {
      return first.sources[0].url || '';
    }
  }
  if (sources && sources.url) return sources.url;
  if (sources && Array.isArray(sources.sources) && sources.sources.length > 0) {
    return sources.sources[0].url || '';
  }
  return '';
}

function extractReleaseDate(dateObj, fallback = new Date(0).toISOString()) {
  if (!dateObj) return fallback;
  if (typeof dateObj === 'string') {
    if (dateObj.includes('T')) return dateObj;
    const d = new Date(dateObj);
    return isNaN(d.getTime()) ? fallback : d.toISOString();
  }
  if (dateObj.isoString) return dateObj.isoString;
  if (typeof dateObj.year === 'number') {
    const year = dateObj.year;
    const month = typeof dateObj.month === 'number' ? dateObj.month : 1;
    const day = typeof dateObj.day === 'number' ? dateObj.day : 1;
    const d = new Date(Date.UTC(year, month - 1, day));
    return isNaN(d.getTime()) ? fallback : d.toISOString();
  }
  return fallback;
}

function extractArtists(artistsData) {
  if (!artistsData) return [];
  const list = Array.isArray(artistsData) ? artistsData : (artistsData.items || []);
  return list.map(a => {
    const rawUri = a.uri || '';
    const id = rawUri.includes(':') ? rawUri.split(':').pop() : (a.id || '');
    return {
      id: id,
      source: 'spotifyInternal',
      name: a.name || (a.profile && a.profile.name) || 'Unknown Artist',
      thumbnail_url: extractImageUrl(a.avatar || a.visuals || a.images)
    };
  });
}

function extractDurationSecs(t) {
  if (!t) return 0;

  // Direct itemV3 check
  if (t.itemV3 && t.itemV3.duration && typeof t.itemV3.duration.seconds === 'number' && t.itemV3.duration.seconds > 0) {
    return t.itemV3.duration.seconds;
  }
  // Direct itemV2 check
  if (t.itemV2 && t.itemV2.data && t.itemV2.data.trackDuration && typeof t.itemV2.data.trackDuration.totalMilliseconds === 'number' && t.itemV2.data.trackDuration.totalMilliseconds > 0) {
    return Math.round(t.itemV2.data.trackDuration.totalMilliseconds / 1000);
  }

  // 1. Direct seconds from consumptionExperienceTrait (Spotify GraphQL v3/v2)
  if (t.consumptionExperienceTrait && t.consumptionExperienceTrait.duration) {
    const d = t.consumptionExperienceTrait.duration;
    if (typeof d.seconds === 'number' && d.seconds > 0) return d.seconds;
    if (typeof d.totalMilliseconds === 'number' && d.totalMilliseconds > 0) {
      return Math.round(d.totalMilliseconds / 1000);
    }
  }

  // 2. Direct seconds field in duration object
  if (t.duration && typeof t.duration.seconds === 'number' && t.duration.seconds > 0) {
    return t.duration.seconds;
  }

  // 3. Milliseconds from trackDuration / duration object
  if (t.trackDuration) {
    if (typeof t.trackDuration.totalMilliseconds === 'number' && t.trackDuration.totalMilliseconds > 0) {
      return Math.round(t.trackDuration.totalMilliseconds / 1000);
    }
    if (typeof t.trackDuration.seconds === 'number' && t.trackDuration.seconds > 0) {
      return t.trackDuration.seconds;
    }
    if (typeof t.trackDuration === 'number' && t.trackDuration > 0) {
      return t.trackDuration > 10000 ? Math.round(t.trackDuration / 1000) : t.trackDuration;
    }
  }
  if (t.duration && typeof t.duration.totalMilliseconds === 'number' && t.duration.totalMilliseconds > 0) {
    return Math.round(t.duration.totalMilliseconds / 1000);
  }

  // 4. Milliseconds from duration_ms / durationMs
  if (typeof t.duration_ms === 'number' && t.duration_ms > 0) {
    return Math.round(t.duration_ms / 1000);
  }
  if (typeof t.durationMs === 'number' && t.durationMs > 0) {
    return Math.round(t.durationMs / 1000);
  }
  if (typeof t.totalMilliseconds === 'number' && t.totalMilliseconds > 0) {
    return Math.round(t.totalMilliseconds / 1000);
  }

  // 5. Primitive duration (could be seconds if < 10000, or ms if >= 10000)
  if (typeof t.duration === 'number' && t.duration > 0) {
    return t.duration > 10000 ? Math.round(t.duration / 1000) : t.duration;
  }

  // 6. Check inner wrappers: data, track, itemV3, itemV2
  if (t.data) {
    const s = extractDurationSecs(t.data);
    if (s > 0) return s;
  }
  if (t.track && typeof t.track === 'object') {
    const s = extractDurationSecs(t.track);
    if (s > 0) return s;
  }
  if (t.itemV3) {
    const s = extractDurationSecs(t.itemV3);
    if (s > 0) return s;
  }
  if (t.itemV2) {
    const s = extractDurationSecs(t.itemV2);
    if (s > 0) return s;
  }

  return 0;
}

function extractDurationMs(t) {
  return extractDurationSecs(t) * 1000;
}

function trackToGeneric(track) {
  if (!track) return null;
  const rawUri = track.uri || '';
  const id = rawUri.includes(':') ? rawUri.split(':').pop() : (track.id || '');
  const artists = extractArtists(track.artists);
  const isExplicit = !!(track.explicit || (track.contentRating && track.contentRating.label === 'EXPLICIT'));
  const durationSecs = extractDurationSecs(track);

  let album = null;
  const albumData = track.album || track.albumOfTrack;
  if (albumData) {
    const albumUri = albumData.uri || '';
    album = {
      id: albumUri.includes(':') ? albumUri.split(':').pop() : (albumData.id || ''),
      source: 'spotifyInternal',
      title: albumData.name || '',
      thumbnail_url: extractImageUrl(albumData.coverArt || albumData.images),
      artists: extractArtists(albumData.artists),
      label: albumData.label || '',
      release_date: extractReleaseDate(albumData.date)
    };
  }

  return {
    id: id,
    source: 'spotifyInternal',
    title: track.name || '',
    artists: artists,
    thumbnail_url: extractImageUrl(track.coverArt || track.images),
    explicit: isExplicit,
    album: album,
    duration_secs: durationSecs
  };
}

function fullAlbumToGeneric(data, offset = 0, limit = 50) {
  const album = data.albumUnion || data.album || (data.data && data.data.albumUnion) || data;
  const albumUri = album.uri || '';
  const albumId = albumUri.includes(':') ? albumUri.split(':').pop() : (album.id || '');
  const artists = extractArtists(album.artists);
  const coverUrl = extractImageUrl(album.coverArt || album.images);

  const tracksData = album.tracksV2 || album.tracks;
  const trackItems = (tracksData && tracksData.items) || [];
  const songs = trackItems.map(item => {
    let durationSecs = 0;
    if (item.itemV3 && item.itemV3.duration && typeof item.itemV3.duration.seconds === 'number' && item.itemV3.duration.seconds > 0) {
      durationSecs = item.itemV3.duration.seconds;
    } else if (item.itemV2 && item.itemV2.data && item.itemV2.data.trackDuration && typeof item.itemV2.data.trackDuration.totalMilliseconds === 'number' && item.itemV2.data.trackDuration.totalMilliseconds > 0) {
      durationSecs = Math.round(item.itemV2.data.trackDuration.totalMilliseconds / 1000);
    } else {
      durationSecs = extractDurationSecs(item);
    }

    const t = (item.track && item.track.data) || item.track || item.data || item;
    const song = trackToGeneric(t);
    if (song) {
      if (durationSecs > 0) {
        song.duration_secs = durationSecs;
      }
      if (!song.album) {
        song.album = {
          id: albumId,
          source: 'spotifyInternal',
          title: album.name || '',
          thumbnail_url: coverUrl,
          artists: artists,
          label: album.label || '',
          release_date: extractReleaseDate(album.date)
        };
      }
    }
    return song;
  }).filter(Boolean);

  const totalCount = (tracksData && tracksData.totalCount) || songs.length;
  const hasMore = (offset + limit) < totalCount;

  return {
    id: albumId,
    source: 'spotifyInternal',
    title: album.name || '',
    thumbnail_url: coverUrl,
    artists: artists,
    label: album.label || '',
    release_date: extractReleaseDate(album.date),
    explicit: false,
    songs: songs,
    duration_secs: songs.reduce((acc, s) => acc + (s.duration_secs || 0), 0),
    total: totalCount,
    has_more: hasMore
  };
}

function fullPlaylistToGeneric(data, offset = 0, limit = 50) {
  let pl = (data.data && data.data.playlistV2) || data.playlistV2 || (data.data && data.data.playlist) || data;
  const uri = pl.uri || '';
  const id = uri.includes(':') ? uri.split(':').pop() : (pl.id || '');
  const coverUrl = extractImageUrl(pl.images || pl.coverArt);

  const owner = pl.ownerV2 || pl.owner || {};
  const ownerData = owner.data || owner;
  const ownerAvatar = ownerData.avatar || 
                      ownerData.images || 
                      (ownerData.visualIdentity && ownerData.visualIdentity.image) ||
                      owner.avatar || 
                      owner.images;
  const author = {
    id: ownerData.username || ownerData.id || owner.username || owner.id || '',
    source: 'spotifyInternal',
    display_name: ownerData.name || ownerData.displayName || owner.name || owner.displayName || 'Spotify User',
    avatar_url: extractImageUrl(ownerAvatar)
  };

  const contents = (pl.content && pl.content.items) || (pl.tracks && pl.tracks.items) || [];
  const songs = [];
  let trackNum = offset;

  for (let i = 0; i < contents.length; i++) {
    const item = contents[i];
    const sourceData = (item.itemV3 && item.itemV3.data) ||
                       (item.itemV2 && item.itemV2.data) ||
                       (item.track && item.track.data) ||
                       item.track ||
                       item.data ||
                       item;
    if (!sourceData) continue;

    trackNum++;
    const trackUri = sourceData.uri || (item.itemV2 && item.itemV2.data && item.itemV2.data.uri) || (item.itemV3 && item.itemV3.data && item.itemV3.data.uri) || '';
    const trackId = trackUri.includes(':') ? trackUri.split(':').pop() : (sourceData.id || '');
    
    const identity = sourceData.identityTrait;
    const title = (identity && identity.name) || sourceData.name || 'Unknown Track';
    
    // Artists
    let artists = [];
    if (identity && identity.contributors && identity.contributors.items) {
      artists = identity.contributors.items.map(c => {
        const cUri = c.uri || '';
        return {
          id: cUri.includes(':') ? cUri.split(':').pop() : (c.id || ''),
          source: 'spotifyInternal',
          name: c.name || '',
          thumbnail_url: ''
        };
      });
    } else {
      artists = extractArtists(sourceData.artists);
    }

    const albumData = sourceData.albumOfTrack || sourceData.album;
    let album = null;
    if (albumData) {
      const aUri = albumData.uri || '';
      album = {
        id: aUri.includes(':') ? aUri.split(':').pop() : (albumData.id || ''),
        source: 'spotifyInternal',
        title: albumData.name || '',
        thumbnail_url: extractImageUrl(albumData.coverArt || albumData.images),
        artists: extractArtists(albumData.artists),
        label: albumData.label || '',
        release_date: extractReleaseDate(albumData.date)
      };
    }

    let durationSecs = 0;
    if (item.itemV3 && item.itemV3.duration && typeof item.itemV3.duration.seconds === 'number' && item.itemV3.duration.seconds > 0) {
      durationSecs = item.itemV3.duration.seconds;
    } else if (item.itemV2 && item.itemV2.data && item.itemV2.data.trackDuration && typeof item.itemV2.data.trackDuration.totalMilliseconds === 'number' && item.itemV2.data.trackDuration.totalMilliseconds > 0) {
      durationSecs = Math.round(item.itemV2.data.trackDuration.totalMilliseconds / 1000);
    } else {
      durationSecs = extractDurationSecs(item) || extractDurationSecs(sourceData);
    }

    const addedAtStr = (item.addedAt && item.addedAt.isoString) || item.added_at || new Date().toISOString();
    const trackThumbnail = extractImageUrl(sourceData.coverArt || sourceData.images || (identity && identity.coverArt));

    songs.push({
      id: trackId,
      uid: item.uid || (item.itemV2 && item.itemV2.uid) || (item.itemV3 && item.itemV3.uid) || ('item_' + trackNum),
      source: 'spotifyInternal',
      title: title,
      artists: artists,
      thumbnail_url: trackThumbnail,
      explicit: !!(sourceData.contentRating && sourceData.contentRating.label === 'EXPLICIT'),
      album: album,
      duration_secs: durationSecs,
      added_at: addedAtStr,
      track_number: trackNum
    });
  }

  const totalCount = (pl.content && pl.content.totalCount) || (pl.tracks && pl.tracks.total) || songs.length;
  const hasMore = (offset + limit) < totalCount;

  return {
    id: id,
    source: 'spotifyInternal',
    title: pl.name || '',
    description: pl.description || (pl.details && pl.details.description) || '',
    thumbnail_url: coverUrl,
    author: author,
    songs: songs,
    duration_secs: songs.reduce((acc, s) => acc + (s.duration_secs || 0), 0),
    total: totalCount,
    has_more: hasMore
  };
}

function fullArtistToGeneric(data) {
  const artist = (data.data && data.data.artistUnion) || data.artistUnion || data;
  const uri = artist.uri || '';
  const id = uri.includes(':') ? uri.split(':').pop() : (artist.id || '');
  const avatarUrl = extractImageUrl(artist.visuals && artist.visuals.avatarImage);

  const discography = (artist.discography && artist.discography.topTracks && artist.discography.topTracks.items) || [];
  const topSongs = discography.map(item => {
    const t = item.track || item;
    return trackToGeneric(t);
  }).filter(Boolean);

  const albumItems = (artist.discography && artist.discography.albums && artist.discography.albums.items) || [];
  const albums = albumItems.map(item => {
    const a = (item.releases && item.releases.items && item.releases.items[0]) || item;
    const aUri = a.uri || '';
    return {
      id: aUri.includes(':') ? aUri.split(':').pop() : (a.id || ''),
      source: 'spotifyInternal',
      title: a.name || '',
      thumbnail_url: extractImageUrl(a.coverArt || a.images),
      artists: extractArtists(a.artists),
      label: a.label || '',
      release_date: extractReleaseDate(a.date)
    };
  });

  const followers = (artist.stats && artist.stats.followers) || 0;
  const monthlyListeners = (artist.stats && artist.stats.monthlyListeners) || null;
  const biography = (artist.profile && artist.profile.biography && artist.profile.biography.text) || '';

  return {
    id: id,
    source: 'spotifyInternal',
    name: (artist.profile && artist.profile.name) || artist.name || '',
    description: biography,
    thumbnail_url: avatarUrl,
    followers: followers,
    monthly_listeners: monthlyListeners,
    top_songs: topSongs,
    albums: albums
  };
}

function simplifiedAlbumToGeneric(data) {
  const cleanId = data.uri ? data.uri.split(':').pop() : (data.id || '');
  const artists = (data.artists && data.artists.items) || [];
  const artistNames = artists.map(a => a.profile && a.profile.name || a.name || '').filter(Boolean);
  return {
    id: cleanId,
    source: 'spotifyInternal',
    title: data.name || '',
    artist: artistNames.join(', '),
    artists: artists.map(a => ({
      id: a.uri ? a.uri.split(':').pop() : (a.id || ''),
      source: 'spotifyInternal',
      name: a.profile && a.profile.name || a.name || '',
      thumbnail_url: ''
    })),
    thumbnail_url: extractImageUrl(data.coverArt),
    release_date: extractReleaseDate(data.date, ''),
    total_tracks: (data.tracks && data.tracks.totalCount) || 0,
    type: data.type || 'album'
  };
}

function simplifiedArtistToGeneric(data) {
  const cleanId = data.uri ? data.uri.split(':').pop() : (data.id || '');
  const profile = data.profile || {};
  return {
    id: cleanId,
    source: 'spotifyInternal',
    name: profile.name || data.name || '',
    thumbnail_url: extractImageUrl(data.visuals)
  };
}

// ---------------------------------------------------------------------------
// Exported Provider Interface
// ---------------------------------------------------------------------------

async function getTrack(trackId) {
  const cleanId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
  const hexGid = spotifyIdToHexGid(cleanId);
  const endpoint = 'https://spclient.wg.spotify.com/metadata/4/track/' + hexGid + '?market=from_token';

  const res = await fetchSpClient(endpoint);
  if (res.status !== 200) {
    throw new Error('getTrack failed: ' + res.status);
  }

  const response = await res.json();
  const trackGid = response.gid || cleanId;
  const standardId = hexGidToSpotifyId(trackGid);

  const albumMap = response.album;
  const dateMap = albumMap ? (albumMap.release_date || albumMap.date) : null;
  let releaseDate = new Date(0).toISOString();
  if (dateMap && dateMap.year) {
    releaseDate = new Date(dateMap.year, (dateMap.month || 1) - 1, dateMap.day || 1).toISOString();
  }

  const coverFileId = response.cover_group && response.cover_group.image && response.cover_group.image[0] && response.cover_group.image[0].file_id;
  const trackCoverUrl = coverFileId ? ('https://i.scdn.co/image/' + coverFileId) : '';

  const artists = (response.artist || []).map(a => ({
    id: hexGidToSpotifyId(a.gid || ''),
    name: a.name || '',
    source: 'spotifyInternal',
    thumbnail_url: ''
  }));

  let album = null;
  if (albumMap) {
    const aCoverFileId = albumMap.cover_group && albumMap.cover_group.image && albumMap.cover_group.image[0] && albumMap.cover_group.image[0].file_id;
    album = {
      id: hexGidToSpotifyId(albumMap.gid || ''),
      title: albumMap.name || '',
      source: 'spotifyInternal',
      thumbnail_url: aCoverFileId ? ('https://i.scdn.co/image/' + aCoverFileId) : trackCoverUrl,
      artists: (albumMap.artist || []).map(a => ({
        id: hexGidToSpotifyId(a.gid || ''),
        name: a.name || '',
        source: 'spotifyInternal',
        thumbnail_url: ''
      })),
      label: albumMap.label || '',
      release_date: releaseDate
    };
  }

  const durationSecs = extractDurationSecs(response);
  return {
    id: standardId,
    source: 'spotifyInternal',
    title: response.name || '',
    artists: artists,
    thumbnail_url: trackCoverUrl,
    explicit: !!response.explicit,
    album: album,
    duration_secs: durationSecs
  };
}

async function getAlbum(albumId, options = {}) {
  const cleanId = albumId.includes(':') ? albumId.split(':').pop() : albumId;
  const offset = options.offset || 0;
  const limit = options.limit || 50;

  const data = await queryGraphQL(
    'getAlbum',
    'b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10',
    {
      uri: 'spotify:album:' + cleanId,
      locale: '',
      offset: offset,
      limit: limit
    }
  );

  return fullAlbumToGeneric(data, offset, limit);
}

async function getMoreAlbumTracks(albumId, options = {}) {
  const album = await getAlbum(albumId, options);
  return album.songs || [];
}

async function getPlaylist(playlistId, options = {}) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const offset = options.offset || 0;
  const limit = options.limit || 50;

  const data = await queryGraphQL(
    'fetchPlaylist',
    '346811f856fb0b7e4f6c59f8ebea78dd081c6e2fb01b77c954b26259d5fc6763',
    {
      uri: 'spotify:playlist:' + cleanId,
      offset: offset,
      limit: limit,
      enableWatchFeedEntrypoint: true
    }
  );

  return fullPlaylistToGeneric(data, offset, limit);
}

async function getMorePlaylistTracks(playlistId, options = {}) {
  const playlist = await getPlaylist(playlistId, options);
  return playlist.songs || [];
}

async function getArtist(artistId) {
  const cleanId = artistId.includes(':') ? artistId.split(':').pop() : artistId;

  const data = await queryGraphQL(
    'queryArtistOverview',
    '5b9e64f43843fa3a9b6a98543600299b0a2cbbbccfdcdcef2402eb9c1017ca4c',
    {
      uri: 'spotify:artist:' + cleanId,
      locale: 'intl-pt',
      preReleaseV2: false
    }
  );

  return fullArtistToGeneric(data);
}

async function search(query, options = {}) {
  const limit = options.limit || 20;
  const offset = options.offset || 0;

  const data = await queryGraphQL(
    'searchDesktop',
    '3c9d3f60dac5dea3876b6db3f534192b1c1d90032c4233c1bbaba526db41eb31',
    {
      searchTerm: query,
      offset: offset,
      limit: limit,
      numberOfTopResults: 5,
      includeAudiobooks: true,
      includeArtistHasConcertsField: false,
      includePreReleases: true,
      includeAuthors: false
    }
  );

  const searchData = (data.data && data.data.searchV2) || {};
  const rawTracks = (searchData.tracksV2 && searchData.tracksV2.items) || [];
  const tracks = rawTracks.map(item => {
    const itemData = (item.item && item.item.data) || item;
    return trackToGeneric(itemData);
  }).filter(Boolean);

  const rawArtists = (searchData.artists && searchData.artists.items) || [];
  const artists = rawArtists.map(item => {
    const itemData = (item.data) || item;
    const uri = itemData.uri || '';
    return {
      id: uri.includes(':') ? uri.split(':').pop() : (itemData.id || ''),
      source: 'spotifyInternal',
      name: (itemData.profile && itemData.profile.name) || itemData.name || '',
      thumbnail_url: extractImageUrl(itemData.visuals && itemData.visuals.avatarImage)
    };
  });

  const rawAlbums = (searchData.albumsV2 && searchData.albumsV2.items) || [];
  const albums = rawAlbums.map(item => {
    const itemData = (item.data) || item;
    const uri = itemData.uri || '';
    return {
      id: uri.includes(':') ? uri.split(':').pop() : (itemData.id || ''),
      source: 'spotifyInternal',
      title: itemData.name || '',
      thumbnail_url: extractImageUrl(itemData.coverArt),
      artists: extractArtists(itemData.artists),
      label: '',
      release_date: (itemData.date && itemData.date.isoString) || new Date(0).toISOString(),
      explicit: false,
      duration_secs: 0
    };
  });

  const rawPlaylists = (searchData.playlists && searchData.playlists.items) || [];
  const playlists = rawPlaylists.map(item => {
    const itemData = (item.data) || item;
    const uri = itemData.uri || '';
    const owner = itemData.ownerV2 || {};
    return {
      id: uri.includes(':') ? uri.split(':').pop() : (itemData.id || ''),
      source: 'spotifyInternal',
      title: itemData.name || '',
      description: itemData.description || '',
      thumbnail_url: extractImageUrl(itemData.images),
      author: {
        id: (owner.data && owner.data.username) || '',
        source: 'spotifyInternal',
        display_name: (owner.data && owner.data.name) || 'Spotify User',
        avatar_url: ''
      },
      duration_secs: 0
    };
  });

  let bestMatch = null;
  const topResult = (searchData.topResultsV2 && searchData.topResultsV2.items && searchData.topResultsV2.items[0]);
  if (topResult && topResult.item && topResult.item.data) {
    const topData = topResult.item.data;
    const typename = topData.__typename;
    if (typename === 'TrackResponseWrapper' || typename === 'Track') {
      const s = trackToGeneric(topData);
      if (s) bestMatch = { kind: 'track', track: s };
    } else if (typename === 'ArtistResponseWrapper' || typename === 'Artist') {
      const aUri = topData.uri || '';
      bestMatch = {
        kind: 'artist',
        artist: {
          id: aUri.includes(':') ? aUri.split(':').pop() : (topData.id || ''),
          source: 'spotifyInternal',
          name: (topData.profile && topData.profile.name) || topData.name || '',
          thumbnail_url: extractImageUrl(topData.visuals && topData.visuals.avatarImage)
        }
      };
    } else if (typename === 'AlbumResponseWrapper' || typename === 'Album') {
      const a = fullAlbumToGeneric(topData);
      if (a) bestMatch = { kind: 'album', album: a };
    } else if (typename === 'PlaylistResponseWrapper' || typename === 'Playlist') {
      const p = fullPlaylistToGeneric(topData);
      if (p) bestMatch = { kind: 'playlist', playlist: p };
    }
  }

  if (!bestMatch && tracks.length > 0) {
    bestMatch = { kind: 'track', track: tracks[0] };
  }

  return {
    tracks: tracks,
    artists: artists,
    albums: albums,
    playlists: playlists,
    best_match: bestMatch
  };
}

async function getCanvasUrl(trackId) {
  const cleanId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
  const uri = 'spotify:track:' + cleanId;

  try {
    const data = await queryGraphQL(
      'canvas',
      '575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f',
      { trackUri: uri }
    );
    const canvasObj = (data.data && data.data.trackUnion && data.data.trackUnion.canvas) ||
      (data.data && data.data.canvas);
    return (canvasObj && canvasObj.url) || null;
  } catch (e) {
    console.warn('[Spotify/Metadata] Canvas fetch error: ' + e);
    return null;
  }
}

async function getUserProfile() {
  const data = await queryGraphQL(
    'profileAttributes',
    '53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced',
    {}
  );
  const profile = data.data && data.data.me && data.data.me.profile;
  if (!profile) return null;
  return {
    id: profile.username || '',
    displayName: profile.name || '',
    avatarUrl: profile.avatar || ''
  };
}

async function getUserHome(options = {}) {
  let timezone = options.timezone;
  if (!timezone) {
    try {
      if (typeof Intl !== 'undefined' && Intl.DateTimeFormat) {
        timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      }
    } catch (_) {}
  }
  timezone = timezone || 'UTC';
  const data = await queryGraphQL(
    'home',
    '66aedae92842f23d5254ba3371f4f7def0bf00342d0cbe3fea3de198d9414a60',
    {
      homeEndUserIntegration: 'INTEGRATION_WEB_PLAYER',
      timeZone: timezone,
      sp_t: '',
      facet: '',
      sectionItemsLimit: 10
    }
  );

  const homeObj = (data.data && data.data.home) || {};
  const sectionItems = (homeObj.sectionContainer && homeObj.sectionContainer.sections && homeObj.sectionContainer.sections.items) || [];
  const sections = {};

  function extractTitle(sec, index) {
    const d = sec.data || {};
    const t = d.title || sec.title;
    if (typeof t === 'string' && t.trim().length > 0) return t.trim();
    if (t && typeof t === 'object') {
      if (t.transformedLabel && t.transformedLabel.trim().length > 0) return t.transformedLabel.trim();
      if (t.translatedBaseText && t.translatedBaseText.trim().length > 0) return t.translatedBaseText.trim();
      if (t.text && t.text.trim().length > 0) return t.text.trim();
    }
    if (d.headerEntity && d.headerEntity.title) {
      const ht = d.headerEntity.title;
      if (typeof ht === 'string' && ht.trim().length > 0) return ht.trim();
      if (ht && typeof ht === 'object') {
        if (ht.transformedLabel && ht.transformedLabel.trim().length > 0) return ht.transformedLabel.trim();
        if (ht.translatedBaseText && ht.translatedBaseText.trim().length > 0) return ht.translatedBaseText.trim();
        if (ht.text && ht.text.trim().length > 0) return ht.text.trim();
      }
    }
    if (d.name && typeof d.name === 'string' && d.name.trim().length > 0) return d.name.trim();
    if (index === 0) return 'Recents';
    return 'Section ' + (index + 1);
  }

  for (let i = 0; i < sectionItems.length; i++) {
    const sec = sectionItems[i];
    const title = extractTitle(sec, i);
    const items = (sec.sectionItems && sec.sectionItems.items) || [];
    const convertedItems = [];

    for (let j = 0; j < items.length; j++) {
      const itemData = (items[j].content && items[j].content.data) || items[j].data || items[j];
      const typename = itemData.__typename;
      if (typename === 'Playlist' || typename === 'PlaylistResponseWrapper') {
        convertedItems.push({ __wispType: 'GenericPlaylist', data: fullPlaylistToGeneric(itemData) });
      } else if (typename === 'Album' || typename === 'AlbumResponseWrapper') {
        convertedItems.push({ __wispType: 'GenericAlbum', data: fullAlbumToGeneric(itemData) });
      } else if (typename === 'Artist' || typename === 'ArtistResponseWrapper') {
        convertedItems.push({
          __wispType: 'GenericSimpleArtist',
          data: {
            id: (itemData.uri && itemData.uri.split(':').pop()) || itemData.id || '',
            source: 'spotifyInternal',
            name: (itemData.profile && itemData.profile.name) || itemData.name || '',
            thumbnail_url: extractImageUrl(itemData.visuals && itemData.visuals.avatarImage)
          }
        });
      } else if (typename === 'Track' || typename === 'TrackResponseWrapper') {
        const t = trackToGeneric(itemData);
        if (t) convertedItems.push({ __wispType: 'GenericSong', data: t });
      }
    }

    if (convertedItems.length > 0) {
      if (sections[title]) {
        const existingIds = new Set(sections[title].map(it => it.data && it.data.id).filter(Boolean));
        for (const it of convertedItems) {
          if (!it.data || !it.data.id || !existingIds.has(it.data.id)) {
            sections[title].push(it);
            if (it.data && it.data.id) existingIds.add(it.data.id);
          }
        }
      } else {
        sections[title] = convertedItems;
      }
    }
  }

  return { sections: sections };
}

async function getUserSavedTracks(options = {}) {
  const offset = options.offset || 0;
  const limit = options.limit || 50;

  const data = await queryGraphQL(
    'fetchLibraryTracks',
    '087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240',
    { offset: offset, limit: limit }
  );

  const tracksObj = (data.data && data.data.me && data.data.me.library && data.data.me.library.tracks) || {};
  const items = tracksObj.items || [];
  const songs = [];
  let trackNum = offset;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const trackData = (item.track && item.track.data) || item.track;
    if (!trackData) continue;
    trackNum++;

    const t = trackToGeneric(trackData);
    if (!t) continue;

    songs.push({
      id: t.id,
      uid: item.uid || ('item_' + trackNum),
      source: 'spotifyInternal',
      title: t.title,
      artists: t.artists,
      thumbnail_url: t.thumbnail_url,
      explicit: t.explicit,
      album: t.album,
      duration_secs: t.duration_secs,
      added_at: (item.addedAt && item.addedAt.isoString) || new Date().toISOString(),
      track_number: trackNum
    });
  }

  return songs;
}

async function getUserSavedTracksAll() {
  const allTracks = [];
  let offset = 0;
  const limit = 50;

  while (true) {
    const page = await getUserSavedTracks({ offset: offset, limit: limit });
    if (!page || page.length === 0) break;
    allTracks.push(...page);
    if (page.length < limit) break;
    offset += limit;
  }

  return allTracks;
}

async function getUserLibrary(options = {}) {
  const sortMode = options.sortMode || 'recent';
  let sortOrder = 'Recently Added';
  if (sortMode === 'alphabetical') sortOrder = 'Alphabetical';
  else if (sortMode === 'recent') sortOrder = 'Recents';
  else if (sortMode === 'recentlyAdded') sortOrder = 'Recently Added';

  let expanded = options.expandedFolders || [];
  let data = await queryGraphQL(
    'libraryV3',
    '390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455',
    {
      expandedFolders: expanded,
      features: ['LIKED_SONGS'],
      flatten: false,
      folderUri: null,
      includeFoldersWhenFlattening: true,
      limit: 100,
      offset: 0,
      order: sortOrder,
      textFilter: null
    }
  );

  let libraryItems = (data.data && data.data.me && data.data.me.libraryV3 && data.data.me.libraryV3.items) || [];

  if ((!options.expandedFolders || options.expandedFolders.length === 0) && libraryItems.length > 0) {
    const remoteFolderIds = [];
    for (let i = 0; i < libraryItems.length; i++) {
      const itemData = (libraryItems[i].item && libraryItems[i].item.data) || libraryItems[i].data || libraryItems[i];
      if (itemData && (itemData.__typename === 'Folder' || itemData.type === 'folder')) {
        const uri = itemData.uri || itemData._uri || itemData.id || '';
        if (uri) remoteFolderIds.push(uri);
      }
    }
    if (remoteFolderIds.length > 0) {
      data = await queryGraphQL(
        'libraryV3',
        '390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455',
        {
          expandedFolders: remoteFolderIds,
          features: ['LIKED_SONGS'],
          flatten: false,
          folderUri: null,
          includeFoldersWhenFlattening: true,
          limit: 100,
          offset: 0,
          order: sortOrder,
          textFilter: null
        }
      );
      libraryItems = (data.data && data.data.me && data.data.me.libraryV3 && data.data.me.libraryV3.items) || [];
    }
  }

  const allOrganized = [];
  const savedAlbums = [];
  const savedPlaylists = [];
  const savedArtists = [];

  for (let i = 0; i < libraryItems.length; i++) {
    const itemData = (libraryItems[i].item && libraryItems[i].item.data) || libraryItems[i].data || libraryItems[i];
    if (!itemData) continue;
    const typename = itemData.__typename;

    if (typename === 'Playlist' || typename === 'PlaylistResponseWrapper') {
      const pl = fullPlaylistToGeneric(itemData);
      savedPlaylists.push(pl);
      allOrganized.push(pl);
    } else if (typename === 'Album' || typename === 'AlbumResponseWrapper') {
      savedAlbums.push(fullAlbumToGeneric(itemData));
      allOrganized.push(simplifiedAlbumToGeneric(itemData));
    } else if (typename === 'Artist' || typename === 'ArtistResponseWrapper') {
      savedArtists.push(fullArtistToGeneric(itemData));
      allOrganized.push(simplifiedArtistToGeneric(itemData));
    } else if (typename === 'Folder') {
      const uri = itemData.uri || itemData._uri || '';
      allOrganized.push({
        __typename: 'Folder',
        uri: uri,
        id: uri,
        name: itemData.name || '',
        playlistCount: itemData.playlistCount || 0
      });
    }
  }

  return {
    all_organized: allOrganized,
    saved_albums: savedAlbums,
    saved_playlists: savedPlaylists,
    saved_artists: savedArtists
  };
}

async function getUserPlaylists(options = {}) {
  const lib = await getUserLibrary(options);
  const items = lib.saved_playlists || [];
  const offset = options.offset || 0;
  const limit = options.limit || 20;
  return items.slice(offset, offset + limit);
}

async function getUserAlbums(options = {}) {
  const lib = await getUserLibrary(options);
  const items = lib.saved_albums || [];
  const offset = options.offset || 0;
  const limit = options.limit || 20;
  return items.slice(offset, offset + limit);
}

async function getUserFollowedArtists(options = {}) {
  const lib = await getUserLibrary(options);
  const items = lib.saved_artists || [];
  const offset = options.offset || 0;
  const limit = options.limit || 20;
  return items.slice(offset, offset + limit).map(a => ({
    id: a.id,
    source: 'spotifyInternal',
    name: a.name,
    thumbnail_url: a.thumbnail_url
  }));
}

// ---------------------------------------------------------------------------
// Library Mutations
// ---------------------------------------------------------------------------

async function likeTrack(trackId) {
  const cleanId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
  await queryGraphQL(
    'addToLibrary',
    '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d',
    { libraryItemUris: ['spotify:track:' + cleanId] }
  );
  return true;
}

async function unlikeTrack(trackId) {
  const cleanId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
  await queryGraphQL(
    'applyCurations',
    '05b739a3a73091c213385233b9d3ed8a857c2ca29d2eebadb3d04ed12e288697',
    {
      input: {
        curations: [
          {
            contextUri: 'spotify:collection:tracks',
            curationType: 'UNCURATE'
          }
        ],
        itemUris: ['spotify:track:' + cleanId]
      }
    }
  );
  return true;
}

async function saveAlbum(albumId) {
  const cleanId = albumId.includes(':') ? albumId.split(':').pop() : albumId;
  await queryGraphQL(
    'addToLibrary',
    '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d',
    { libraryItemUris: ['spotify:album:' + cleanId] }
  );
  return true;
}

async function unsaveAlbum(albumId) {
  const cleanId = albumId.includes(':') ? albumId.split(':').pop() : albumId;
  await queryGraphQL(
    'applyCurations',
    '05b739a3a73091c213385233b9d3ed8a857c2ca29d2eebadb3d04ed12e288697',
    {
      input: {
        curations: [
          {
            contextUri: 'spotify:collection:albums',
            curationType: 'UNCURATE'
          }
        ],
        itemUris: ['spotify:album:' + cleanId]
      }
    }
  );
  return true;
}

async function followArtist(artistId) {
  const cleanId = artistId.includes(':') ? artistId.split(':').pop() : artistId;
  await queryGraphQL(
    'addToLibrary',
    '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d',
    { libraryItemUris: ['spotify:artist:' + cleanId] }
  );
  return true;
}

async function unfollowArtist(artistId) {
  const cleanId = artistId.includes(':') ? artistId.split(':').pop() : artistId;
  await queryGraphQL(
    'applyCurations',
    '05b739a3a73091c213385233b9d3ed8a857c2ca29d2eebadb3d04ed12e288697',
    {
      input: {
        curations: [
          {
            contextUri: 'spotify:collection:artists',
            curationType: 'UNCURATE'
          }
        ],
        itemUris: ['spotify:artist:' + cleanId]
      }
    }
  );
  return true;
}

async function getCuratedStatus(trackIds) {
  if (!Array.isArray(trackIds) || trackIds.length === 0) return {};
  const uris = trackIds.map(id => {
    const cleanId = id.includes(':') ? id.split(':').pop() : id;
    return 'spotify:track:' + cleanId;
  });

  try {
    const data = await queryGraphQL(
      'checkLibraryStatus',
      '14867b4e8c187e14cb1396a84d1bc94541cb4ea1db6a2ecb1ff87d7b275ea13f',
      { uris: uris }
    );
    const results = {};
    const items = (data.data && data.data.lookup) || [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const rawUri = item.uri || '';
      const cleanId = rawUri.includes(':') ? rawUri.split(':').pop() : rawUri;
      results[cleanId] = !!item.inLibrary;
    }
    return results;
  } catch (e) {
    console.warn('[Spotify/Metadata] getCuratedStatus error: ' + e);
    return {};
  }
}

async function createPlaylist(options) {
  const user = await getUserProfile();
  if (!user || !user.id) throw new Error('Cannot create playlist: User not found');

  const res = await fetchWebApi('users/' + encodeURIComponent(user.id) + '/playlists', {
    method: 'POST',
    body: JSON.stringify({
      name: options.name || 'New Playlist',
      description: options.description || '',
      public: options.isPublic !== undefined ? options.isPublic : true
    })
  });

  if (res.status !== 200 && res.status !== 201) {
    throw new Error('createPlaylist failed: ' + res.status);
  }

  const json = await res.json();
  return json.id;
}

async function renamePlaylist(playlistId, name) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const res = await fetchWebApi('playlists/' + encodeURIComponent(cleanId), {
    method: 'PUT',
    body: JSON.stringify({ name: name })
  });
  return res.status === 200;
}

async function deletePlaylist(playlistId) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const res = await fetchWebApi('playlists/' + encodeURIComponent(cleanId) + '/followers', {
    method: 'DELETE'
  });
  return res.status === 200;
}

async function addTracksToPlaylist(playlistId, trackIds) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const uris = trackIds.map(id => 'spotify:track:' + (id.includes(':') ? id.split(':').pop() : id));
  const res = await fetchWebApi('playlists/' + encodeURIComponent(cleanId) + '/tracks', {
    method: 'POST',
    body: JSON.stringify({ uris: uris })
  });
  return res.status === 200 || res.status === 201;
}

async function removeTracksFromPlaylist(playlistId, trackIds) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const tracks = trackIds.map(id => ({
    uri: 'spotify:track:' + (id.includes(':') ? id.split(':').pop() : id)
  }));
  const res = await fetchWebApi('playlists/' + encodeURIComponent(cleanId) + '/tracks', {
    method: 'DELETE',
    body: JSON.stringify({ tracks: tracks })
  });
  return res.status === 200;
}

async function getSimilarTracks(trackId) {
  const cleanTrackId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
  const res = await fetchSpClient('/inspiredby-mix/v2/seed_to_playlist/spotify:track:' + cleanTrackId + '?response-format=json');
  if (res.status !== 200) {
    throw new Error('getSimilarTracks radio failed: ' + res.status);
  }
  const data = await res.json();
  const mediaItems = data && data.mediaItems;
  if (!mediaItems || !mediaItems.length) return [];
  const playlistUri = mediaItems[0].uri || '';
  const playlistId = playlistUri.includes(':') ? playlistUri.split(':').pop() : playlistUri;
  const playlist = await getPlaylist(playlistId);
  if (playlist && Array.isArray(playlist.songs)) {
    return playlist.songs.slice(1);
  }
  return [];
}

async function addPlaylistToFolder(playlistId, folderId) {
  const user = await getUserProfile();
  if (!user || !user.id) throw new Error('User not found');
  let trueFolderId = folderId;
  let truePlaylistId = playlistId;
  if (folderId.startsWith('spotify:user:')) {
    const parts = folderId.split(':');
    if (parts.length >= 5) trueFolderId = parts[4];
  }
  if (playlistId.startsWith('spotify:playlist:')) {
    const parts = playlistId.split(':');
    if (parts.length >= 3) truePlaylistId = parts[2];
  }

  const url = '/playlist/v2/user/' + encodeURIComponent(user.id) + '/rootlist/changes';
  const body = {
    deltas: [
      {
        ops: [
          {
            kind: 'MOV',
            mov: {
              items: [{ uri: 'spotify:playlist:' + truePlaylistId, attributes: {} }],
              addAfterItem: { uri: 'spotify:start-group:' + trueFolderId, attributes: {} }
            }
          }
        ],
        info: { source: { client: 'WEBPLAYER' } }
      }
    ]
  };

  const res = await fetchSpClient(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (res.status !== 200) {
    throw new Error('addPlaylistToFolder failed: ' + res.status);
  }
  const json = await res.json();
  if (json && json.changeRequiresResync === true) {
    throw new Error('addPlaylistToFolder requires resync');
  }
  return true;
}

async function removePlaylistFromFolder(playlistId) {
  const user = await getUserProfile();
  if (!user || !user.id) throw new Error('User not found');
  let truePlaylistId = playlistId;
  if (playlistId.startsWith('spotify:playlist:')) {
    const parts = playlistId.split(':');
    if (parts.length >= 3) truePlaylistId = parts[2];
  }

  const url = '/playlist/v2/user/' + encodeURIComponent(user.id) + '/rootlist/changes';
  const body = {
    deltas: [
      {
        ops: [
          {
            kind: 'MOV',
            mov: {
              items: [{ uri: 'spotify:playlist:' + truePlaylistId, attributes: {} }],
              addFirst: true
            }
          }
        ],
        info: { source: { client: 'WEBPLAYER' } }
      }
    ]
  };

  const res = await fetchSpClient(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (res.status !== 200) {
    throw new Error('removePlaylistFromFolder failed: ' + res.status);
  }
  const json = await res.json();
  if (json && json.changeRequiresResync === true) {
    throw new Error('removePlaylistFromFolder requires resync');
  }
  return true;
}

async function getUserProfileView(userId, options = {}) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const pLimit = options.playlistLimit || 10;
  const aLimit = options.artistLimit || 10;
  const eLimit = options.episodeLimit || 10;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) +
    '?playlist_limit=' + pLimit + '&artist_limit=' + aLimit + '&episode_limit=' + eLimit + '&market=from_token';

  const res = await fetchSpClient(url);
  if (res.status !== 200) {
    throw new Error('getUserProfileView failed: ' + res.status);
  }
  const data = await res.json();
  const uri = data.uri || data.id || '';
  const cleanUriId = uri.includes(':') ? uri.split(':').pop() : (uri || cleanId);

  const recentArtists = (data.recently_played_artists || []).map(a => ({
    id: a.uri ? a.uri.split(':').pop() : (a.id || ''),
    source: 'spotifyInternal',
    name: a.name || '',
    thumbnail_url: a.image_url || extractImageUrl(a.images) || ''
  }));

  const publicPlaylists = (data.public_playlists || []).map(p => ({
    id: p.uri ? p.uri.split(':').pop() : (p.id || ''),
    source: 'spotifyInternal',
    title: p.name || '',
    thumbnail_url: p.image_url || extractImageUrl(p.images) || '',
    total_tracks: 0
  }));

  return {
    id: cleanUriId,
    source: 'spotifyInternal',
    display_name: data.name || data.display_name || 'Unknown User',
    avatar_url: data.image_url || extractImageUrl(data.images) || '',
    follower_count: data.followers_count || 0,
    following_count: data.following_count || 0,
    recent_artists: recentArtists,
    public_playlists: publicPlaylists,
    followers: [],
    following: []
  };
}

async function getUserFollowers(userId) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) + '/followers?market=from_token';
  const res = await fetchSpClient(url);
  if (res.status !== 200) return [];
  const data = await res.json();
  const items = data.profiles || data.followers || data.items || [];
  return items.map(u => ({
    id: u.uri ? u.uri.split(':').pop() : (u.id || ''),
    name: u.name || u.display_name || '',
    thumbnail_url: u.image_url || extractImageUrl(u.images) || '',
    source: 'spotifyInternal'
  }));
}

async function getUserFollowing(userId) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) + '/following?market=from_token';
  const res = await fetchSpClient(url);
  if (res.status !== 200) return [];
  const data = await res.json();
  const items = data.profiles || data.following || data.items || [];
  return items.map(u => ({
    id: u.uri ? u.uri.split(':').pop() : (u.id || ''),
    name: u.name || u.display_name || '',
    thumbnail_url: u.image_url || extractImageUrl(u.images) || '',
    source: 'spotifyInternal'
  }));
}

async function getRecommended(playlistId, skippedTrackIds = [], numResults = 20) {
  const cleanPlaylistId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const cleanSkipped = skippedTrackIds.map(id => id.includes(':') ? id.split(':').pop() : id);
  const body = {
    numResults: numResults,
    playlistURI: 'spotify:playlist:' + cleanPlaylistId,
    trackSkipIDs: cleanSkipped
  };
  const res = await fetchSpClient('/playlistextender/extendp/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (res.status !== 200) {
    throw new Error('getRecommended failed: ' + res.status);
  }
  const data = await res.json();
  const tracks = data.recommendedTracks || (data.result && data.result.tracks) || data.tracks || [];
  return tracks.map((t, idx) => {
    const rawUri = t.uri || '';
    const cleanTrackId = (t.id ? (t.id.includes(':') ? t.id.split(':').pop() : t.id) : (rawUri.includes(':') ? rawUri.split(':').pop() : (t.originalId || '')));
    const albumData = t.album || {};
    const albumCover = albumData.imageUrl || albumData.largeImageUrl || extractImageUrl(albumData.images || albumData.coverArt) || '';
    const durationMs = extractDurationMs(t);
    return {
      id: cleanTrackId,
      uid: t.uid || ('rec_' + (idx + 1)),
      source: 'spotifyInternal',
      title: t.name || t.trackName || '',
      artists: (t.artists || []).map(a => ({
        id: (a.id ? (a.id.includes(':') ? a.id.split(':').pop() : a.id) : (a.uri ? a.uri.split(':').pop() : '')),
        source: 'spotifyInternal',
        name: a.name || a.artistName || 'Unknown Artist',
        thumbnail_url: ''
      })),
      thumbnail_url: '',
      explicit: !!t.explicit,
      album: {
        id: (albumData.id ? (albumData.id.includes(':') ? albumData.id.split(':').pop() : albumData.id) : (albumData.uri ? albumData.uri.split(':').pop() : '')),
        title: albumData.name || albumData.albumName || 'Unknown Album',
        source: 'spotifyInternal',
        thumbnail_url: albumCover,
        artists: [],
        label: '',
        release_date: new Date(0).toISOString()
      },
      duration_secs: Math.round(durationMs / 1000),
      added_at: new Date().toISOString(),
      track_number: idx + 1
    };
  });
}

async function isAuthenticated() {
  const session = await authManager.getSession();
  return !!(session && ((session.cookies && session.cookies.sp_dc) || session.cookie || session.accessToken));
}

// ---------------------------------------------------------------------------
// Protobuf Writer & Reader for Track Descriptors (Genres)
// ---------------------------------------------------------------------------
class SimpleProtoWriter {
  constructor() {
    this.buffer = [];
  }
  writeVarint(value) {
    let v = value >>> 0;
    while (v >= 0x80) {
      this.buffer.push((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
    this.buffer.push(v & 0x7F);
  }
  writeTag(fieldNumber, wireType) {
    this.writeVarint((fieldNumber << 3) | wireType);
  }
  writeString(fieldNumber, str) {
    const bytes = [];
    for (let i = 0; i < str.length; i++) {
      let code = str.charCodeAt(i);
      if (code < 0x80) bytes.push(code);
      else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else {
        bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    this.writeBytes(fieldNumber, bytes);
  }
  writeBytes(fieldNumber, bytes) {
    this.writeTag(fieldNumber, 2);
    this.writeVarint(bytes.length);
    for (let i = 0; i < bytes.length; i++) this.buffer.push(bytes[i]);
  }
  writeInt32(fieldNumber, val) {
    this.writeTag(fieldNumber, 0);
    this.writeVarint(val);
  }
  writeMessage(fieldNumber, writer) {
    this.writeBytes(fieldNumber, writer.toBytes());
  }
  toBytes() {
    return new Uint8Array(this.buffer);
  }
}

class SimpleProtoReader {
  constructor(uint8Array) {
    this.bytes = uint8Array;
    this.offset = 0;
  }
  hasMore() {
    return this.offset < this.bytes.length;
  }
  readVarint() {
    let result = 0;
    let shift = 0;
    while (this.offset < this.bytes.length) {
      const b = this.bytes[this.offset++];
      result |= (b & 0x7F) << shift;
      shift += 7;
      if ((b & 0x80) === 0) break;
    }
    return result >>> 0;
  }
  readTag() {
    if (!this.hasMore()) return null;
    const tag = this.readVarint();
    return { field: tag >> 3, wire: tag & 0x07 };
  }
  readLengthDelimited() {
    const len = this.readVarint();
    const slice = this.bytes.subarray(this.offset, this.offset + len);
    this.offset += len;
    return slice;
  }
  readString() {
    const slice = this.readLengthDelimited();
    let str = '';
    for (let i = 0; i < slice.length; i++) {
      str += String.fromCharCode(slice[i]);
    }
    try {
      return decodeURIComponent(escape(str));
    } catch (_) {
      return str;
    }
  }
  skipField(wireType) {
    if (wireType === 0) this.readVarint();
    else if (wireType === 1) this.offset += 8;
    else if (wireType === 2) {
      const len = this.readVarint();
      this.offset += len;
    } else if (wireType === 5) this.offset += 4;
  }
}

function parseTrackDescriptorsResponse(bytes) {
  const genres = [];
  try {
    const root = new SimpleProtoReader(bytes);
    while (root.hasMore()) {
      const tag = root.readTag();
      if (!tag) break;
      if (tag.field === 2 && tag.wire === 2) {
        const arr = new SimpleProtoReader(root.readLengthDelimited());
        let kind = 0;
        const extDataSlices = [];
        while (arr.hasMore()) {
          const aTag = arr.readTag();
          if (!aTag) break;
          if (aTag.field === 2 && aTag.wire === 0) {
            kind = arr.readVarint();
          } else if (aTag.field === 3 && aTag.wire === 2) {
            extDataSlices.push(arr.readLengthDelimited());
          } else {
            arr.skipField(aTag.wire);
          }
        }
        if (kind === 6) {
          for (const extBytes of extDataSlices) {
            let anyValue = null;
            const ext = new SimpleProtoReader(extBytes);
            while (ext.hasMore()) {
              const eTag = ext.readTag();
              if (!eTag) break;
              if (eTag.field === 3 && eTag.wire === 2) {
                const any = new SimpleProtoReader(ext.readLengthDelimited());
                while (any.hasMore()) {
                  const anyTag = any.readTag();
                  if (!anyTag) break;
                  if (anyTag.field === 2 && anyTag.wire === 2) {
                    anyValue = any.readLengthDelimited();
                  } else {
                    any.skipField(anyTag.wire);
                  }
                }
              } else {
                ext.skipField(eTag.wire);
              }
            }
            if (anyValue) {
              const desc = new SimpleProtoReader(anyValue);
              while (desc.hasMore()) {
                const dTag = desc.readTag();
                if (!dTag) break;
                if (dTag.field === 1 && dTag.wire === 2) {
                  const item = new SimpleProtoReader(desc.readLengthDelimited());
                  let rawTag = null;
                  let displayName = null;
                  while (item.hasMore()) {
                    const iTag = item.readTag();
                    if (!iTag) break;
                    if (iTag.field === 1 && iTag.wire === 2) {
                      rawTag = item.readString();
                    } else if (iTag.field === 5 && iTag.wire === 2) {
                      displayName = item.readString();
                    } else {
                      item.skipField(iTag.wire);
                    }
                  }
                  const resolved = displayName || rawTag;
                  if (resolved) genres.push(resolved);
                } else {
                  desc.skipField(dTag.wire);
                }
              }
            }
          }
        }
      } else {
        root.skipField(tag.wire);
      }
    }
  } catch (e) {
    console.warn('[Spotify] Failed parsing track descriptors: ' + e);
  }
  return genres;
}

async function getTrackGenres(trackId) {
  try {
    if (!trackId || typeof trackId !== 'string') return [];
    const cleanTrackId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
    const trackUri = 'spotify:track:' + cleanTrackId;
    const token = await authManager.getAccessToken();
    if (!token) return [];

    const queryWriter = new SimpleProtoWriter();
    queryWriter.writeInt32(1, 6);

    const entityWriter = new SimpleProtoWriter();
    entityWriter.writeString(1, trackUri);
    entityWriter.writeMessage(2, queryWriter);

    const rootWriter = new SimpleProtoWriter();
    rootWriter.writeString(1, 'PT');
    rootWriter.writeString(2, 'premium');
    const traceId = [];
    for (let i = 0; i < 16; i++) traceId.push(Math.floor(Math.random() * 256));
    rootWriter.writeBytes(3, traceId);
    rootWriter.writeMessage(2, entityWriter);

    const bodyBytes = rootWriter.toBytes();
    const session = await authManager.getSession();
    const clientToken = session ? (session.clientToken || '') : '';

    const headers = {
      'Authorization': 'Bearer ' + token,
      'App-Platform': 'Win32_x86_64',
      'Accept': 'application/protobuf',
      'Content-Type': 'application/protobuf',
      'Spotify-App-Version': APP_VERSION,
      'User-Agent': USER_AGENT
    };
    if (clientToken) headers['Client-Token'] = clientToken;

    const res = await wisp.fetch('https://gew1-spclient.spotify.com/extended-metadata/v0/extended-metadata', {
      method: 'POST',
      headers: headers,
      body: bodyBytes
    });

    if (res.status !== 200) {
      return [];
    }

    const bytes = await res.bytes();
    return parseTrackDescriptorsResponse(bytes);
  } catch (e) {
    console.warn('[Spotify] Failed getTrackGenres: ' + e);
    return [];
  }
}

// ---------------------------------------------------------------------------
// Module Exports
// ---------------------------------------------------------------------------
const SpotifyMetadataProvider = {
  getTrack,
  getAlbum,
  getMoreAlbumTracks,
  getPlaylist,
  getMorePlaylistTracks,
  getArtist,
  search,
  getCanvasUrl,
  getUserProfile,
  getUserProfileView,
  getUserFollowers,
  getUserFollowing,
  getRecommended,
  getUserHome,
  getUserPlaylists,
  getUserAlbums,
  getUserFollowedArtists,
  getUserSavedTracks,
  getUserSavedTracksAll,
  getUserLibrary,
  likeTrack,
  unlikeTrack,
  saveAlbum,
  unsaveAlbum,
  followArtist,
  unfollowArtist,
  getCuratedStatus,
  createPlaylist,
  renamePlaylist,
  deletePlaylist,
  addTracksToPlaylist,
  removeTracksFromPlaylist,
  getSimilarTracks,
  addPlaylistToFolder,
  removePlaylistFromFolder,
  getTrackGenres,
  isAuthenticated,
  login: () => authManager.login(),
  logout: () => authManager.logout()
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SpotifyMetadataProvider;
}

// Register on globalThis for runtime execution
for (const [key, fn] of Object.entries(SpotifyMetadataProvider)) {
  globalThis[key] = fn;
}

