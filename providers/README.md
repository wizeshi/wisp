# wisp Providers Architecture

wisp is designed around an open, modular provider architecture. Providers extend the application with custom audio metadata retrieval, synchronized lyrics fetching, and third-party authentication services.

Every provider runs inside an isolated, secure JavaScript environment powered by `flutter_js` (QuickJS on Windows, Linux, and Android; JavaScriptCore on macOS and iOS).

---

## Provider Categories & Documentation

The provider ecosystem is organized into four distinct categories, each with its own specifications and manifest contracts:

| Type | Directory | Documentation | Description |
|---|---|---|---|
| **Audio** | `providers/audio/` | [Audio Providers Documentation](audio/README.md) | Supplies direct audio stream candidates and playable stream URLs (e.g. Qobuz, YouTube, SoundCloud). |
| **Auth** | `providers/auth/` | [Auth Providers Documentation](auth/README.md) | Manages authentication, session vaults, and token renewal. Appears under **Settings -> ACCOUNTS**. |
| **Metadata** | `providers/metadata/` | [Metadata Providers Documentation](metadata/README.md) | Supplies tracks, albums, artist catalogs, search, user libraries, home feed trays, and canvas visuals. |
| **Lyrics** | `providers/lyrics/` | [Lyrics Providers Documentation](lyrics/README.md) | Normalizes lyrics into the universal **wisp Lyrics Format (WLF v1.0)** across word, line, and unsynced precision. |

---

## 1. Provider Discovery & Directory Layout

### Discovery
wisp discovers providers through two complementary mechanisms:
1. **Local Workspace**: Scans `providers/` recursively across `audio/`, `metadata/`, `lyrics/`, and `auth/` subdirectories.
2. **Remote Repository**: Fetches the directory tree from the official GitHub repository (`wizeshi/wisp`).

Installed providers reside in the application support directory:
```
<ApplicationSupportDirectory>/providers/
  ├── audio/
  │   └── qobuz/
  ├── auth/
  │   ├── spicylyrics/
  │   └── spotify/
  ├── lyrics/
  │   ├── betterlyrics/
  │   ├── lrclib/
  │   ├── spicy-lyrics/
  │   └── spotify/
  └── metadata/
      └── spotify/
```

Each package folder contains:
- `manifest.json`: Metadata, capabilities, dependencies, and entrypoint definition.
- `index.js`: The JavaScript implementation.
- `icon.png` or `icon.svg` (optional): Branded icon rendered across the marketplace and settings.

---

## 2. Common Manifest Specification (`manifest.json`)

All provider manifests share these common fields:

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Unique identifier (e.g. `spotify`, `spicylyrics`). |
| `name` | `string` | Human-readable name. |
| `version` | `string` | Semantic version string (`MAJOR.MINOR.PATCH`). |
| `type` | `string` | Provider category: `"auth"`, `"metadata"`, or `"lyrics"`. |
| `entry` | `string` | Main JavaScript script (default: `index.js`). |
| `author` | `string` | Author name or handle. |
| `description` | `string` | Brief description of provider functionality. |
| `priority` | `number` | Ordering weight when resolving track metadata or lyrics. |
| `service` | `string?` | Optional service realm identifier for token and session storage. |
| `dependencies` | `string[]?` | List of package identifiers that must be installed/enabled. |
| `homepage` | `string?` | URL for documentation or developer website. |

### Type-Exclusive Manifest Fields

Each category defines exclusive properties in its manifest:

- **Auth Providers**:
  - `service` (`string`): **Required** for auth providers. Declares the service realm namespace in the session vault for dependent providers to link to.
- **Metadata Providers**:
  - `capabilities` (`string[]`): **Exclusive to metadata**. Declares discrete features supported: `"search"`, `"home"`, `"canvas"`, `"npv"`, `"library"`, `"playlist_management"`, `"recommendations"`, `"user_profile"`.
- **Lyrics Providers**:
  - `supportedSyncModes` (`string[]`): **Exclusive to lyrics**. Array declaring supported precision levels: `"word"`, `"line"`, and/or `"unsynced"`.

---

## 3. Sandbox Runtime APIs (`wisp.*`)

All JavaScript execution takes place within a sandboxed worker. Communication with native Dart subsystems occurs via the injected `wisp` global namespace.

### HTTP Client (`wisp.fetch`)
Executes asynchronous HTTP requests through the native Dart network layer (bypassing browser CORS restrictions and supporting custom TLS options).

