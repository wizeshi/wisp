// SpicyLyrics Auth Provider for wisp
// Manages developer API keys via native promptInput dialog and wisp.service vault.

class SpicyLyricsAuthProvider {
  constructor(serviceId = 'spicylyrics') {
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
    return !!(session && (session.apiKey || session.accessToken));
  }

  async getAccessToken() {
    const tokens = await this.getTokens();
    return tokens ? tokens.accessToken : null;
  }

  async getTokens() {
    const session = await this.getSession();
    if (session && (session.apiKey || session.accessToken)) {
      const key = session.apiKey || session.accessToken;
      return {
        accessToken: key,
        apiKey: key
      };
    }
    return null;
  }

  async login() {
    if (!wisp.auth || typeof wisp.auth.promptInput !== 'function') {
      console.warn('[SpicyLyrics/Auth] wisp.auth.promptInput not available');
      return null;
    }

    const current = await this.getSession();
    const res = await wisp.auth.promptInput({
      title: 'SpicyLyrics API Key',
      description: 'Enter your SpicyLyrics API key to access synchronized lyrics.',
      label: 'API Key',
      hint: 'sl_sk_...',
      defaultValue: (current && (current.apiKey || current.accessToken)) || '',
      link: 'https://developers.spicylyrics.org/dashboard',
      linkText: 'Get API Key',
      isSecret: true
    });

    if (res && res.value && res.value.trim()) {
      const apiKey = res.value.trim();
      await wisp.service.setSession(this.serviceId, {
        apiKey: apiKey,
        accessToken: apiKey
      });
      console.log('[SpicyLyrics/Auth] API Key saved to session vault successfully');
      return { accessToken: apiKey, apiKey: apiKey };
    }

    return null;
  }

  async logout() {
    if (wisp.service && typeof wisp.service.clearSession === 'function') {
      await wisp.service.clearSession(this.serviceId);
    }
    console.log('[SpicyLyrics/Auth] Session cleared');
    return true;
  }
}

const authInstance = new SpicyLyricsAuthProvider('spicylyrics');

const AuthExport = {
  login: () => authInstance.login(),
  logout: () => authInstance.logout(),
  getSession: () => authInstance.getSession(),
  isAuthenticated: () => authInstance.isAuthenticated(),
  getTokens: () => authInstance.getTokens()
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = AuthExport;
}

for (const [key, fn] of Object.entries(AuthExport)) {
  globalThis[key] = fn;
}

