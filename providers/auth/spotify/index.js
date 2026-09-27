// Spotify Auth Provider for Wisp
// Provides authentication, cookie capture, TOTP token exchanges, and token refresh
// for Spotify-dependent providers (metadata, lyrics, etc.) via wisp.service vault.

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const APP_VERSION = '1.2.96.238.g5c95ebca';

class SpotifyAuthProvider {
  constructor(serviceId = 'spotify') {
    this.serviceId = serviceId;
  }

  async getSession() {
    if (!wisp.service || typeof wisp.service.getSession !== 'function') {
      return null;
    }
    return await wisp.service.getSession(this.serviceId);
  }

  async isAuthenticated() {
    const session = await this.getSession();
    return !!(session && ((session.cookies && session.cookies.sp_dc) || session.cookie || session.accessToken));
  }

  async getAccessToken() {
    const tokens = await this.getTokens();
    return tokens ? tokens.accessToken : null;
  }

  async getTokens(forceRefresh = false) {
    const session = await this.getSession();
    const now = Date.now();

    if (!forceRefresh && session && session.accessToken && (now < (session.expiresAtMs - 60000))) {
      return session;
    }

    if (!wisp.service || typeof wisp.service.withRefreshLock !== 'function') {
      return null;
    }

    return await wisp.service.withRefreshLock(this.serviceId, async () => {
      const current = await this.getSession();
      if (!forceRefresh && current && current.accessToken && (Date.now() < (current.expiresAtMs - 60000))) {
        return current;
      }

      let spDc = (current && current.cookies && current.cookies.sp_dc) || (current && current.cookie) || null;

      if (!spDc) {
        console.warn('[Spotify/Auth] NOT_AUTHENTICATED: sp_dc cookie missing in vault.');
        return null;
      }

      console.log('[Spotify/Auth] Refreshing Spotify tokens via TOTP web authentication...');

      const secretUrls = [
        'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json',
        'https://raw.githubusercontent.com/spotandfly/spotify-secrets/main/secrets.json'
      ];

      let latestSecret = null;
      for (let i = 0; i < secretUrls.length; i++) {
        try {
          const secretsRes = await wisp.fetch(secretUrls[i]);
          if (secretsRes.status === 200) {
            const secrets = await secretsRes.json();
            if (Array.isArray(secrets) && secrets.length > 0) {
              latestSecret = secrets[secrets.length - 1];
              break;
            }
          }
        } catch (e) {
          console.warn('[Spotify/Auth] Secrets fetch failed from ' + secretUrls[i] + ': ' + e);
        }
      }

      if (!latestSecret || !latestSecret.secret) {
        console.error('[Spotify/Auth] Could not retrieve TOTP secret');
        return null;
      }

      const otp = await this._generateOtp(latestSecret.secret);
      const cleanCookie = spDc.startsWith('sp_dc=') ? spDc : ('sp_dc=' + spDc);
      const accessUrl = 'https://open.spotify.com/api/token?reason=transport&productType=web-player' +
        '&totp=' + encodeURIComponent(otp) +
        '&totpServer=' + encodeURIComponent(otp) +
        '&totpVer=' + encodeURIComponent(String(latestSecret.version));

      const accessRes = await wisp.fetch(accessUrl, {
        headers: {
          'Cookie': cleanCookie,
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/'
        }
      });

      if (accessRes.status !== 200) {
        console.error('[Spotify/Auth] Access token request failed: ' + accessRes.status);
        return null;
      }

      const accessData = await accessRes.json();
      if (!accessData || !accessData.accessToken) {
        console.error('[Spotify/Auth] No accessToken in response');
        return null;
      }

      let clientToken = null;
      try {
        const deviceId = await wisp.crypto.randomHex(32);
        const clientTokenRes = await wisp.fetch('https://clienttoken.spotify.com/v1/clienttoken', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            client_data: {
              client_id: accessData.clientId,
              client_version: APP_VERSION,
              js_sdk_data: {
                device_brand: 'unknown',
                device_id: deviceId,
                device_model: 'unknown',
                device_type: 'computer',
                os: 'windows',
                os_version: 'NT 10.0'
              }
            }
          })
        });

        if (clientTokenRes.status === 200) {
          const clientData = await clientTokenRes.json();
          if (clientData && clientData.response_type === 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
            clientToken = clientData.granted_token && clientData.granted_token.token;
          }
        }
      } catch (e) {
        console.warn('[Spotify/Auth] Client token acquisition warning: ' + e);
      }

      const cleanSpDc = cleanCookie.replace(/^sp_dc=/, '');
      const newSession = {
        accessToken: accessData.accessToken,
        clientToken: clientToken || '',
        cookies: { sp_dc: cleanSpDc },
        expiresAtMs: accessData.accessTokenExpirationTimestampMs || (Date.now() + 3600000),
        clientId: accessData.clientId
      };

      await wisp.service.setSession(this.serviceId, newSession);
      console.log('[Spotify/Auth] Tokens successfully refreshed in vault (expires in: ' +
        Math.round((newSession.expiresAtMs - Date.now()) / 1000) + 's)');

      return newSession;
    });
  }

  async _generateOtp(secretValue) {
    const secretCipherBytes = [];
    for (let i = 0; i < secretValue.length; i++) {
      secretCipherBytes.push(secretValue.charCodeAt(i) ^ ((i % 33) + 9));
    }
    const cipherString = secretCipherBytes.join('');
    const cipherBytes = [];
    for (let i = 0; i < cipherString.length; i++) {
      cipherBytes.push(cipherString.charCodeAt(i));
    }

    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let t = 0;
    let n = 0;
    let base32Secret = '';
    for (let i = 0; i < cipherBytes.length; i++) {
      n = (n << 8) | cipherBytes[i];
      t += 8;
      while (t >= 5) {
        base32Secret += alphabet[(n >> (t - 5)) & 31];
        t -= 5;
      }
    }
    if (t > 0) {
      base32Secret += alphabet[(n << (5 - t)) & 31];
    }

    return await wisp.crypto.totp(base32Secret);
  }

  async login() {
    if (!wisp.auth || typeof wisp.auth.openLogin !== 'function') {
      console.warn('[Spotify/Auth] wisp.auth.openLogin not available');
      return null;
    }
    const res = await wisp.auth.openLogin({
      url: 'https://accounts.spotify.com/en/login',
      title: 'Log in to Spotify',
      targetCookies: ['sp_dc']
    });
    if (res && res.cookies && res.cookies.sp_dc) {
      const spDc = res.cookies.sp_dc;
      await wisp.service.setSession(this.serviceId, {
        cookies: { sp_dc: spDc }
      });
      return await this.getTokens(true);
    }
    return null;
  }

  async logout() {
    if (wisp.service && typeof wisp.service.clearSession === 'function') {
      await wisp.service.clearSession(this.serviceId);
    }
    console.log('[Spotify/Auth] Logged out and session cleared');
    return true;
  }
}

const authInstance = new SpotifyAuthProvider('spotify');

const AuthExport = {
  login: () => authInstance.login(),
  logout: () => authInstance.logout(),
  getSession: () => authInstance.getSession(),
  isAuthenticated: () => authInstance.isAuthenticated(),
  getTokens: (forceRefresh) => authInstance.getTokens(forceRefresh)
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = AuthExport;
}

for (const [key, fn] of Object.entries(AuthExport)) {
  globalThis[key] = fn;
}
