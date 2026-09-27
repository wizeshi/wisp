## wisp Providers Architecture

This directory contains the default, app-developed providers. Here's how that works:

When accessing an applicable view, the app needs to know which are avaliable for installation. This is done in two ways:
1. Fetching information from the remote GitHub repo;
2. In Debug Mode (and other situations), the app can also fetch from the local repo.

It also loads the already installed ones from `<ApplicationSupportDirectory>/providers/lyrics/`

There are two types of providers: `metadata` & `lyrics`, each having their own subfolder in this folder.

The providers are written in JS, and are ran using `flutter_js` (QuickJS on Windows, Linux & Android, JSCore on macOS/iOS)

Each provider needs a `manifest.json` file, which itself points to the provider's entry point (usually `index.js`). It looks something like this:
```jsonc
{
  "id": "example-lyrics", // The internal ID of the provider
  "name": "Example Lyrics", // Provider's visible name
  "version": "1.0.0", // A version number. Use it however you please
  "type": "lyrics", // The type. Can be either "lyrics" or "metadata"
  "entry": "index.js", // The entry point
  "author": "wizeshi", // You, the author
  "description": "An example lyrics provider.", // A simple description. Keep it to one sentence.
  "supportedSyncModes": ["word", "line", "unsynced"], // This is lyrics-specific. These are also all the avaliable ones for lyrics.
  "priority": 70, // Dictates how reliable it is (e.g. usually Apple Music is better than Spotify, so its priority should be higher)
  "homepage": "https://example.com", // If you wanna have a link to you :)
}
```

Providers have access to a global `wisp` object, which has:
- `wisp.fetch(url, options)`: Sandboxed network request routed through the app's native HTTP client (supporting custom TLS bad-cert callbacks for providers like Spotify).
- `wisp.spotify.getTokens(options)`: Obtains active Spotify WebPlayer `accessToken` and `clientToken` via the app's secure credentials bridge (supports `{ forceRefresh: true }`).

### Standard Lyrics Providers
1. **BetterLyrics** (`providers/lyrics/betterlyrics`) - Priority: `70`. Word-synced and line-synced lyrics via BetterLyrics TTML API.
2. **Spotify** (`providers/lyrics/spotify`) - Priority: `60`. Line-synced and unsynced lyrics directly from Spotify Color Lyrics API with fallback catalog search.
3. **LRCLIB** (`providers/lyrics/lrclib`) - Priority: `50`. Line-synced and plain lyrics from the open LRCLIB database.