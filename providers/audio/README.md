# Audio Providers Specification

Audio providers supply audio streaming sources (candidate matching and playable direct audio URLs) for tracks requested by metadata providers.

Every audio provider runs inside the isolated JavaScript sandbox powered by `flutter_js` and exports standardized interface methods on `globalThis`.

---

## 1. Directory Structure

Audio providers reside in `providers/audio/<id>/`:

```
providers/audio/qobuz/
  ├── manifest.json
  ├── index.js
  └── icon.png (or icon.svg)
```

---

## 2. Audio Provider Manifest (`manifest.json`)

```json
{
  "id": "qobuz",
  "name": "Qobuz",
  "version": "1.0.0",
  "type": "audio",
  "entry": "index.js",
  "author": "wizeshi",
  "description": "High-res lossless audio streaming via Qobuz.",
  "priority": 90,
  "service": "qobuz",
  "dependencies": ["qobuz-auth"],
  "supportedQualities": ["standard", "high", "lossless", "hiRes"]
}
```

### Audio Manifest Fields

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Unique audio provider identifier (e.g. `youtube`, `qobuz`, `soundcloud`). |
| `name` | `string` | Human-readable name displayed in the settings and alternatives picker. |
| `type` | `string` | Must be `"audio"`. |
| `entry` | `string` | Main JavaScript script filename (default: `index.js`). |
| `priority` | `number` | Default cascade priority (higher = tried first during track playback). |
| `service` | `string?` | Optional service realm identifier for linked auth/session storage. |
| `dependencies` | `string[]?` | Optional list of package identifiers (such as an auth provider) required for operation. |
| `supportedQualities`| `string[]` | Audio quality tiers offered: `"standard"`, `"high"`, `"lossless"`, `"hiRes"`. |

---

## 3. JavaScript Contract

Audio providers must register the following functions on the global scope:

### `searchAudio(query)`
Searches the provider's catalog for audio tracks that best match the queried track metadata.

#### Parameters
- `query` (`object`):
  - `title` (`string`): Track title.
  - `artists` (`string[]`): List of artist names.
  - `album` (`string?`): Album name if available.
  - `durationSecs` (`number?`): Expected track duration in seconds.
  - `isrc` (`string?`): International Standard Recording Code if known.
  - `trackId` (`string?`): Source track ID.
  - `metadataSource` (`string?`): Metadata source ID (e.g. `spotify`).

#### Return Value
Returns an array of candidate objects:
```javascript
[
  {
    "mediaId": "12345678",        // Provider-specific track/media ID
    "title": "Let It Happen",
    "artist": "Tame Impala",
    "album": "Currents",
    "durationMs": 467000,
    "thumbnailUrl": "https://...", // Optional artwork preview
    "qualityLabel": "24-bit / 96kHz", // Optional badge label
    "score": 0.95                 // Optional matching confidence (0.0 to 1.0)
  }
]
```

---

### `getStreamUrl(mediaId, options)`
Resolves the playable direct audio URL and any required HTTP headers.

#### Parameters
- `mediaId` (`string`): The media ID chosen from `searchAudio` or entered via manual override.
- `options` (`object?`):
  - `preferredQuality` (`string`): User quality preference (`standard`, `high`, `lossless`, `hiRes`, `auto`).

#### Return Value
Returns an object with stream details:
```javascript
{
  "url": "https://stream.example.com/audio/12345678.flac",
  "headers": {
    "Authorization": "Bearer ...",
    "User-Agent": "..."
  },
  "format": "flac",               // e.g. "mp3", "m4a", "flac"
  "bitrate": 1411200,             // Bitrate in bps
  "sampleRate": 96000,            // Sample rate in Hz
  "bitDepth": 24,                 // 16 or 24 bit
  "expiresAt": "2026-10-06T13:00:00Z" // Optional ISO timestamp when URL expires
}
```

---

## 4. Example Audio Provider (`index.js`)

```javascript
globalThis.searchAudio = async function(query) {
  const searchTerm = `${query.title} ${query.artists.join(' ')}`;
  const res = await wisp.fetch(`https://api.example.com/search?q=${encodeURIComponent(searchTerm)}`);
  const data = await res.json();

  return (data.tracks || []).map(t => ({
    mediaId: String(t.id),
    title: t.title,
    artist: t.artist_name,
    album: t.album_title,
    durationMs: t.duration * 1000,
    thumbnailUrl: t.cover_url,
    qualityLabel: t.is_lossless ? 'Lossless CD' : '320 kbps',
    score: 1.0
  }));
};

globalThis.getStreamUrl = async function(mediaId, options) {
  const res = await wisp.fetch(`https://api.example.com/track/${mediaId}/stream?quality=${options.preferredQuality || 'high'}`);
  const data = await res.json();

  return {
    url: data.streamUrl,
    headers: {
      'User-Agent': 'wisp-audio-client/1.0'
    },
    format: data.format || 'mp3',
    bitrate: data.bitrate || 320000,
    // Optional encrypted stream configuration (e.g. for Spotify AES-128-CTR Ogg Vorbis streams)
    customData: {
      cipher: {
        algorithm: 'aes-128-ctr',
        keyHex: '...',
        ivHex: '72e067fbddcbcf77ebe8bc643f630d93',
        skipBytes: 167
      }
    }
  };
};
```


