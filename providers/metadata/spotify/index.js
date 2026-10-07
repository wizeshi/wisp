// Spotify Metadata Provider for wisp
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
    body: JSON.stringify(payload),
    label: operationName
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
      body: JSON.stringify(payload),
      label: operationName
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
    if (obj.startsWith('spotify:mosaic:')) {
      const parts = obj.split(':');
      const hash = parts[2] || parts[parts.length - 1];
      return hash ? ('https://i.scdn.co/image/' + hash) : '';
    }
    if (obj.startsWith('spotify:')) {
      const parts = obj.split(':');
      return 'https://i.scdn.co/image/' + parts[parts.length - 1];
    }
    return 'https://i.scdn.co/image/' + obj;
  }
  if (obj.url) return obj.url;
  // Handle Spotify's { image: { data: { sources } } } wrapper (visualIdentityTrait images)
  if (obj.image && obj.image.data) {
    const r = extractImageUrl(obj.image.data);
    if (r) return r;
  }
  if (obj.image && obj.image.sources) {
    const r = extractImageUrl(obj.image.sources);
    if (r) return r;
  }
  // Handle Spotify's visualIdentityTrait { squareCoverImage, sixteenByNineCoverImage }
  const visualCover = obj.squareCoverImage || obj.sixteenByNineCoverImage;
  if (visualCover) {
    const r = extractImageUrl(visualCover);
    if (r) return r;
  }
  // Handle avatarImage wrapper (e.g. artist visuals.avatarImage in albums)
  if (obj.avatarImage) {
    const r = extractImageUrl(obj.avatarImage);
    if (r) return r;
  }
  // Handle visuals wrapper (e.g. artist.visuals)
  if (obj.visuals) {
    const r = extractImageUrl(obj.visuals);
    if (r) return r;
  }
  const sources = obj.sources || 
                  obj.images || 
                  (obj.avatarImage && (obj.avatarImage.sources || obj.avatarImage)) ||
                  (obj.visuals && (obj.visuals.avatarImage?.sources || obj.visuals.avatarImage || obj.visuals)) ||
                  (obj.items && (obj.items[0]?.sources || obj.items[0]?.url ? obj.items : obj.items[0])) || 
                  (obj.coverArt && (obj.coverArt.sources || obj.coverArt)) ||
                  (obj.avatar && (obj.avatar.sources || obj.avatar));
  if (Array.isArray(sources) && sources.length > 0) {
    // Pick the highest resolution source if dimensions are available
    const valid = sources.filter(s => s && (typeof s === 'string' || s.url));
    if (valid.length > 0) {
      const sorted = [...valid].sort((a, b) => {
        const wA = (typeof a === 'object' && a.width) || 0;
        const wB = (typeof b === 'object' && b.width) || 0;
        return wB - wA;
      });
      const best = sorted[0];
      if (typeof best === 'string') return best;
      if (best && best.url) return best.url;
    }
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
      source: 'spotify',
      name: a.name || (a.profile && a.profile.name) || 'Unknown Artist',
      thumbnail_url: extractImageUrl(
        (a.visuals && a.visuals.avatarImage) ||
        a.avatarImage ||
        a.avatar ||
        a.visuals ||
        a.images ||
        a
      )
    };
  });
}

