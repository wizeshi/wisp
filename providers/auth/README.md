# wisp Auth Providers Specification

Auth providers (`type: "auth"`) manage user authentication, session persistence, credential vaults, and token refresh logic for wisp and its dependent services.

Every enabled auth provider appears as a dedicated account card in **Settings -> ACCOUNTS**, allowing users to log in, view connection state, and disconnect.

---

## 1. Directory Structure

```
providers/auth/{id}/
  ├── manifest.json
  ├── index.js
  └── icon.png (or icon.svg)
```

---

## 2. Manifest Specification (`manifest.json`)

### Common Fields
- `id` (`string`): Unique identifier (e.g. `spotify`, `spicylyrics`).
- `name` (`string`): Human-readable service name.
- `version` (`string`): Semantic version.
- `type` (`string`): Must be `"auth"`.
- `entry` (`string`): Main JavaScript script (default: `index.js`).
- `author` (`string`): Author name.
- `description` (`string`): Summary of the authentication provider.
- `priority` (`number`): Ordering priority (default: `100`).
- `homepage` (`string?`): Developer or service homepage.

### Exclusive Auth Manifest Fields
| Field | Type | Description |
|---|---|---|
| `service` | `string` | **Required**. The service namespace identifier used by `wisp.service` vault and token delegation. Dependent metadata and lyrics providers reference this via their `service` and `dependencies` fields (e.g. `"service": "spotify"`, `"dependencies": ["auth/spotify"]`). |

### Example Manifest
```json
{
  "id": "spicylyrics",
  "name": "Spicy Lyrics Auth",
  "version": "1.0.0",
  "type": "auth",
  "service": "spicylyrics",
  "entry": "index.js",
  "author": "wizeshi",
  "description": "API key authentication for SpicyLyrics services",
  "priority": 100,
  "homepage": "https://spicylyrics.org/"
}
```

---

## 3. Required JavaScript Interface

An auth provider's entry script must define and export the following functions (or assign them to `globalThis`):

| Method | Signature | Description |
|---|---|---|
| `login()` | `async () => any` | Initiates user authentication flow. Typically calls `wisp.auth.promptInput` (for API keys/passwords) or `wisp.auth.openLogin` (for OAuth webviews). Stores credentials in `wisp.service.setSession(serviceId, ...)` and returns the session object. |
| `logout()` | `async () => boolean` | Clears credentials using `wisp.service.clearSession(serviceId)`. Returns `true` on success. |
| `getSession()` | `async () => object?` | Reads the currently persisted session from `wisp.service.getSession(serviceId)`. |
| `isAuthenticated()` | `async () => boolean` | Returns `true` if valid authentication credentials or session tokens are active in the vault. |
| `getTokens(forceRefresh?)` | `async (forceRefresh?: boolean) => object?` | Returns active credentials (e.g. `{ accessToken: '...' }`). If tokens are expired or `forceRefresh` is `true`, performs renewal using `wisp.service.withRefreshLock(serviceId, ...)`. |

---

## 4. Implementation Patterns

### Pattern A: API Key Auth (`wisp.auth.promptInput`)
Used when users provide a personal API key or token:

```javascript
class ApiKeyAuthProvider {
  constructor(serviceId = 'spicylyrics') {
    this.serviceId = serviceId;
  }

  async getSession() {
    return await wisp.service.getSession(this.serviceId);
  }

  async isAuthenticated() {
    const session = await this.getSession();
    return !!(session && (session.apiKey || session.accessToken));
  }

  async getTokens() {
    const session = await this.getSession();
    if (session && session.apiKey) {
      return { accessToken: session.apiKey, apiKey: session.apiKey };
    }
    return null;
  }

  async login() {
    const res = await wisp.auth.promptInput({
      title: 'SpicyLyrics API Key',
      description: 'Enter your developer API key.',
      label: 'API Key',
      hint: 'sl_sk_...',
      isSecret: true,
      link: 'https://developers.spicylyrics.org',
      linkText: 'Get API Key'
    });

    if (res && res.value && res.value.trim()) {
      const apiKey = res.value.trim();
      await wisp.service.setSession(this.serviceId, { apiKey: apiKey, accessToken: apiKey });
      return { accessToken: apiKey };
    }
    return null;
  }

  async logout() {
    await wisp.service.clearSession(this.serviceId);
    return true;
  }
}

const auth = new ApiKeyAuthProvider('spicylyrics');
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    login: () => auth.login(),
    logout: () => auth.logout(),
    getSession: () => auth.getSession(),
    isAuthenticated: () => auth.isAuthenticated(),
    getTokens: (force) => auth.getTokens(force)
  };
}
```

### Pattern B: Webview & Cookie Capture (`wisp.auth.openLogin`)
Used for OAuth or web session cookie capture:

```javascript
async function login() {
  const result = await wisp.auth.openLogin({
    url: 'https://accounts.spotify.com/en/login',
    title: 'Log in to Spotify',
    captureCookies: ['sp_dc', 'sp_key'],
    redirectUrlPrefix: 'https://open.spotify.com'
  });

  if (result && result.cookies && result.cookies.sp_dc) {
    await wisp.service.setSession('spotify', {
      cookies: result.cookies,
      updatedAt: Date.now()
    });
    return result;
  }
  return null;
}
```

