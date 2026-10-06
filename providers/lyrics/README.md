# wisp Lyrics Providers & WLF Specification

Lyrics providers (`type: "lyrics"`) fetch and synchronize lyrics across unsynced, line-synced, word-synced, and syllable-synced levels for playback in wisp.

All lyrics providers normalize their results into the **wisp Lyrics Format (WLF v1.0)**. The host Dart application remains completely schema-agnostic of upstream provider APIs.

---

## 1. Directory Structure

```
providers/lyrics/{id}/
  ├── manifest.json
  ├── index.js
  └── icon.png (or icon.svg)
```

---

## 2. Manifest Specification (`manifest.json`)

### Common Fields
- `id` (`string`): Unique provider ID (e.g. `spicylyrics`, `betterlyrics`, `lrclib`, `spotify`).
- `name` (`string`): Display name.
- `version` (`string`): SemVer version string.
- `type` (`string`): Must be `"lyrics"`.
- `entry` (`string`): Main JavaScript entrypoint (default: `index.js`).
- `author` (`string`): Author name.
- `description` (`string`): Description of provider features.
- `priority` (`number`): Resolution precedence when querying lyrics for a track.
- `service` (`string?`): Optional service realm ID for session credentials.
- `dependencies` (`string[]?`): Optional package dependencies (e.g. `["auth/spicylyrics"]`).
- `homepage` (`string?`): Documentation or service homepage.

### Exclusive Lyrics Manifest Fields
| Field | Type | Description |
|---|---|---|
| `supportedSyncModes` | `string[]` | **Exclusive to lyrics**. Array declaring which precision levels this provider can deliver. Values: `"word"`, `"line"`, and/or `"unsynced"`. Used by wisp to match user preferences and compute provider capability tiers in the marketplace. |

### Example Manifest
```json
{
  "id": "spicylyrics",
  "name": "Spicy Lyrics",
  "version": "2.0.0",
  "type": "lyrics",
  "entry": "index.js",
  "author": "wizeshi",
  "description": "Word-synced, syllable-synced, and opposite-aligned lyrics using the SpicyLyrics Public v1 API",
  "supportedSyncModes": [
    "word",
    "line",
    "unsynced"
  ],
  "priority": 85,
  "service": "spicylyrics",
  "dependencies": [
    "auth/spicylyrics"
  ],
  "homepage": "https://spicylyrics.org/"
}
```

---

## 3. JavaScript Interface (`getLyrics`)

Every lyrics provider must export an `async function getLyrics(query)`:

```javascript
async function getLyrics(query) {
  // query properties:
  // - query.title: string
  // - query.artist: string
  // - query.album: string
  // - query.durationSecs: number
  // - query.id: string (track ID if playback originated from this source)
  // - query.source: string (playback source name, e.g. "spotify")
  // - query.mode: "word" | "line" | "unsynced"

  // Returns: WLF JSON object, or null if no lyrics found
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getLyrics };
}
```

---

## 4. wisp Lyrics Format (WLF v1.0) Specification

### Precision Modes (`syncMode`)
- **`word`**: Syllable-level or word-level timing precision with fluid fill animations.
- **`line`**: Line-synchronized timing (`startTimeMs` per line).
- **`unsynced`**: Static plain-text lyrics without playback timing.

### Line Structure
- `content`: Plain string for the line.
- `startTimeMs`: Line start time in milliseconds.
- `endTimeMs`: Optional line end time in milliseconds.
- `words`: Array of timed syllables/words:
  - `content`: Syllable or word text.
  - `startTimeMs`: Start time in milliseconds.
  - `endTimeMs`: End time in milliseconds.
  - `partOfWord`: Boolean. When `true`, indicates this syllable attaches directly to the adjacent syllable without an extra space (e.g. `"Ha-"`, `"ha-"`).

### Opposite-Aligned Vocals (Duets)
The `speaker` property designates vocal assignment:
- `'left'`: Default primary/lead vocalist (left-aligned in UI).
- `'right'`: Opposite/secondary vocalist (right-aligned in UI for duets).

### Synchronized Background Vocals
Background vocal phrases can accompany any lead line via the `background` array:
- `content`: Plain string representing the vocal phrase (e.g. `"Louder"`).
- `startTimeMs`: Phrase start time in milliseconds.
- `endTimeMs`: Phrase end time in milliseconds.
- `words`: Optional syllable-level timing array for word-fill animations.

The UI renders background vocals progressively as playback reaches `startTimeMs`, appearing below the parent line in an italicized secondary style.

### Attribution Credits & Markdown Links
The `attribution` property provides source information and contributor credits.
- Plain string credits (e.g. `"Sourced using Musixmatch"`, `"Sourced using Apple Music"`).
- Markdown links for community contributors:
  ```markdown
  Lyrics uploaded by [username](https://example.com/u/username)
  Lyrics written by [author](https://example.com/u/author)
  ```
wisp parses these markdown links into interactive, clickable spans that open in the user's default browser.

### Complete WLF Schema Example

```json
{
  "version": "1.0",
  "provider": "spicylyrics",
  "syncMode": "word",
  "attribution": "Sourced using Apple Music",
  "lines": [
    {
      "content": "Ha-ha-ha",
      "startTimeMs": 5110,
      "endTimeMs": 9884,
      "speaker": "left",
      "words": [
        { "content": "Ha-", "startTimeMs": 5110, "endTimeMs": 5945, "partOfWord": true },
        { "content": "ha-", "startTimeMs": 5945, "endTimeMs": 6804, "partOfWord": true },
        { "content": "ha", "startTimeMs": 6804, "endTimeMs": 9884, "partOfWord": false }
      ],
      "background": []
    },
    {
      "content": "And pump it",
      "startTimeMs": 15898,
      "endTimeMs": 17657,
      "speaker": "left",
      "words": [
        { "content": "And", "startTimeMs": 15898, "endTimeMs": 16055, "partOfWord": false },
        { "content": "pump", "startTimeMs": 16055, "endTimeMs": 16392, "partOfWord": false },
        { "content": "it", "startTimeMs": 16392, "endTimeMs": 16584, "partOfWord": false }
      ],
      "background": [
        {
          "content": "Louder",
          "startTimeMs": 16752,
          "endTimeMs": 17657,
          "words": [
            { "content": "Loud", "startTimeMs": 16752, "endTimeMs": 17216, "partOfWord": true },
            { "content": "er", "startTimeMs": 17216, "endTimeMs": 17657, "partOfWord": false }
          ]
        }
      ]
    }
  ]
}
```

