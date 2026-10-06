# wisp Metadata Providers Specification

Metadata providers (`type: "metadata"`) supply musical data across wisp, including track metadata, catalog searches, albums, artist top tracks, discographies, playlists, recommendations, and animated canvas visuals.

---

## 1. Directory Structure

```
providers/metadata/{id}/
  ├── manifest.json
  ├── index.js
  └── icon.png (or icon.svg)
```

---

## 2. Manifest Specification (`manifest.json`)

### Common Fields
- `id` (`string`): Unique provider ID (e.g. `spotify`).
- `name` (`string`): Display name.
- `version` (`string`): SemVer version string.
- `type` (`string`): Must be `"metadata"`.
- `entry` (`string`): Main JavaScript entrypoint (default: `index.js`).
- `author` (`string`): Author name.
- `description` (`string`): Description of provider features.
- `priority` (`number`): Resolution precedence when aggregating metadata sources.
- `homepage` (`string?`): Documentation or service homepage.

### Exclusive Metadata Manifest Fields
| Field | Type | Description |
|---|---|---|
| `capabilities` | `string[]` | **Exclusive to metadata**. List of discrete features supported by this metadata provider. Used by wisp to conditionally display UI features (like home feed tabs, canvas video backgrounds, recommendation rows, or playlist editor buttons). |
| `service` | `string?` | Optional service realm identifier for token retrieval from the session vault. |
| `dependencies` | `string[]?` | Package dependencies (e.g. `["auth/spotify"]`). |

### Supported Metadata Capabilities
wisp recognizes the following capability flags in `manifest.json`:

| Capability Flag | Identifier in Code | Description |
|---|---|---|
| `"search"` | `MetadataCapability.search` | General search across tracks, albums, artists, and playlists. |
| `"home"` | `MetadataCapability.home` | Populates the Home feed (`getUserHome()` returning section trays and shelves). |
| `"canvas"` | `MetadataCapability.canvas` | Provides looped video canvas URLs (`getCanvasUrl(trackId)`). |
| `"npv"` | `MetadataCapability.npv` | Now-playing view extra metadata (release notes, extended artist credits). |
| `"library"` | `MetadataCapability.library` | Reads user's saved albums, playlists, and artists (`getUserLibrary()`). |
| `"playlist_management"` | `MetadataCapability.playlistManagement` | Creates, renames, deletes, and edits tracks in playlists. |
| `"recommendations"` | `MetadataCapability.recommendations` | Provides radio and track recommendations (`getRecommended()`, `getSimilarTracks()`). |
| `"user_profile"` | `MetadataCapability.userProfile` | User profile avatar, following, and followers metadata. |

### Example Manifest
```json
{
  "id": "spotify",
  "name": "Spotify",
  "version": "1.1.4",
  "type": "metadata",
  "entry": "index.js",
  "author": "wizeshi",
  "description": "Spotify catalog, search, albums, artists, playlists, user library, and canvas metadata provider.",
  "service": "spotify",
  "dependencies": ["auth/spotify"],
  "capabilities": [
    "search",
    "home",
    "canvas",
    "npv",
    "library",
    "playlist_management",
    "recommendations",
    "user_profile"
  ],
  "priority": 100,
  "homepage": "https://spotify.com"
}
```

---

## 3. JavaScript Interface Methods

A metadata provider implements or exports methods depending on its declared capabilities:

### Core Catalog Methods
```javascript
// Search catalog
async function search(query, types = ['track', 'album', 'artist', 'playlist'], limit = 20) {
  // Returns: { tracks: [...], albums: [...], artists: [...], playlists: [...] }
}

// Track details
async function getTrack(id) {
  // Returns: GenericSong
}

// Album details and tracklist
async function getAlbum(id) {
  // Returns: GenericAlbum
}

// Artist bio, top tracks, and albums
async function getArtist(id) {
  // Returns: GenericArtist
}

// Playlist details and tracks
async function getPlaylist(id) {
  // Returns: GenericPlaylist
}
```

### Capability-Specific Methods
```javascript
// Capability: "canvas"
async function getCanvasUrl(trackId) {
  // Returns: string URL of canvas MP4 video, or null
}

// Capability: "home"
async function getUserHome() {
  // Returns: { sections: { 'Recently Played': [...], 'Featured': [...] } }
}

// Capability: "library"
async function getUserLibrary() {
  // Returns: { saved_albums: [...], saved_playlists: [...], saved_artists: [...] }
}

async function getUserPlaylists() {
  // Returns: List of GenericPlaylist
}

// Capability: "playlist_management"
async function createPlaylist(name, description) { ... }
async function addTracksToPlaylist(playlistId, trackIds) { ... }
async function removeTracksFromPlaylist(playlistId, trackIds) { ... }
async function deletePlaylist(playlistId) { ... }

// Capability: "recommendations"
async function getRecommended({ seedTracks, seedArtists, limit }) { ... }
async function getSimilarTracks(trackId, limit) { ... }

// Track favorites & library mutations
async function likeTrack(id) { ... }
async function unlikeTrack(id) { ... }
```

---

## 4. Entity Schemas

### `GenericSong`
```json
{
  "id": "track_id",
  "source": "spotify",
  "title": "Song Title",
  "artist": "Lead Artist",
  "album": "Album Name",
  "album_id": "album_id",
  "thumbnail_url": "https://...",
  "duration_secs": 215,
  "explicit": false,
  "artists": [
    { "id": "artist_id", "name": "Artist Name", "thumbnail_url": "https://..." }
  ]
}
```

### `GenericAlbum`
```json
{
  "id": "album_id",
  "source": "spotify",
  "title": "Album Title",
  "thumbnail_url": "https://...",
  "artists": [...],
  "tracks": [ /* GenericSong objects */ ],
  "release_date": "2024-05-10T00:00:00.000Z",
  "label": "Record Label",
  "explicit": false
}
```

