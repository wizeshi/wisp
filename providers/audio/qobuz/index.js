const JUMO_HOST = 'https://jumo-dl.pages.dev';
const SEARCH_PATH = '/qggybiqvrmvapbsrfrlg';
const FETCH_PATH = '/wydmcqpplrfjrstcj';
const REGIONS_PATH = '/symdofufvpjpgkmru';

function getRandomHex(len) {
  let hex = '';
  for (let i = 0; i < len; i++) {
    hex += Math.floor(Math.random() * 16).toString(16);
  }
  return hex;
}

class JumoClient {
  constructor() {
    this.sessionId = null;
    this.keyPair = null;
    this.sequence = 0;
    this.cachedTracks = new Map();
    this.activeRegion = null;
    this.regionsData = null;
    this._regionsPromise = null;
  }

  async _ensureSession() {
    if (this.sessionId && this.keyPair) return;
    this.sessionId = getRandomHex(32);
    // Use host bridge for ECDH key generation (PointyCastle in Dart)
    this.keyPair = await globalThis.wisp.crypto.generateP256KeyPair();
  }

  async getActiveRegion() {
    if (this.activeRegion) return this.activeRegion;
    if (this._regionsPromise) return await this._regionsPromise;

    this._regionsPromise = (async () => {
      try {
        const data = await this.request(REGIONS_PATH);
        if (data) {
          this.regionsData = data;
          if (data.default) {
            this.activeRegion = data.default;
          } else if (Array.isArray(data.regions) && data.regions.length > 0) {
            const available = data.regions.find(r => r.available);
            this.activeRegion = available ? available.code : data.regions[0].code;
          }
        }
      } catch (e) {
        console.warn('[Qobuz] Failed to fetch regions, falling back to default:', e);
      } finally {
        this._regionsPromise = null;
      }
      return this.activeRegion || 'CA';
    })();

    return await this._regionsPromise;
  }

  async getAvailableRegions() {
    if (this.regionsData && Array.isArray(this.regionsData.regions)) {
      const available = this.regionsData.regions
        .filter(r => r.available)
        .map(r => r.code);
      if (available.length > 0) return available;
    }
    const def = await this.getActiveRegion();
    return [def];
  }

  async request(urlStr, extraHeaders = {}) {
    await this._ensureSession();
    this.sequence++;

    const urlObj = new URL(urlStr, JUMO_HOST);
    const nonce = getRandomHex(24);

    const interactionJson = JSON.stringify({
      v: 1,
      nonce: nonce,
      method: 'GET',
      path: urlObj.pathname,
      pageAgeMs: 5000 + this.sequence * 1000,
      lastInputAgeMs: null,
      pointer: 0,
      key: 0,
      scroll: 0,
      touch: 0,
      focused: true,
      visibility: 'visible',
      botSignals: []
    });
    const interaction = btoa(interactionJson).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

    const headers = {
      'sec-ch-ua-platform': '"Windows"',
      'x-jumo-interaction': interaction,
      'sec-ch-ua': '"Chromium";v="135", "Google Chrome";v="135", "Not A(Brand";v="99"',
      'x-jumo-client': 'browser',
      'sec-ch-ua-mobile': '?0',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
      'x-jumo-session': this.sessionId,
      'x-jumo-request-nonce': nonce,
      'Accept': 'application/json, text/plain, */*',
      'x-jumo-sequence': String(this.sequence),
      'Referer': JUMO_HOST + '/',
      'Accept-Language': 'en-US,en;q=0.9',
      ...extraHeaders
    };

    const isEncrypted = [SEARCH_PATH, FETCH_PATH].includes(urlObj.pathname);
    if (isEncrypted) {
      headers['x-jumo-public-key'] = this.keyPair.publicKey;
    }

    const res = await globalThis.wisp.fetch(urlObj.href, { headers });
    if (res.status !== 200) {
      throw new Error('Jumo request failed with status ' + res.status);
    }

    const getHeader = (name) => {
      if (!res.headers) return null;
      if (typeof res.headers.get === 'function') {
        const val = res.headers.get(name);
        if (val) return val;
      }
      const lower = name.toLowerCase();
      for (const k of Object.keys(res.headers)) {
        if (k.toLowerCase() === lower) return res.headers[k];
      }
      return null;
    };

    const isPayloadEncrypted = getHeader('x-jumo-payload') === '1';

    if (isEncrypted && isPayloadEncrypted) {
      const serverPubKey = getHeader('x-jumo-public-key');
      const bodyB64 = await res.base64();

      // Native Dart ECDH + HKDF + AES-GCM decryption
      const decryptedJson = await globalThis.wisp.crypto.decryptJumoPayload({
        clientPrivHex: this.keyPair.privateKeyHex,
        serverPubKey: serverPubKey,
        bodyB64: bodyB64,
        url: urlObj.href,
        nonce: nonce
      });
      return decryptedJson;
    } else {
      const rawText = await res.text();
      if (rawText.trim().startsWith('<')) {
        throw new Error('Jumo returned unexpected HTML response for ' + urlObj.pathname);
      }
      return JSON.parse(rawText);
    }
  }