function extractDurationSecs(t) {
  if (!t) return 0;

  // Direct itemV3 check (duration lives at itemV3.data.consumptionExperienceTrait.duration, not itemV3.duration)
  const _v3d = t.itemV3 && t.itemV3.data && t.itemV3.data.consumptionExperienceTrait && t.itemV3.data.consumptionExperienceTrait.duration;
  if (_v3d && typeof _v3d.seconds === 'number' && _v3d.seconds > 0) {
    return _v3d.seconds;
  }
  if (_v3d && typeof _v3d.totalMilliseconds === 'number' && _v3d.totalMilliseconds > 0) {
    return Math.round(_v3d.totalMilliseconds / 1000);
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

function trackToGeneric(track, albumLookup = null, defaultArtist = null) {
  if (!track) return null;
  const rawUri = track.uri ||
                 track._uri ||
                 (track.track && (track.track.uri || track.track._uri)) ||
                 (track.data && (track.data.uri || track.data._uri)) ||
                 '';
  const id = rawUri.includes(':')
    ? rawUri.split(':').pop()
    : (track.id ||
       track._id ||
       (track.track && (track.track.id || track.track._id)) ||
       (track.data && (track.data.id || track.data._id)) ||
       '');
  let artists = extractArtists(track.artists);
  if ((!artists || artists.length === 0) && defaultArtist) {
    artists = [{
      id: defaultArtist.id || '',
      source: 'spotify',
      name: defaultArtist.name || '',
      thumbnail_url: defaultArtist.thumbnail_url || ''
    }];
  }

  const isExplicit = !!(
    (track.explicit === true) ||
    (track.contentRating && track.contentRating.label === 'EXPLICIT') ||
    (track.consumptionExperienceTrait && Array.isArray(track.consumptionExperienceTrait.contentRatings) &&
     track.consumptionExperienceTrait.contentRatings.some(r => r === 'CONTENT_RATING_EXPLICIT' || r === 'EXPLICIT')) ||
    (Array.isArray(track.attributes) && track.attributes.includes('EXPLICIT'))
  );
  const durationSecs = extractDurationSecs(track);

  let album = null;
  const albumData = track.albumOfTrack || track.album;
  if (albumData) {
    const albumUri = albumData.uri || albumData._uri || (albumData.id ? ('spotify:album:' + albumData.id) : '');
    const albumId = albumUri.includes(':') ? albumUri.split(':').pop() : (albumData.id || albumData._id || '');

    let matchedAlbum = null;
    if (albumLookup) {
      matchedAlbum = (albumUri && albumLookup.get(albumUri)) || (albumId && albumLookup.get(albumId));
    }

    if (matchedAlbum) {
      album = {
        id: matchedAlbum.id || albumId,
        source: 'spotify',
        title: matchedAlbum.title || matchedAlbum.name || '',
        thumbnail_url: extractImageUrl(albumData.coverArt || albumData.images) || matchedAlbum.thumbnail_url || '',
        artists: (matchedAlbum.artists && matchedAlbum.artists.length > 0) ? matchedAlbum.artists : (artists || []),
        label: matchedAlbum.label || '',
        release_date: matchedAlbum.release_date || extractReleaseDate(albumData.date)
      };
    } else {
      let albumArtists = extractArtists(albumData.artists);
      if ((!albumArtists || albumArtists.length === 0) && artists && artists.length > 0) {
        albumArtists = artists;
      }
      album = {
        id: albumId,
        source: 'spotify',
        title: albumData.name || '',
        thumbnail_url: extractImageUrl(albumData.coverArt || albumData.images),
        artists: albumArtists || [],
        label: albumData.label || '',
        release_date: extractReleaseDate(albumData.date)
      };
    }
  }

  return {
    id: id,
    source: 'spotify',
    title: track.name || '',
    artists: artists,
    thumbnail_url: extractImageUrl(track.coverArt || track.images || (album && album.thumbnail_url)) ||
                   extractImageUrl(track.visualIdentityTrait) || '',
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
    const _albV3dur = item.itemV3 && item.itemV3.data && item.itemV3.data.consumptionExperienceTrait && item.itemV3.data.consumptionExperienceTrait.duration;
    if (_albV3dur && typeof _albV3dur.seconds === 'number' && _albV3dur.seconds > 0) {
      durationSecs = _albV3dur.seconds;
    } else if (item.itemV3 && item.itemV3.duration && typeof item.itemV3.duration.seconds === 'number' && item.itemV3.duration.seconds > 0) {
      durationSecs = item.itemV3.duration.seconds;
    } else if (item.itemV2 && item.itemV2.data && item.itemV2.data.trackDuration && typeof item.itemV2.data.trackDuration.totalMilliseconds === 'number' && item.itemV2.data.trackDuration.totalMilliseconds > 0) {
      durationSecs = Math.round(item.itemV2.data.trackDuration.totalMilliseconds / 1000);
    } else {
      durationSecs = extractDurationSecs(item);
    }

    const t = (item.track && item.track.data) || item.track || (item.itemV2 && item.itemV2.data) || item.data || item;
    const song = trackToGeneric(t);
    if (song) {
      if (durationSecs > 0) {
        song.duration_secs = durationSecs;
      }
      if (!song.album) {
        song.album = {
          id: albumId,
          source: 'spotify',
          title: album.name || '',
          thumbnail_url: coverUrl,
          artists: artists,
          label: album.label || '',
          release_date: extractReleaseDate(album.date)
        };
      }
      song.thumbnail_url = coverUrl;
    }
    return song;
  }).filter(Boolean);

  const totalCount = (tracksData && tracksData.totalCount) || songs.length;
  const hasMore = (offset + limit) < totalCount;

  return {
    id: albumId,
    source: 'spotify',
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

// ---------------------------------------------------------------------------
// Shared playlist-item extractor (used by both fetchPlaylist and
// fetchPlaylistContents response parsers so the logic lives in one place).
// ---------------------------------------------------------------------------
function extractPlaylistItems(contents, offset) {
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
    const trackUri = sourceData.uri ||
                     sourceData._uri ||
                     (item.track && (item.track.uri || item.track._uri)) ||
                     (item.itemV2 && item.itemV2.data && (item.itemV2.data.uri || item.itemV2.data._uri)) ||
                     (item.itemV3 && item.itemV3.data && (item.itemV3.data.uri || item.itemV3.data._uri)) ||
                     item.uri ||
                     item._uri ||
                     '';
    const trackId = trackUri.includes(':')
      ? trackUri.split(':').pop()
      : (sourceData.id ||
         sourceData._id ||
         (item.track && (item.track.id || item.track._id)) ||
         item.id ||
         item._id ||
         '');

    const identity = sourceData.identityTrait;
    const title = (identity && identity.name) || sourceData.name || 'Unknown Track';

    let artists = [];
    if (identity && identity.contributors && identity.contributors.items) {
      artists = identity.contributors.items.map(c => {
        const cUri = c.uri || '';
        return {
          id: cUri.includes(':') ? cUri.split(':').pop() : (c.id || ''),
          source: 'spotify',
          name: c.name || '',
          thumbnail_url: ''
        };
      });
    } else {
      artists = extractArtists(sourceData.artists);
    }

    const albumData = (item.itemV2 && item.itemV2.data && item.itemV2.data.albumOfTrack) ||
                      sourceData.albumOfTrack ||
                      sourceData.album;
    let album = null;
    if (albumData) {
      const aUri = albumData.uri || '';
      album = {
        id: aUri.includes(':') ? aUri.split(':').pop() : (albumData.id || ''),
        source: 'spotify',
        title: albumData.name || '',
        thumbnail_url: extractImageUrl(albumData.coverArt || albumData.images),
        artists: extractArtists(albumData.artists),
        label: albumData.label || '',
        release_date: extractReleaseDate(albumData.date || null)
      };
    } else if (identity && identity.contentHierarchyParent) {
      const parent = identity.contentHierarchyParent;
      const pUri = parent.uri || '';
      const pId = pUri.includes(':') ? pUri.split(':').pop() : (parent.id || '');
      const pName = (parent.identityTrait && parent.identityTrait.name) || parent.name || '';
      const pDate = (parent.publishingMetadataTrait && parent.publishingMetadataTrait.firstPublishedAt && parent.publishingMetadataTrait.firstPublishedAt.isoString) || null;
      album = {
        id: pId,
        source: 'spotify',
        title: pName,
        thumbnail_url: extractImageUrl(sourceData.coverArt || sourceData.visualIdentityTrait) || '',
        artists: artists,
        label: '',
        release_date: extractReleaseDate(pDate)
      };
    }

    let durationSecs = 0;
    const _plV3dur = item.itemV3 && item.itemV3.data && item.itemV3.data.consumptionExperienceTrait && item.itemV3.data.consumptionExperienceTrait.duration;
    if (_plV3dur && typeof _plV3dur.seconds === 'number' && _plV3dur.seconds > 0) {
      durationSecs = _plV3dur.seconds;
    } else if (item.itemV3 && item.itemV3.duration && typeof item.itemV3.duration.seconds === 'number' && item.itemV3.duration.seconds > 0) {
      durationSecs = item.itemV3.duration.seconds;
    } else if (item.itemV2 && item.itemV2.data && item.itemV2.data.trackDuration && typeof item.itemV2.data.trackDuration.totalMilliseconds === 'number' && item.itemV2.data.trackDuration.totalMilliseconds > 0) {
      durationSecs = Math.round(item.itemV2.data.trackDuration.totalMilliseconds / 1000);
    } else {
      durationSecs = extractDurationSecs(item) || extractDurationSecs(sourceData);
    }

    const addedAtStr = (item.addedAt && item.addedAt.isoString) || item.added_at || new Date().toISOString();
    const trackThumbnail =
      extractImageUrl(sourceData.coverArt || sourceData.images || (identity && identity.coverArt)) ||
      extractImageUrl(sourceData.visualIdentityTrait) ||
      (album && album.thumbnail_url) || '';

    const isExplicit = !!(
      (sourceData.explicit === true) ||
      (item.explicit === true) ||
      (sourceData.contentRating && sourceData.contentRating.label === 'EXPLICIT') ||
      (item.itemV2 && item.itemV2.data && item.itemV2.data.contentRating && item.itemV2.data.contentRating.label === 'EXPLICIT') ||
      (item.track && item.track.contentRating && item.track.contentRating.label === 'EXPLICIT') ||
      (sourceData.consumptionExperienceTrait && Array.isArray(sourceData.consumptionExperienceTrait.contentRatings) &&
       sourceData.consumptionExperienceTrait.contentRatings.some(r => r === 'CONTENT_RATING_EXPLICIT' || r === 'EXPLICIT')) ||
      (item.itemV3 && item.itemV3.data && item.itemV3.data.consumptionExperienceTrait &&
       Array.isArray(item.itemV3.data.consumptionExperienceTrait.contentRatings) &&
       item.itemV3.data.consumptionExperienceTrait.contentRatings.some(r => r === 'CONTENT_RATING_EXPLICIT' || r === 'EXPLICIT')) ||
      (Array.isArray(item.attributes) && item.attributes.includes('EXPLICIT'))
    );

    songs.push({
      id: trackId,
      uid: item.uid || (item.itemV2 && item.itemV2.uid) || (item.itemV3 && item.itemV3.uid) || ('item_' + trackNum),
      source: 'spotify',
      title: title,
      artists: artists,
      thumbnail_url: trackThumbnail,
      explicit: isExplicit,
      album: album,
      duration_secs: durationSecs,
      added_at: addedAtStr,
      track_number: trackNum
    });
  }

  return songs;
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
    source: 'spotify',
    display_name: ownerData.name || ownerData.displayName || owner.name || owner.displayName || 'Spotify User',
    avatar_url: extractImageUrl(ownerAvatar)
  };

  const contents = (pl.content && pl.content.items) || (pl.tracks && pl.tracks.items) || [];
  const songs = extractPlaylistItems(contents, offset);

  const totalCount = (pl.content && pl.content.totalCount) || (pl.tracks && pl.tracks.total) || songs.length;
  const hasMore = (offset + limit) < totalCount;

  return {
    id: id,
    source: 'spotify',
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

async function fullArtistToGeneric(data) {
  const artist = (data.data && data.data.artistUnion) || data.artistUnion || data;
  const uri = artist.uri || '';
  const id = uri.includes(':') ? uri.split(':').pop() : (artist.id || '');
  const artistName = (artist.profile && artist.profile.name) || artist.name || '';
  const avatarUrl = extractImageUrl(artist.visuals && artist.visuals.avatarImage);
  const defaultArtist = {
    id: id,
    source: 'spotify',
    name: artistName,
    thumbnail_url: avatarUrl
  };

  const discography = artist.discography || {};
  const relatedContent = artist.relatedContent || {};
  const albumLookup = new Map();

  function registerAlbum(item) {
    if (!item) return;
    const a = (item.releases && item.releases.items && item.releases.items[0]) || item;
    const aUri = a.uri || (a.id ? ('spotify:album:' + a.id) : '');
    const aId = aUri.includes(':') ? aUri.split(':').pop() : (a.id || '');
    if (!aId) return;

    let albArtists = extractArtists(a.artists);
    if (!albArtists || albArtists.length === 0) {
      albArtists = [defaultArtist];
    }

    const albumObj = {
      id: aId,
      source: 'spotify',
      title: a.name || '',
      thumbnail_url: extractImageUrl(a.coverArt || a.images),
      artists: albArtists,
      label: a.label || '',
      release_date: extractReleaseDate(a.date)
    };

    albumLookup.set(aId, albumObj);
    if (aUri) albumLookup.set(aUri, albumObj);
  }

  const collections = [
    discography.popularReleasesAlbums && discography.popularReleasesAlbums.items,
    discography.albums && discography.albums.items,
    discography.singles && discography.singles.items,
    discography.compilations && discography.compilations.items,
    discography.latest ? [discography.latest] : null,
    relatedContent.appearsOn && relatedContent.appearsOn.items
  ];

  for (const col of collections) {
    if (Array.isArray(col)) {
      for (const item of col) {
        registerAlbum(item);
      }
    }
  }

  const topTracks = (discography.topTracks && discography.topTracks.items) || [];
  const topSongs = topTracks.map(item => {
    const t = item.track || item;
    return trackToGeneric(t, albumLookup, defaultArtist);
  }).filter(Boolean);

  // If any top songs are still missing album title, fetch the missing album(s)
  const missingAlbumPromises = [];
  const missingAlbumIds = new Set();
  for (const song of topSongs) {
    if (song.album && (!song.album.title || song.album.title.trim() === '')) {
      if (song.album.id && !missingAlbumIds.has(song.album.id)) {
        missingAlbumIds.add(song.album.id);
        missingAlbumPromises.push(
          getAlbum(song.album.id).catch(() => null)
        );
      }
    }
  }

  if (missingAlbumPromises.length > 0) {
    const fetchedAlbums = await Promise.all(missingAlbumPromises);
    for (const fetched of fetchedAlbums) {
      if (fetched && fetched.id) {
        for (const song of topSongs) {
          if (song.album && song.album.id === fetched.id) {
            song.album = {
              id: fetched.id,
              source: 'spotify',
              title: fetched.title,
              thumbnail_url: song.album.thumbnail_url || fetched.thumbnail_url,
              artists: (fetched.artists && fetched.artists.length > 0) ? fetched.artists : [defaultArtist],
              label: fetched.label || song.album.label || '',
              release_date: fetched.release_date || song.album.release_date
            };
          }
        }
      }
    }
  }

  const albumItems = (discography.albums && discography.albums.items) || [];
  const albums = albumItems.map(item => {
    const a = (item.releases && item.releases.items && item.releases.items[0]) || item;
    const aUri = a.uri || '';
    const aId = aUri.includes(':') ? aUri.split(':').pop() : (a.id || '');
    let albArtists = extractArtists(a.artists);
    if (!albArtists || albArtists.length === 0) {
      albArtists = [defaultArtist];
    }
    return {
      id: aId,
      source: 'spotify',
      title: a.name || '',
      thumbnail_url: extractImageUrl(a.coverArt || a.images),
      artists: albArtists,
      label: a.label || '',
      release_date: extractReleaseDate(a.date)
    };
  });

  const followers = (artist.stats && artist.stats.followers) || 0;
  const monthlyListeners = (artist.stats && artist.stats.monthlyListeners) || null;
  const biography = (artist.profile && artist.profile.biography && artist.profile.biography.text) || '';

  return {
    id: id,
    source: 'spotify',
    name: artistName,
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
    source: 'spotify',
    title: data.name || '',
    artist: artistNames.join(', '),
    artists: artists.map(a => ({
      id: a.uri ? a.uri.split(':').pop() : (a.id || ''),
      source: 'spotify',
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
    source: 'spotify',
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
    source: 'spotify',
    thumbnail_url: ''
  }));

  let album = null;
  if (albumMap) {
    const aCoverFileId = albumMap.cover_group && albumMap.cover_group.image && albumMap.cover_group.image[0] && albumMap.cover_group.image[0].file_id;
    album = {
      id: hexGidToSpotifyId(albumMap.gid || ''),
      title: albumMap.name || '',
      source: 'spotify',
      thumbnail_url: aCoverFileId ? ('https://i.scdn.co/image/' + aCoverFileId) : trackCoverUrl,
      artists: (albumMap.artist || []).map(a => ({
        id: hexGidToSpotifyId(a.gid || ''),
        name: a.name || '',
        source: 'spotify',
        thumbnail_url: ''
      })),
      label: albumMap.label || '',
      release_date: releaseDate
    };
  }

  const durationSecs = extractDurationSecs(response);
  return {
    id: standardId,
    source: 'spotify',
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
  const limit = options.limit || 200;

  // fetchPlaylist only reliably returns ~82 tracks. For paginated requests
  // (offset > 0) we use fetchPlaylistContents which supports proper offsets.
  if (offset > 0) {
    const data = await queryGraphQL(
      'fetchPlaylistContents',
      '243c0ba2736f16da721e3a227004bbcdb8df6c846f198bd478172e00aa1faf42',
      { uri: 'spotify:playlist:' + cleanId, offset: offset, limit: limit }
    );
    const pl = (data.data && data.data.playlistV2) || data.playlistV2 || data;
    const contents = (pl.content && pl.content.items) || [];
    const totalCount = (pl.content && pl.content.totalCount) || 0;
    const songs = extractPlaylistItems(contents, offset);
    return {
      id: cleanId,
      source: 'spotify',
      title: '',
      description: '',
      thumbnail_url: '',
      author: { id: '', source: 'spotify', display_name: '', avatar_url: '' },
      songs: songs,
      duration_secs: songs.reduce((acc, s) => acc + (s.duration_secs || 0), 0),
      total: totalCount,
      has_more: (offset + limit) < totalCount
    };
  }

  const data = await queryGraphQL(
    'fetchPlaylist',
    '346811f856fb0b7e4f6c59f8ebea78dd081c6e2fb01b77c954b26259d5fc6763',
    {
      uri: 'spotify:playlist:' + cleanId,
      offset: 0,
      limit: limit,
      enableWatchFeedEntrypoint: true
    }
  );

  return fullPlaylistToGeneric(data, offset, limit);
}

async function getMorePlaylistTracks(playlistId, options = {}) {
  const cleanId = playlistId.includes(':') ? playlistId.split(':').pop() : playlistId;
  const offset = options.offset || 0;
  const limit = options.limit || 50;

  const data = await queryGraphQL(
    'fetchPlaylistContents',
    '243c0ba2736f16da721e3a227004bbcdb8df6c846f198bd478172e00aa1faf42',
    { uri: 'spotify:playlist:' + cleanId, offset: offset, limit: limit }
  );

  const pl = (data.data && data.data.playlistV2) || data.playlistV2 || data;
  const contents = (pl.content && pl.content.items) || [];
  return extractPlaylistItems(contents, offset);
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

  return await fullArtistToGeneric(data);
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
      source: 'spotify',
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
      source: 'spotify',
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
      source: 'spotify',
      title: itemData.name || '',
      description: itemData.description || '',
      thumbnail_url: extractImageUrl(itemData.images),
      author: {
        id: (owner.data && owner.data.username) || '',
        source: 'spotify',
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
          source: 'spotify',
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
            source: 'spotify',
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

    const trackUri = (item.track && (item.track.uri || item.track._uri)) || item.uri || item._uri || '';
    const trackId = (item.track && (item.track.id || item.track._id)) || item.id || item._id || '';
    if (trackUri && !trackData.uri && !trackData._uri) {
      trackData.uri = trackUri;
    }
    if (trackId && !trackData.id && !trackData._id) {
      trackData.id = trackId;
    }

    const t = trackToGeneric(trackData);
    if (!t) continue;
    if (!t.id && (trackUri || trackId)) {
      t.id = trackUri ? (trackUri.includes(':') ? trackUri.split(':').pop() : trackUri) : trackId;
    }

    songs.push({
      id: t.id,
      uid: item.uid || ('item_' + trackNum),
      source: 'spotify',
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
      savedArtists.push(await fullArtistToGeneric(itemData));
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
    source: 'spotify',
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

// ---------------------------------------------------------------------------
// Protobuf Writer, Reader & User Profile View Parsers
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
    if (!str) return;
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
    if (val === undefined || val === null) return;
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
    const field = tag >> 3;
    const wire = tag & 0x07;
    if (wire !== 0 && wire !== 1 && wire !== 2 && wire !== 5) {
      throw new Error('Unknown protobuf wire type: ' + wire);
    }
    return { field: field, wire: wire };
  }
  readLengthDelimited() {
    const len = this.readVarint();
    if (this.offset + len > this.bytes.length) {
      throw new Error('Protobuf length-delimited out of bounds: ' + len);
    }
    const slice = this.bytes.subarray(this.offset, this.offset + len);
    this.offset += len;
    return slice;
  }
  readString() {
    const slice = this.readLengthDelimited();
    if (typeof TextDecoder !== 'undefined') {
      try {
        return new TextDecoder('utf-8').decode(slice);
      } catch (_) {}
    }
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
      if (this.offset + len > this.bytes.length) throw new Error('Protobuf skip out of bounds');
      this.offset += len;
    } else if (wireType === 5) this.offset += 4;
    else throw new Error('Unknown protobuf wire type: ' + wireType);
  }
}

function parseUserProfileProto(bytes) {
  if (!bytes) return null;
  let u8;
  if (bytes instanceof Uint8Array) {
    u8 = bytes;
  } else if (typeof bytes === 'string') {
    u8 = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) u8[i] = bytes.charCodeAt(i) & 0xff;
  } else if (Array.isArray(bytes)) {
    u8 = new Uint8Array(bytes);
  } else {
    return null;
  }

  if (u8.length === 0) return null;

  // In case leading 0x0a was stripped from text dumps
  if (u8[0] === 0x26 && u8[1] === 0x73 && u8[2] === 0x70) {
    const fixed = new Uint8Array(u8.length + 1);
    fixed[0] = 0x0a;
    fixed.set(u8, 1);
    u8 = fixed;
  }

  const result = {
    uri: '',
    name: '',
    image_url: '',
    followers_count: 0,
    following_count: 0,
    recently_played_artists: [],
    public_playlists: [],
    total_public_playlists_count: 0
  };

  try {
    const reader = new SimpleProtoReader(u8);
    while (reader.hasMore()) {
      const tag = reader.readTag();
      if (!tag) break;
      if (tag.field === 1 && tag.wire === 2) {
        const u = reader.readString();
        if (!result.uri && u.startsWith('spotify:user:')) result.uri = u;
      } else if (tag.field === 2 && tag.wire === 2) {
        if (!result.name) result.name = reader.readString();
        else reader.skipField(2);
      } else if (tag.field === 3 && tag.wire === 2) {
        if (!result.image_url) result.image_url = reader.readString();
        else reader.skipField(2);
      } else if (tag.field === 4 && tag.wire === 0) {
        result.followers_count = reader.readVarint();
      } else if (tag.field === 5 && tag.wire === 0) {
        result.following_count = reader.readVarint();
      } else if (tag.field === 7 && tag.wire === 2) {
        const artistBytes = reader.readLengthDelimited();
        const aReader = new SimpleProtoReader(artistBytes);
        const artist = { uri: '', name: '', image_url: '', followers_count: 0 };
        while (aReader.hasMore()) {
          const aTag = aReader.readTag();
          if (!aTag) break;
          if (aTag.field === 1 && aTag.wire === 2) {
            artist.uri = aReader.readString();
          } else if (aTag.field === 2 && aTag.wire === 2) {
            artist.name = aReader.readString();
          } else if (aTag.field === 3 && aTag.wire === 2) {
            artist.image_url = aReader.readString();
          } else if (aTag.field === 4 && aTag.wire === 0) {
            artist.followers_count = aReader.readVarint();
          } else {
            aReader.skipField(aTag.wire);
          }
        }
        if (artist.uri || artist.name) {
          result.recently_played_artists.push(artist);
        }
      } else if (tag.field === 8 && tag.wire === 2) {
        const plBytes = reader.readLengthDelimited();
        const pReader = new SimpleProtoReader(plBytes);
        const playlist = { uri: '', name: '', image_url: '', followers_count: 0, owner_name: '', owner_uri: '' };
        while (pReader.hasMore()) {
          const pTag = pReader.readTag();
          if (!pTag) break;
          if (pTag.field === 1 && pTag.wire === 2) {
            playlist.uri = pReader.readString();
          } else if (pTag.field === 2 && pTag.wire === 2) {
            playlist.name = pReader.readString();
          } else if (pTag.field === 3 && pTag.wire === 2) {
            playlist.image_url = pReader.readString();
          } else if (pTag.field === 4 && pTag.wire === 0) {
            playlist.followers_count = pReader.readVarint();
          } else if (pTag.field === 5 && pTag.wire === 2) {
            playlist.owner_name = pReader.readString();
          } else if (pTag.field === 6 && pTag.wire === 2) {
            playlist.owner_uri = pReader.readString();
          } else {
            pReader.skipField(pTag.wire);
          }
        }
        if (playlist.uri || playlist.name) {
          result.public_playlists.push(playlist);
        }
      } else if (tag.field === 9 && tag.wire === 0) {
        result.total_public_playlists_count = reader.readVarint();
      } else {
        reader.skipField(tag.wire);
      }
    }
  } catch (_) {
    return null;
  }

  return (result.uri && (result.public_playlists.length > 0 || result.recently_played_artists.length > 0)) ? result : null;
}

function parseUserProfileFromText(text) {
  if (!text || typeof text !== 'string') return null;
  const result = {
    uri: '',
    name: '',
    image_url: '',
    followers_count: 0,
    following_count: 0,
    recently_played_artists: [],
    public_playlists: [],
    total_public_playlists_count: 0
  };

  const userMatch = text.match(/spotify:user:([a-zA-Z0-9_-]+)/);
  if (userMatch) {
    result.uri = 'spotify:user:' + userMatch[1];
    const afterUser = text.slice(userMatch.index + userMatch[0].length);
    const imgIdx = afterUser.indexOf('https://');
    if (imgIdx !== -1) {
      result.name = afterUser.slice(0, imgIdx).replace(/^[\x00-\x1f\s]+/, '').replace(/[\x00-\x1f].*$/, '').trim();
      const afterImg = afterUser.slice(imgIdx);
      const endImg = afterImg.search(/[\x00-\x20]/);
      result.image_url = endImg !== -1 ? afterImg.slice(0, endImg) : afterImg;
    }
  }

  const artistRegex = /spotify:artist:([a-zA-Z0-9]+)/g;
  let aMatch;
  const artistIndices = [];
  while ((aMatch = artistRegex.exec(text)) !== null) {
    artistIndices.push({ id: aMatch[1], start: aMatch.index, end: aMatch.index + aMatch[0].length });
  }

  const plRegex = /spotify:playlist:([a-zA-Z0-9]+)/g;
  let pMatch;
  const plIndices = [];
  while ((pMatch = plRegex.exec(text)) !== null) {
    plIndices.push({ id: pMatch[1], start: pMatch.index, end: pMatch.index + pMatch[0].length });
  }

  for (let i = 0; i < artistIndices.length; i++) {
    const cur = artistIndices[i];
    const nextLimit = (i + 1 < artistIndices.length) ? artistIndices[i + 1].start : (plIndices.length > 0 ? plIndices[0].start : text.length);
    const chunk = text.slice(cur.end, nextLimit);
    const imgIdx = chunk.indexOf('https://');
    let name = '';
    let img = '';
    if (imgIdx !== -1) {
      name = chunk.slice(0, imgIdx).replace(/^[\x00-\x1f\s]+/, '').replace(/[\x00-\x1f].*$/, '').trim();
      const afterImg = chunk.slice(imgIdx);
      const endImg = afterImg.search(/[\x00-\x20]/);
      img = endImg !== -1 ? afterImg.slice(0, endImg) : afterImg;
    }
    result.recently_played_artists.push({
      uri: 'spotify:artist:' + cur.id,
      name: name,
      image_url: img,
      followers_count: 0
    });
  }

  for (let i = 0; i < plIndices.length; i++) {
    const cur = plIndices[i];
    const nextLimit = (i + 1 < plIndices.length) ? plIndices[i + 1].start : text.length;
    const chunk = text.slice(cur.end, nextLimit);
    let imgIdx = chunk.indexOf('https://');
    if (imgIdx === -1) imgIdx = chunk.indexOf('spotify:mosaic:');
    let title = '';
    let img = '';
    let ownerName = '';
    let ownerUri = '';
    if (imgIdx !== -1) {
      title = chunk.slice(0, imgIdx).replace(/^[\x00-\x1f\s]+/, '').replace(/[\x00-\x1f].*$/, '').trim();
      const afterImg = chunk.slice(imgIdx);
      const ownerIdx = afterImg.indexOf('spotify:user:');
      if (ownerIdx !== -1) {
        const ownerMatch = afterImg.slice(ownerIdx).match(/^spotify:user:([a-zA-Z0-9_-]+)/);
        if (ownerMatch) ownerUri = ownerMatch[0];
        const midPart = afterImg.slice(0, ownerIdx);
        const parts = midPart.split('*');
        if (parts.length > 1) {
          ownerName = parts[parts.length - 1].replace(/^[\x00-\x1f\s]+/, '').replace(/[\x00-\x1f].*$/, '').replace(/[\s0-9&]+$/g, '').trim();
        }
        const imgPart = parts[0].trim();
        const endImg = imgPart.search(/[\x00-\x20]/);
        img = endImg !== -1 ? imgPart.slice(0, endImg) : imgPart;
      } else {
        const endImg = afterImg.search(/[\x00-\x20]/);
        img = endImg !== -1 ? afterImg.slice(0, endImg) : afterImg;
      }
    }
    result.public_playlists.push({
      uri: 'spotify:playlist:' + cur.id,
      name: title,
      image_url: img,
      followers_count: 0,
      owner_name: ownerName,
      owner_uri: ownerUri
    });
  }

  return (result.uri || result.name || result.public_playlists.length > 0) ? result : null;
}

function parseUserListProto(bytes) {
  if (!bytes) return [];
  let u8;
  if (bytes instanceof Uint8Array) {
    u8 = bytes;
  } else if (typeof bytes === 'string') {
    u8 = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) u8[i] = bytes.charCodeAt(i) & 0xff;
  } else if (Array.isArray(bytes)) {
    u8 = new Uint8Array(bytes);
  } else {
    return [];
  }

  if (u8.length === 0) return [];
  const reader = new SimpleProtoReader(u8);
  const profiles = [];
  try {
    while (reader.hasMore()) {
      const tag = reader.readTag();
      if (!tag) break;
      if (tag.wire === 2) {
        const itemBytes = reader.readLengthDelimited();
        try {
          const iReader = new SimpleProtoReader(itemBytes);
          const item = { id: '', uri: '', name: '', image_url: '', followers_count: 0 };
          while (iReader.hasMore()) {
            const iTag = iReader.readTag();
            if (!iTag) break;
            if (iTag.field === 1 && iTag.wire === 2) {
              item.uri = iReader.readString();
            } else if (iTag.field === 2 && iTag.wire === 2) {
              item.name = iReader.readString();
            } else if (iTag.field === 3 && iTag.wire === 2) {
              item.image_url = iReader.readString();
            } else if (iTag.field === 4 && iTag.wire === 0) {
              item.followers_count = iReader.readVarint();
            } else {
              iReader.skipField(iTag.wire);
            }
          }
          if (item.uri && (item.uri.startsWith('spotify:user:') || item.uri.startsWith('spotify:artist:'))) {
            item.id = item.uri.split(':').pop();
            profiles.push(item);
          }
        } catch (_) {}
      } else {
        reader.skipField(tag.wire);
      }
    }
  } catch (_) {
    return profiles.length > 0 ? profiles : [];
  }
  return profiles;
}

function parseUserListFromText(text) {
  if (!text || typeof text !== 'string') return [];
  const results = [];
  const regex = /spotify:(user|artist):([a-zA-Z0-9_-]+)/g;
  let match;
  const matches = [];
  while ((match = regex.exec(text)) !== null) {
    matches.push({
      type: match[1],
      id: match[2],
      fullUri: match[0],
      start: match.index,
      end: match.index + match[0].length
    });
  }

  for (let i = 0; i < matches.length; i++) {
    const cur = matches[i];
    const nextLimit = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
    const chunk = text.slice(cur.end, nextLimit);

    const imgIdx = chunk.indexOf('https://');
    let name = '';
    let img = '';
    let afterNameChunk = '';
    if (imgIdx !== -1) {
      const rawName = chunk.slice(0, imgIdx).replace(/^[\x00-\x1f\s]+/, '');
      name = rawName.split(/[\x00-\x1f]/)[0].trim();
      const afterImg = chunk.slice(imgIdx);
      const endImg = afterImg.search(/[\x00-\x20]/);
      img = endImg !== -1 ? afterImg.slice(0, endImg) : afterImg;
      afterNameChunk = endImg !== -1 ? afterImg.slice(endImg) : '';
    } else {
      const rawName = chunk.replace(/^[\x00-\x1f\s]+/, '');
      name = rawName.split(/[\x00-\x1f]/)[0].trim();
      const namePos = chunk.indexOf(name);
      if (namePos !== -1) {
        afterNameChunk = chunk.slice(namePos + name.length);
      }
    }

    let followersCount = 0;
    if (afterNameChunk) {
      const tag4 = afterNameChunk.indexOf(' ');
      if (tag4 !== -1 && tag4 < 10) {
        const val = afterNameChunk.charCodeAt(tag4 + 1);
        if (!isNaN(val) && val < 128) {
          followersCount = val;
        }
      }
    }

    results.push({
      id: cur.id,
      uri: cur.fullUri,
      name: name,
      image_url: img,
      followers_count: followersCount,
      source: 'spotify'
    });
  }
  return results;
}

async function getUserProfileView(userId, options = {}) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const pLimit = options.playlistLimit || 10;
  const aLimit = options.artistLimit || 10;
  const eLimit = options.episodeLimit || 10;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) +
    '?playlist_limit=' + pLimit + '&artist_limit=' + aLimit + '&episode_limit=' + eLimit + '&market=from_token';

  const res = await fetchSpClient(url, {
    headers: {
      'Accept': 'application/x-protobuf, application/protobuf, application/json, */*'
    }
  });
  if (res.status !== 200) {
    throw new Error('getUserProfileView failed: ' + res.status);
  }

  let data = null;
  // 1. Try parsing JSON first
  try {
    data = await res.json();
  } catch (_) {}

  // 2. If not JSON, try parsing protobuf bytes
  if (!data || !data.uri) {
    try {
      if (typeof res.bytes === 'function') {
        const bytes = await res.bytes();
        if (bytes && bytes.length > 0) {
          data = parseUserProfileProto(bytes);
        }
      }
    } catch (e) {
      console.warn('[Spotify] Failed parsing user profile protobuf bytes: ' + e);
    }
  }

  // 3. Fallback: try parsing from response text
  if (!data || !data.uri || ((!data.public_playlists || data.public_playlists.length === 0) && (!data.recently_played_artists || data.recently_played_artists.length === 0))) {
    try {
      const text = await res.text();
      if (text) {
        if (text.trim().startsWith('{')) {
          try {
            data = JSON.parse(text);
          } catch (_) {
            data = null;
          }
        }
        if (!data || !data.uri) {
          data = parseUserProfileProto(text) || parseUserProfileFromText(text);
        }
      }
    } catch (e) {
      console.warn('[Spotify] Failed parsing user profile text fallback: ' + e);
    }
  }

  if (!data) {
    throw new Error('getUserProfileView failed: unable to parse user profile response');
  }

  const uri = data.uri || data.id || '';
  const cleanUriId = uri.includes(':') ? uri.split(':').pop() : (uri || cleanId);

  const recentArtists = (data.recently_played_artists || []).map(a => ({
    id: a.uri ? a.uri.split(':').pop() : (a.id || ''),
    source: 'spotify',
    name: a.name || '',
    thumbnail_url: extractImageUrl(a.image_url || a.images || a.image) || ''
  }));

  const publicPlaylists = (data.public_playlists || []).map(p => {
    let pOwner = null;
    if (p.owner_name || p.owner_uri) {
      let ownerId = p.owner_uri ? (p.owner_uri.includes(':') ? p.owner_uri.split(':').pop() : p.owner_uri) : '';
      if (ownerId && cleanId && ownerId.startsWith(cleanId)) {
        ownerId = cleanId;
      }
      pOwner = {
        id: ownerId || cleanId,
        source: 'spotify',
        display_name: p.owner_name || data.name || '',
        avatar_url: ''
      };
    }
    return {
      id: p.uri ? p.uri.split(':').pop() : (p.id || ''),
      source: 'spotify',
      title: p.name || '',
      thumbnail_url: extractImageUrl(p.image_url || p.images || p.image) || '',
      total_tracks: p.total_tracks || 0,
      follower_count: p.followers_count !== undefined ? p.followers_count : (p.follower_count || 0),
      owner: pOwner
    };
  });

  return {
    id: cleanUriId,
    source: 'spotify',
    display_name: data.name || data.display_name || 'Unknown User',
    avatar_url: extractImageUrl(data.image_url || data.images || data.avatar_url || data.avatar) || '',
    follower_count: data.followers_count !== undefined ? data.followers_count : (data.follower_count || 0),
    following_count: data.following_count !== undefined ? data.following_count : 0,
    recent_artists: recentArtists,
    public_playlists: publicPlaylists,
    followers: [],
    following: []
  };
}

async function getUserFollowers(userId) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) + '/followers?market=from_token';
  const res = await fetchSpClient(url, {
    headers: {
      'Accept': 'application/x-protobuf, application/protobuf, application/json, */*'
    }
  });
  if (res.status !== 200) return [];
  let data = null;
  try {
    data = await res.json();
  } catch (_) {}
  if (!data || (Array.isArray(data) && data.length === 0)) {
    try {
      const bytes = typeof res.bytes === 'function' ? await res.bytes() : null;
      if (bytes && bytes.length > 0) {
        const parsed = parseUserListProto(bytes);
        if (parsed && parsed.length > 0) {
          data = parsed;
        }
      }
    } catch (_) {}
  }
  if (!data || (Array.isArray(data) && data.length === 0)) {
    try {
      const text = typeof res.text === 'function' ? await res.text() : null;
      if (text) {
        if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
          try {
            data = JSON.parse(text);
          } catch (_) {
            data = null;
          }
        }
        if (!data || (Array.isArray(data) && data.length === 0)) {
          const parsed = parseUserListProto(text);
          if (parsed && parsed.length > 0) {
            data = parsed;
          } else {
            data = parseUserListFromText(text);
          }
        }
      }
    } catch (_) {}
  }
  if (!data) return [];
  let items = [];
  if (Array.isArray(data)) {
    items = data;
  } else if (data && typeof data === 'object') {
    items = data.profiles || data.followers || data.items || data.values || [];
  }
  return items.map(u => {
    const rawUri = u.uri || u.profile_url || (u.id ? (u.id.startsWith('spotify:') ? u.id : '') : '');
    const cleanUserId = rawUri ? rawUri.split(':').pop() : (u.id || '');
    const name = u.display_name || u.name || '';
    const avatar = extractImageUrl(u.image_url || u.images || u.image || u.avatar_url || u.avatar || u.thumbnail_url) || '';
    const profileUri = rawUri || (cleanUserId ? ('spotify:user:' + cleanUserId) : '');
    const followerCount = u.followers_count !== undefined ? u.followers_count : (u.follower_count !== undefined ? u.follower_count : 0);

    return {
      id: cleanUserId,
      source: 'spotify',
      name: name,
      display_name: name,
      avatar_url: avatar || null,
      thumbnail_url: avatar || '',
      profile_url: profileUri || null,
      follower_count: followerCount
    };
  });
}

