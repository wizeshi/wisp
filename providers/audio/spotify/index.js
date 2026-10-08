// Spotify Audio Provider for wisp
// Resolves and streams audio directly from Spotify CDN using the librespot protocol.
// Encrypted Ogg Vorbis streams are decrypted on the fly via the wisp streaming proxy.

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const SPOTIFY_BASE62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

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
    if (wisp.auth && typeof wisp.auth.getTokens === 'function') {
      const tokens = await wisp.auth.getTokens({ serviceId: this.serviceId, forceRefresh: forceRefresh });
      if (tokens) return tokens;
    }
    return await this.getSession();
  }
}

const authManager = new SpotifyAuthManager('spotify');

function spotifyIdToHexGid(id) {
  if (!id || typeof id !== 'string') return '';
  const clean = id.trim().replace(/^spotify:track:/, '');
  if (clean.length === 32 && /^[0-9a-fA-F]{32}$/.test(clean)) {
    return clean.toLowerCase();
  }
  const bytes = [];
  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    const idx = SPOTIFY_BASE62.indexOf(ch);
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

async function fetchWithAuth(url, options = {}) {
  let tokens = await authManager.getTokens();
  if (!tokens || !tokens.accessToken) {
    throw new Error('NOT_AUTHENTICATED: No Spotify tokens available');
  }

  const buildHeaders = (t) => Object.assign({
    'Authorization': 'Bearer ' + t.accessToken,
    'client-token': t.clientToken || '',
    'Accept': 'application/json',
    'User-Agent': USER_AGENT
  }, options.headers || {});

  let res = await wisp.fetch(url, {
    method: options.method || 'GET',
    headers: buildHeaders(tokens),
    body: options.body || null
  });

  if (res.status === 401) {
    console.warn('[Spotify/Audio] 401 Unauthorized for ' + url + ', refreshing tokens...');
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

async function searchAudio(query) {
  try {
    const session = await authManager.getSession();
    if (!session || !session.isPremium) {
      console.log('[Spotify/Audio] User is not logged in or lacks Spotify Premium. Skipping Spotify audio provider.');
      return [];
    }

    // Direct match optimization: if the track is already from Spotify, return it directly
    if (query.metadataSource === 'spotify' && query.trackId) {
      return [{
        mediaId: query.trackId,
        providerId: 'spotify',
        title: query.title || '',
        artist: query.artist || (Array.isArray(query.artists) ? query.artists.join(', ') : ''),
        album: query.album || null,
        duration: query.durationSecs || 0,
        thumbnailUrl: null,
        qualityLabel: '320 kbps (High)',
        score: 1.0
      }];
    }

    // Catalog search
    let searchTerm = '';
    if (query.isrc && query.isrc.trim().length > 0) {
      searchTerm = 'isrc:' + query.isrc.trim();
    } else {
      const artistNames = Array.isArray(query.artists) ? query.artists.join(' ') : (query.artist || '');
      searchTerm = `${query.title} ${artistNames}`.trim();
    }

    const searchUrl = 'https://api.spotify.com/v1/search?q=' + encodeURIComponent(searchTerm) + '&type=track&limit=5';
    const res = await fetchWithAuth(searchUrl);
    if (res.status !== 200) {
      console.warn('[Spotify/Audio] Search failed with status: ' + res.status);
      return [];
    }

    const data = await res.json();
    const items = (data && data.tracks && Array.isArray(data.tracks.items)) ? data.tracks.items : [];

    return items.map((item, index) => {
      const artists = (item.artists || []).map(a => a.name).join(', ');
      const album = item.album ? item.album.name : null;
      const thumb = item.album && item.album.images && item.album.images.length > 0 ? item.album.images[0].url : null;
      const durationSecs = item.duration_ms ? Math.round(item.duration_ms / 1000) : 0;

      return {
        mediaId: String(item.id),
        providerId: 'spotify',
        title: item.name || '',
        artist: artists,
        album: album,
        duration: durationSecs,
        thumbnailUrl: thumb,
        qualityLabel: '320 kbps (High)',
        score: index === 0 ? 0.95 : Math.max(0.1, 0.85 - index * 0.1)
      };
    });
  } catch (err) {
    console.warn('[Spotify/Audio] searchAudio error: ' + err);
    return [];
  }
}

// ---------------------------------------------------------------------------
// Protobuf Writer & Reader for extended-metadata (following librespot)
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

function bytesToHex(bytes) {
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

const AUDIO_FORMAT_ENUM = {
  0: 'OGG_VORBIS_96',
  1: 'OGG_VORBIS_160',
  2: 'OGG_VORBIS_320',
  3: 'MP3_256',
  4: 'MP3_320',
  5: 'MP3_160',
  6: 'MP3_96',
  7: 'MP3_160_ENC',
  8: 'AAC_24',
  9: 'AAC_48',
  16: 'FLAC_FLAC',
  18: 'XHE_AAC_24',
  19: 'XHE_AAC_16',
  20: 'XHE_AAC_12',
  22: 'FLAC_FLAC_24BIT'
};

function parseAudioFilesFromTrackProto(trackBytes) {
  const files = [];
  try {
    const reader = new SimpleProtoReader(trackBytes);
    while (reader.hasMore()) {
      const tag = reader.readTag();
      if (!tag) break;
      // In Track proto, field 12 is repeated AudioFile file
      if (tag.field === 12 && tag.wire === 2) {
        const fileSlice = reader.readLengthDelimited();
        const fReader = new SimpleProtoReader(fileSlice);
        let fileId = null;
        let formatVal = null;
        while (fReader.hasMore()) {
          const fTag = fReader.readTag();
          if (!fTag) break;
          if (fTag.field === 1 && fTag.wire === 2) {
            fileId = bytesToHex(fReader.readLengthDelimited());
          } else if (fTag.field === 2 && fTag.wire === 0) {
            formatVal = fReader.readVarint();
          } else {
            fReader.skipField(fTag.wire);
          }
        }
        if (fileId) {
          files.push({
            file_id: fileId,
            format: AUDIO_FORMAT_ENUM[formatVal] || ('FORMAT_' + formatVal)
          });
        }
      } else {
        reader.skipField(tag.wire);
      }
    }
  } catch (err) {
    console.warn('[Spotify/Audio] Failed parsing Track protobuf audio files: ' + err);
  }
  return files;
}

function parseExtendedMetadataResponse(bytes) {
  try {
    const root = new SimpleProtoReader(bytes);
    while (root.hasMore()) {
      const tag = root.readTag();
      if (!tag) break;
      // BatchedExtensionResponse: field 2 is repeated EntityExtensionDataArray extended_metadata
      if (tag.field === 2 && tag.wire === 2) {
        const arrSlice = root.readLengthDelimited();
        const arr = new SimpleProtoReader(arrSlice);
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

        // ExtensionKind::TRACK_V4 = 10
        if (kind === 10) {
          for (const extBytes of extDataSlices) {
            const ext = new SimpleProtoReader(extBytes);
            let anyValue = null;
            while (ext.hasMore()) {
              const eTag = ext.readTag();
              if (!eTag) break;
              if (eTag.field === 3 && eTag.wire === 2) {
                // google.protobuf.Any: field 2 is bytes value
                const anyReader = new SimpleProtoReader(ext.readLengthDelimited());
                while (anyReader.hasMore()) {
                  const anyTag = anyReader.readTag();
                  if (!anyTag) break;
                  if (anyTag.field === 2 && anyTag.wire === 2) {
                    anyValue = anyReader.readLengthDelimited();
                  } else {
                    anyReader.skipField(anyTag.wire);
                  }
                }
              } else {
                ext.skipField(eTag.wire);
              }
            }
            if (anyValue) {
              const files = parseAudioFilesFromTrackProto(anyValue);
              if (files.length > 0) return files;
            }
          }
        }
      } else {
        root.skipField(tag.wire);
      }
    }
  } catch (err) {
    console.warn('[Spotify/Audio] Failed parsing extended-metadata response: ' + err);
  }
  return [];
}

async function fetchAudioFilesViaExtendedMetadata(trackUri, token, clientToken) {
  try {
    // Exactly matches librespot:
    // BatchedEntityRequest with ExtensionKind::TRACK_V4 = 10
    const queryWriter = new SimpleProtoWriter();
    queryWriter.writeInt32(1, 10); // ExtensionKind::TRACK_V4

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

    const headers = {
      'Authorization': 'Bearer ' + token,
      'App-Platform': 'Win32_x86_64',
      'Accept': 'application/protobuf',
      'Content-Type': 'application/protobuf',
      'Spotify-App-Version': '1.2.96.238.g5c95ebca',
      'User-Agent': USER_AGENT
    };
    if (clientToken) headers['Client-Token'] = clientToken;

    const res = await wisp.fetch('https://gew1-spclient.spotify.com/extended-metadata/v0/extended-metadata', {
      method: 'POST',
      headers: headers,
      body: bodyBytes
    });

    if (res.status === 200 && typeof res.bytes === 'function') {
      const bytes = await res.bytes();
      return parseExtendedMetadataResponse(bytes);
    }
  } catch (err) {
    console.warn('[Spotify/Audio] fetchAudioFilesViaExtendedMetadata error: ' + err);
  }
  return [];
}

async function getStreamUrl(mediaId, options = {}) {
  try {
    const session = await authManager.getSession();
    if (!session || !session.isPremium) {
      throw new Error('Spotify Premium account required for audio playback');
    }

    const cleanId = mediaId.includes(':') ? mediaId.split(':').pop() : mediaId;
    const hexGid = spotifyIdToHexGid(cleanId);
    const trackUri = 'spotify:track:' + cleanId;
    const clientToken = session.clientToken || '';

    // 1. Fetch track audio file descriptors via librespot's primary extended-metadata endpoint
    let files = await fetchAudioFilesViaExtendedMetadata(trackUri, session.accessToken, clientToken);

    // Fallback: If extended-metadata did not return files, check spclient metadata/4/track
    if (!files || files.length === 0) {
      const metaUrl = 'https://spclient.wg.spotify.com/metadata/4/track/' + hexGid + '?market=from_token';
      const metaRes = await fetchWithAuth(metaUrl);
      if (metaRes.status === 200) {
        const trackData = await metaRes.json();
        if (Array.isArray(trackData.file) && trackData.file.length > 0) {
          files = trackData.file;
        } else if (trackData.original_audio && trackData.original_audio.uuid) {
          files = [{
            file_id: trackData.original_audio.uuid,
            format: 'OGG_VORBIS_320'
          }];
        }
      }
    }

    if (!files || files.length === 0) {
      throw new Error('No audio files available for Spotify track ' + mediaId);
    }

    // 2. Select file format based on preferred quality
    const preferredQuality = options.preferredQuality || 'high';
    let targetFormat = 'OGG_VORBIS_320';
    if (preferredQuality === 'standard') {
      targetFormat = 'OGG_VORBIS_160';
    }

    let chosenFile = files.find(f => f.format === targetFormat);
    if (!chosenFile && targetFormat === 'OGG_VORBIS_320') {
      chosenFile = files.find(f => f.format === 'OGG_VORBIS_160');
    }
    if (!chosenFile) {
      chosenFile = files.find(f => f.format && f.format.startsWith('OGG_VORBIS_')) || files[0];
    }

    if (!chosenFile || !chosenFile.file_id) {
      throw new Error('No playable OGG stream descriptor found for track ' + mediaId);
    }

    // 3. Resolve CDN URL via storage-resolve (as in librespot)
    const storageUrl = 'https://gew4-spclient.spotify.com/storage-resolve/files/audio/interactive/' +
      chosenFile.file_id + '?alt=json';
    const storageRes = await fetchWithAuth(storageUrl);
    if (storageRes.status !== 200) {
      throw new Error('Storage resolve failed with status ' + storageRes.status);
    }

    const storageData = await storageRes.json();
    const cdnUrl = (storageData.cdnurl && storageData.cdnurl.length > 0)
      ? storageData.cdnurl[0]
      : ('https://audio-fa.scdn.co/audio/' + chosenFile.file_id);

    // 4. Resolve 16-byte AES-128 audio key via abstract host bridge
    if (!wisp.audio || typeof wisp.audio.resolveKey !== 'function') {
      throw new Error('wisp.audio.resolveKey bridge is not available');
    }

    const keyResult = await wisp.audio.resolveKey({
      protocol: 'ap',
      trackId: cleanId,
      fileId: chosenFile.file_id,
      token: session.accessToken
    });

    if (!keyResult || !keyResult.keyHex) {
      throw new Error('Failed to acquire audio decryption key');
    }

    const bitrate = chosenFile.format === 'OGG_VORBIS_320' ? 320 : 160;

    return {
      url: cdnUrl,
      format: 'ogg',
      bitrate: bitrate,
      sampleRate: 44100,
      headers: {
        'User-Agent': USER_AGENT
      },
      customData: {
        cipher: {
          algorithm: 'aes-128-ctr',
          keyHex: keyResult.keyHex,
          ivHex: '72e067fbddcbcf77ebe8bc643f630d93',
          skipBytes: 167,
          format: 'ogg'
        }
      }
    };
  } catch (err) {
    console.error('[Spotify/Audio] getStreamUrl error: ' + err);
    throw err;
  }
}

const SpotifyAudioProvider = { searchAudio, getStreamUrl };
if (typeof module !== 'undefined' && module.exports) module.exports = SpotifyAudioProvider;
globalThis.searchAudio = searchAudio;
globalThis.getStreamUrl = getStreamUrl;