  async search(queryStr) {
    const primaryRegion = await this.getActiveRegion();
    let items = await this._searchWithRegion(queryStr, primaryRegion);
    if (items && items.length > 0) return items;

    return [];
  }

  async _searchWithRegion(queryStr, region) {
    try {
      const url = SEARCH_PATH + '?query=' + encodeURIComponent(queryStr) + '&offset=0&limit=10&region=' + encodeURIComponent(region) + '&view=ui';
      const data = await this.request(url);
      if (data && data.tracks && Array.isArray(data.tracks.items)) {
        for (const t of data.tracks.items) {
          if (t && t.id) {
            this.cachedTracks.set(String(t.id), t);
          }
        }
        return data.tracks.items;
      }
    } catch (e) {
      console.warn('[Qobuz] Search error for region ' + region + ': ' + e);
    }
    return [];
  }

  async resolveStream(track, preferredQuality = 'auto') {
    if (!track.fetchUrls) {
      throw new Error('Track has no fetchUrls available');
    }

    const availableFormats = Object.keys(track.fetchUrls);

    // Format IDs:
    // '27': Hi-Res Lossless (24-bit / 96-192 kHz)
    // '6': Lossless CD (16-bit / 44.1 kHz)
    // '5': High / Standard (MP3 320 kbps)
    let candidateOrder;
    switch (preferredQuality) {
      case 'lossless':
        // Try Lossless CD first, then fallback to highest available (27 -> 5)
        candidateOrder = ['6', '27', '5'];
        break;
      case 'high':
      case 'standard':
        // Try MP3 320 first, fallback to Lossless / Hi-Res
        candidateOrder = ['5', '6', '27'];
        break;
      case 'hiRes':
      case 'auto':
      default:
        // Try Hi-Res first, then Lossless, then MP3
        candidateOrder = ['27', '6', '5'];
        break;
    }

    let chosenFormat = candidateOrder.find(f => availableFormats.includes(f));
    if (!chosenFormat && availableFormats.length > 0) {
      chosenFormat = availableFormats[0];
    }

    const fetchPath = track.fetchUrls[chosenFormat];
    if (!fetchPath) {
      throw new Error('Format ' + chosenFormat + ' not available for track');
    }

    const payload = await this.request(fetchPath, { 'X-Jumo-Embed-Cover': '1' });
    let resolvedBitDepth = 16;
    let resolvedSamplingRate = 44.1;
    if (chosenFormat === '27') {
      resolvedBitDepth = track.maximum_bit_depth && track.maximum_bit_depth > 16 ? track.maximum_bit_depth : 24;
      resolvedSamplingRate = track.maximum_sampling_rate && track.maximum_sampling_rate > 44.1 ? track.maximum_sampling_rate : 96.0;
    } else if (chosenFormat === '6') {
      resolvedBitDepth = 16;
      resolvedSamplingRate = 44.1;
    } else {
      resolvedBitDepth = 16;
      resolvedSamplingRate = 44.1;
    }

    return {
      payload,
      formatId: chosenFormat,
      bitDepth: resolvedBitDepth,
      samplingRate: resolvedSamplingRate
    };
  }
}