async function getUserFollowing(userId) {
  const cleanId = userId.includes(':') ? userId.split(':').pop() : userId;
  const url = '/user-profile-view/v3/profile/' + encodeURIComponent(cleanId) + '/following?market=from_token';
  const res = await fetchSpClient(url, {
    headers: {
      'Accept': 'application/x-protobuf, application/protobuf, application/json, */*'
    }
  });
  if (res.status !== 200) return [];
  let data = null;
  try {
    data = await res.json();
  } catch (_) {}
  if (!data || (Array.isArray(data) && data.length === 0)) {
    try {
      const bytes = typeof res.bytes === 'function' ? await res.bytes() : null;
      if (bytes && bytes.length > 0) {
        const parsed = parseUserListProto(bytes);
        if (parsed && parsed.length > 0) {
          data = parsed;
        }
      }
    } catch (_) {}
  }
  if (!data || (Array.isArray(data) && data.length === 0)) {
    try {
      const text = typeof res.text === 'function' ? await res.text() : null;
      if (text) {
        if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
          try {
            data = JSON.parse(text);
          } catch (_) {
            data = null;
          }
        }
        if (!data || (Array.isArray(data) && data.length === 0)) {
          const parsed = parseUserListProto(text);
          if (parsed && parsed.length > 0) {
            data = parsed;
          } else {
            data = parseUserListFromText(text);
          }
        }
      }
    } catch (_) {}
  }
  if (!data) return [];
  let items = [];
  if (Array.isArray(data)) {
    items = data;
  } else if (data && typeof data === 'object') {
    items = data.profiles || data.following || data.items || data.values || [];
  }
  return items.map(u => {
    const rawUri = u.uri || u.profile_url || (u.id ? (u.id.startsWith('spotify:') ? u.id : '') : '');
    const cleanEntityId = rawUri ? rawUri.split(':').pop() : (u.id || '');
    const name = u.display_name || u.name || '';
    const avatar = extractImageUrl(u.image_url || u.images || u.image || u.avatar_url || u.avatar || u.thumbnail_url) || '';
    const profileUri = rawUri || (cleanEntityId ? ('spotify:user:' + cleanEntityId) : '');
    const followerCount = u.followers_count !== undefined ? u.followers_count : (u.follower_count !== undefined ? u.follower_count : 0);

    return {
      id: cleanEntityId,
      source: 'spotify',
      name: name,
      display_name: name,
      avatar_url: avatar || null,
      thumbnail_url: avatar || '',
      profile_url: profileUri || null,
      follower_count: followerCount
    };
  });
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
      source: 'spotify',
      title: t.name || t.trackName || '',
      artists: (t.artists || []).map(a => ({
        id: (a.id ? (a.id.includes(':') ? a.id.split(':').pop() : a.id) : (a.uri ? a.uri.split(':').pop() : '')),
        source: 'spotify',
        name: a.name || a.artistName || 'Unknown Artist',
        thumbnail_url: ''
      })),
      thumbnail_url: albumCover,
      explicit: !!t.explicit,
      album: {
        id: (albumData.id ? (albumData.id.includes(':') ? albumData.id.split(':').pop() : albumData.id) : (albumData.uri ? albumData.uri.split(':').pop() : '')),
        title: albumData.name || albumData.albumName || 'Unknown Album',
        source: 'spotify',
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
// Track Descriptors (Genres)
// ---------------------------------------------------------------------------

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

async function getTrackIsrc(trackId) {
  try {
    if (!trackId || typeof trackId !== 'string') return null;
    const cleanTrackId = trackId.includes(':') ? trackId.split(':').pop() : trackId;
    const hexGid = spotifyIdToHexGid(cleanTrackId);

    // 1. Check direct metadata/4/track endpoint first (fastest)
    try {
      const endpoint = 'https://spclient.wg.spotify.com/metadata/4/track/' + hexGid + '?market=from_token';
      const res = await fetchSpClient(endpoint);
      if (res.status === 200) {
        const data = await res.json();
        if (data && Array.isArray(data.external_id)) {
          const isrcEntry = data.external_id.find(e => e.type === 'isrc' || e.type === 'ISRC');
          if (isrcEntry && isrcEntry.id) return isrcEntry.id;
        }
      }
    } catch (_) {}

    // 2. Fallback to extended-metadata endpoint
    const trackUri = 'spotify:track:' + cleanTrackId;
    const token = await authManager.getAccessToken();
    if (!token) return null;

    const queryWriter = new SimpleProtoWriter();
    queryWriter.writeInt32(1, 1); // Track metadata extension

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
      'Accept': 'application/json',
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

    if (res.status === 200) {
      const json = await res.json();
      if (json && Array.isArray(json.extended_metadata)) {
        for (const ext of json.extended_metadata) {
          if (ext && Array.isArray(ext.external_id)) {
            const entry = ext.external_id.find(e => (e.type || '').toLowerCase() === 'isrc');
            if (entry && entry.id) return entry.id;
          }
        }
      }
    }

    return null;
  } catch (e) {
    console.warn('[Spotify] Failed getTrackIsrc: ' + e);
    return null;
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
  getTrackIsrc,
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

