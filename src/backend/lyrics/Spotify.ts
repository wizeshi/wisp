import { TOTP } from "totp-generator"
import { loadCredentials } from "../Credentials"

const SPOTIFY_WEB_TOKEN_URL = 'https://open.spotify.com/api/token'
const SPOTIFY_CLIENT_TOKEN_URL = 'https://clienttoken.spotify.com/v1/clienttoken'
const SPOTIFY_LYRICS_BASE_URL = 'https://spclient.wg.spotify.com/color-lyrics/v2/track'
const SPOTIFY_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

// ILY bro
const SECRETS_URL = 'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json'

const SPOTIFY_APP_VERSION = "1.2.75.277.g5c44d208"

type SpotifySecret = {
    version: number,
    secret: string
}

type SpotifyAccessTokenResponse = {
    clientId: string,
    accessToken: string,
    accessTokenExpirationTimestampMs: number,
    isAnonymous: true,
    _notes: string,
}

type SpotifyClientTokenResponse = {
    response_type: string,
    granted_token: {
        token: string,
        expires_after_seconds: number,
        refresh_after_seconds: number,
        domains: unknown
    }
}

const cleanBuffer = (e: string): Uint8Array => {
    e = e.replaceAll(" ", "");
    const length = Math.floor(e.length / 2);
    const n = new Uint8Array(length);
    for (let r = 0; r < e.length; r += 2) {
      n[Math.floor(r / 2)] = parseInt(e.substring(r, r + 2), 16);
    }
    return n;
}

const base32FromBytes = (e: Uint8Array, secretSauce: string): string => {
    let t = 0;
    let n = 0;
    let r = "";
    for (let i = 0; i < e.length; i++) {
      n = n << 8 | e[i];
      t += 8;
      while (t >= 5) {
        r += secretSauce[(n >>> (t - 5)) & 31];
        t -= 5;
      }
    }
    if (t > 0) {
      r += secretSauce[(n << (5 - t)) & 31];
    }
    return r;
}

const generateTotp = async () => {
    const secretSauce = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    const secrets = await (await fetch(SECRETS_URL)).json()
    const mostRecentSecret: SpotifySecret = secrets[secrets.length - 1]
    console.log("Most recent secret:", mostRecentSecret)

    const secretArray = mostRecentSecret.secret
		.toString()
		.split("")
		.map((char: string) => char.charCodeAt(0));
	const secretCipherBytes = secretArray.map((e: number, t: number) => e ^ ((t % 33) + 9));

	const secretBytes = cleanBuffer(
		new TextEncoder()
			.encode(secretCipherBytes.join(""))
			.reduce((acc, val) => acc + val.toString(16).padStart(2, "0"), ""),
	);

	const secret = base32FromBytes(secretBytes, secretSauce);

	return {
        totp: (await TOTP.generate(secret)).otp,
        version: mostRecentSecret.version
    };
}

class SpotifyProvider {
    private initPromise: Promise<void>
    private CLIENT_TOKEN: string
    private ACCESS_TOKEN: string

    constructor() {
        this.initPromise = this.initialize()
    }

    private async initialize() {
        const {totp, version} = await generateTotp()
        const cookie = (await loadCredentials()).spotifyCookie
        const ACCESS_TOKEN_URL = `${SPOTIFY_WEB_TOKEN_URL}?reason=init&productType=web-player&totp=${totp}&totpServer=${totp}&totpVer=${version}`

        const res = await fetch(ACCESS_TOKEN_URL, {
            headers: {
                'Cookie': cookie,
                'User-Agent': SPOTIFY_USER_AGENT
            }
        })
        
        const accessTokenResponse: SpotifyAccessTokenResponse = await res.json()
        this.ACCESS_TOKEN = accessTokenResponse.accessToken

        // Generate random device ID (32-character hex string)
        const deviceId = Array.from({length: 32}, () => 
            Math.floor(Math.random() * 16).toString(16)
        ).join('')
        
        const data = {
            client_data: {
                client_id: accessTokenResponse.clientId,
                client_version: SPOTIFY_APP_VERSION,
                js_sdk_data: {
                    device_brand: "unknown",
                    device_id: deviceId,
                    device_model: "unknown",
                    device_type: "computer",
                    os: "windows",
                    os_version: "NT 10.0"
                }
            }
        }

        const clientTokenRes = await fetch(SPOTIFY_CLIENT_TOKEN_URL, {
            method: "POST",
            body: JSON.stringify(data),
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            },
        })
        
        const clientTokenResponse: SpotifyClientTokenResponse = await clientTokenRes.json()
        if (clientTokenResponse.response_type == "RESPONSE_GRANTED_TOKEN_RESPONSE") {
            this.CLIENT_TOKEN = clientTokenResponse.granted_token.token
        }
    }

    
    async getLyrics(id: string) {
        // Wait for initialization to complete
        await this.initPromise
        
        const URL = `${SPOTIFY_LYRICS_BASE_URL}/${id}?format=json&vocalRemoval=false&market=from_token`

        console.log("Client Token:", this.CLIENT_TOKEN)
        console.log("Access Token:", this.ACCESS_TOKEN)
        
        const response = await fetch(URL, {
            // Necessary headers for Spotify Closed API response.
            // Seriously Spotify? You guys couldn't expose this?
            headers: {
                'App-Platform': 'WebPlayer',
                'Accept': 'application/json',
                'Authorization': `Bearer ${this.ACCESS_TOKEN}`,
                'Client-Token': this.CLIENT_TOKEN,
                'User-Agent': SPOTIFY_USER_AGENT,
                'Spotify-App-Version': SPOTIFY_APP_VERSION,
            },
        })
        
        const lyricsResponse = await response.json()
        console.log(lyricsResponse)
        return lyricsResponse
    }
}

export const spotifyProvider = new SpotifyProvider()