const client = new JumoClient();

async function searchAudio(query) {
  try {
    let items = [];
    if (query.isrc && query.isrc.trim().length > 0) {
      items = await client.search(query.isrc.trim());
    }
    if (!items || items.length === 0) {
      const artistNames = Array.isArray(query.artists) ? query.artists.join(', ') : (query.artist || '');
      const searchTerms = artistNames ? (artistNames + ' - ' + query.title) : query.title;
      items = await client.search(searchTerms);
    }
    return items.map((item, index) => {
      const performerName = item.performer ? item.performer.name : (item.artists ? item.artists.map(a => a.name).join(', ') : '');
      const bitDepth = item.maximum_bit_depth || 16;
      const samplingRate = item.maximum_sampling_rate || 44.1;
      const isHiRes = bitDepth > 16 || samplingRate > 44.1;
      return {
        mediaId: String(item.id),
        providerId: 'qobuz',
        title: item.title || '',
        artist: performerName,
        album: item.album ? item.album.title : null,
        duration: Math.round(item.duration || 0),
        thumbnailUrl: item.album && item.album.image ? (item.album.image.large || item.album.image.small) : null,
        qualityLabel: isHiRes ? ('Hi-Res (' + bitDepth + '-bit / ' + samplingRate + ' kHz)') : ('Lossless (' + bitDepth + '-bit / ' + samplingRate + ' kHz)'),
        score: index === 0 ? 0.98 : Math.max(0.1, 0.9 - index * 0.1)
      };
    });
  } catch (err) {
    console.warn('[Qobuz] searchAudio error: ' + err);
    return [];
  }
}

async function getStreamUrl(mediaId, options = {}) {
  try {
    let track = client.cachedTracks.get(String(mediaId));
    if (!track) {
      const items = await client.search(String(mediaId));
      track = items.find(i => String(i.id) === String(mediaId)) || items[0];
    }
    if (!track) {
      throw new Error('Track ' + mediaId + ' not found in Qobuz catalog');
    }
    const preferredQuality = options.preferredQuality || 'hiRes';
    const { payload, formatId, bitDepth, samplingRate } = await client.resolveStream(track, preferredQuality);

    if (payload.qb && payload.qb.url_template) {
      const streamUrl = payload.qb.url_template.replace('$SEGMENT$', '0');
      return {
        url: streamUrl,
        format: payload.qb.container || 'flac',
        bitDepth: bitDepth,
        sampleRate: Math.round(samplingRate * 1000),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36'
        },
        segmented: {
          initSegmentUrl: streamUrl,
          segmentUrlTemplate: payload.qb.url_template,
          segmentCount: payload.qb.n_segments || 0,
          container: payload.qb.container || 'flac',
          cipher: {
            algorithm: 'aes-ctr',
            keyHex: payload.qb.content_key,
            ivMode: 'mp4-uuid'
          }
        }
      };
    }
    if (payload.directDownloadUrl) {
      return {
        url: payload.directDownloadUrl,
        format: 'flac',
        headers: {}
      };
    }
    throw new Error('No playable stream URL returned by resolver');
  } catch (err) {
    console.error('[Qobuz] getStreamUrl error: ' + err);
    throw err;
  }
}

const QobuzAudioProvider = { searchAudio, getStreamUrl };
if (typeof module !== 'undefined' && module.exports) module.exports = QobuzAudioProvider;
globalThis.searchAudio = searchAudio;
globalThis.getStreamUrl = getStreamUrl;
