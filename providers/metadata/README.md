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

// Search track by International Standard Recording Code (ISRC)
async function searchByIsrc(isrc) {
  // Returns: GenericSong or null
}

// Track details
async function getTrack(id) {
  // Returns: GenericSong
}

// Batch track details (chunked to 50 items)
async function getTracks(ids) {
  // Returns: Array of GenericSong
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

// Shareable Web URL for any entity
async function getShareUrl(type, id) {
  // type: 'track' | 'album' | 'artist' | 'playlist'
  // Returns: string URL or null
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
async function getUserLibrary(options = {}) {
  // options: { sortMode: 'recent' | 'alphabetical' | 'recentlyAdded' }
  // Returns: { saved_albums: [...], saved_playlists: [...], saved_artists: [...] }
}

async function getUserPlaylists() {
  // Returns: List of GenericPlaylist
}

// Capability: "playlist_management"
async function createPlaylist(options) { ... }
async function renamePlaylist(playlistId, name) { ... }
async function updatePlaylistDetails(playlistId, { name, description, isPublic }) { ... }
async function deletePlaylist(playlistId) { ... }
async function addTracksToPlaylist(playlistId, trackIds) { ... }
async function removeTracksFromPlaylist(playlistId, trackIds) { ... }
async function reorderPlaylistTracks(playlistId, oldIndex, newIndex) { ... }

// Capability: "recommendations"
async function getRecommended({ seedTracks, seedArtists, limit }) { ... }
async function getSimilarTracks(trackId, limit) { ... }

// Track favorites & library mutations
async function likeTrack(id) { ... }
async function unlikeTrack(id) { ... }
async function getCuratedStatus(trackIds) {
  // Returns: Array of booleans or Map indicating saved/liked status
}
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

---

## 5. Source Linking Contract & Provider Icons

### The `source` Linking Contract
Every entity returned by a metadata provider (`GenericSong`, `GenericAlbum`, `GenericArtist`, `GenericPlaylist`, `GenericSimpleUser`) **MUST** set its `"source"` property to match the canonical provider `id` declared in its `manifest.json` (e.g., `"source": "spotify"`):

- **Origin-First Resolution**: When navigating to an album, playlist, or artist detail view, wisp reads the entity's `source` and directs initial fetches and cache lookups to that specific provider first.
- **Heterogeneous Playlists & Queues**: wisp supports playlists and playback queues composed of tracks from multiple providers. The `source` property on each track item allows `MetadataManager.getTracksForItems` to segment items by origin, query the corresponding metadata providers concurrently, and preserve original ordering.
- **Audio Matching & Fallback**: Playback coordinators use `source` to identify which metadata catalog owns the track ID and ISRC, ensuring accurate stream resolution against audio providers.

### Provider Icons
Each provider directory should include an icon asset in its root directory:
```
providers/metadata/{id}/
  ├── manifest.json
  ├── index.js
  └── icon.svg (or icon.png)
```
- **Vector Preferred**: `icon.svg` is strongly recommended for clean scaling across high-DPI desktop and mobile screens.
- **Dynamic Resolution**: wisp automatically discovers and displays provider icons via `ProviderIcon(providerId: entity.source, type: 'metadata')` across search bars, source filters, and detail badges. If no icon asset is provided, wisp gracefully falls back to default category icons.