```javascript
const response = await wisp.fetch(url, {
  method: 'GET', // 'GET', 'POST', 'PUT', 'DELETE', etc.
  headers: {
    'Accept': 'application/json',
    'Authorization': 'Bearer ' + token
  },
  body: JSON.stringify({ trackId: '...' }), // Optional string or Uint8Array
  label: 'ColorLyrics API'                  // Optional debugging label
});

const status = response.status;     // e.g. 200
const isOk = response.ok;           // Boolean (status in 200..299)
const data = await response.json(); // Parses JSON response
const text = await response.text(); // Raw response text
```

### Service Vault (`wisp.service`)
Persistent encrypted storage for service sessions and credentials.

- `wisp.service.getSession(serviceId)`: Retrieves stored session object for the given service.
- `wisp.service.setSession(serviceId, sessionData)`: Persists session data.
- `wisp.service.clearSession(serviceId)`: Clears stored credentials upon logout.
- `wisp.service.withRefreshLock(serviceId, async () => { ... })`: Acquires a host-level mutex across providers to prevent duplicate concurrent token refresh requests.

```javascript
// Saving an API key into the service vault
await wisp.service.setSession('spicylyrics', { apiKey: 'sl_sk_...' });

// Reading credentials
const session = await wisp.service.getSession('spicylyrics');
console.log(session.apiKey);
```

### Authentication Bridge (`wisp.auth`)
Native UI interactions for user login and token acquisition.

#### Interactive Input Dialog (`wisp.auth.promptInput`)
Displays a native Material 3 modal prompting the user for text or secret input (e.g. an API key or token):

```javascript
const result = await wisp.auth.promptInput({
  title: 'SpicyLyrics API Key',
  description: 'Enter your developer API key.',
  label: 'API Key',
  hint: 'sl_sk_...',
  isSecret: true,
  link: 'https://developers.spicylyrics.org',
  linkText: 'Get API Key'
});

if (result && !result.cancelled && result.value) {
  const apiKey = result.value.trim();
  await wisp.service.setSession('spicylyrics', { apiKey: apiKey });
}
```

#### In-App Webview Login (`wisp.auth.openLogin`)
Opens an embedded webview to capture authorization cookies or OAuth redirect tokens:

```javascript
const result = await wisp.auth.openLogin({
  url: 'https://accounts.spotify.com/en/login',
  title: 'Log in to Spotify',
  captureCookies: ['sp_dc', 'sp_key'],
  redirectUrlPrefix: 'https://open.spotify.com'
});
```

#### Token Acquisition (`wisp.auth.getTokens`)
Retrieves active access tokens from an auth provider:

```javascript
const tokens = await wisp.auth.getTokens({
  serviceId: 'spotify',
  forceRefresh: false
});

console.log(tokens.accessToken);
```

### Cryptographic Utilities (`wisp.crypto`)
High-performance native cryptography primitives:
- `wisp.crypto.totp(base32Secret, { digits, interval })`: Generates RFC 6238 TOTP codes.
- `wisp.crypto.hmacSha1(key, data)`: Computes HMAC-SHA1 signature.
- `wisp.crypto.sha256(text)`: Computes SHA-256 digest.
- `wisp.crypto.randomHex(length)`: Cryptographically secure random hex string generator.

---

## 4. Standard Built-in Providers

| Provider | Type | Priority | Description |
|---|---|---|---|
| **Spicy Lyrics** (`lyrics/spicy-lyrics`) | `lyrics` | 85 | Word-synced, syllable-synced, duet, and background lyrics via SpicyLyrics Public v1 API. |
| **SpicyLyrics Auth** (`auth/spicylyrics`) | `auth` | 100 | Secure API key input and storage via `wisp.auth.promptInput`. |
| **BetterLyrics** (`lyrics/betterlyrics`) | `lyrics` | 70 | Word-synced and line-synced lyrics via BetterLyrics TTML API. |
| **Spotify** (`lyrics/spotify`) | `lyrics` | 60 | Line-synced and unsynced lyrics via Spotify Color Lyrics API. Sourced using Musixmatch. |
| **Spotify Auth** (`auth/spotify`) | `auth` | 100 | WebPlayer session credentials and token management. |
| **Spotify Metadata** (`metadata/spotify`) | `metadata` | 100 | Track, album, and artist metadata search and catalogs. |
| **LRCLIB** (`lyrics/lrclib`) | `lyrics` | 50 | Line-synced and plain lyrics from the open LRCLIB database. |