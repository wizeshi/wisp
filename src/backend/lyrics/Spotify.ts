import { TOTP } from "totp-generator"
import { loadCredentials } from "../Credentials"
import { GenericLyrics, GenericLyricsLine } from "../../common/types/LyricsTypes"

const SPOTIFY_WEB_TOKEN_URL = 'https://open.spotify.com/api/token'
const SPOTIFY_CLIENT_TOKEN_URL = 'https://clienttoken.spotify.com/v1/clienttoken'
const SPOTIFY_LYRICS_BASE_URL = 'https://spclient.wg.spotify.com/color-lyrics/v2/track'
const SPOTIFY_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

// Hats off to this guy for hosting the secrets file :)
const SECRETS_URL = 'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json'

const SPOTIFY_APP_VERSION = "1.2.75.277.g5c44d208"

type SpotifyLyrics = {
    lyrics: {
        syncType: 'LINE_SYNCED' | 'LINE_UNSYNCED',
        lines: SpotifyLyricsLine[],
        provider: 'MusixMatch',
        providerLyricsId: number,
        providerDisplayName: 'Musixmatch',
        syncLyricsUri: string,
        isDenseTypeface: boolean,
        alternatives: [],
        langauge: string,
        isRtlLanguage: boolean,
        capStatus: string,
        previewLines: []
    },
    colors: {
        background: number,
        text: number,
        highlightText: number,
    },
    hasVocalRemoval: false
}

type SpotifyLyricsLine = {
    startTimeMs: string,
    words: string,
    syllables: [],
    endTimeMs: string,
    transliteratedWords: string
}

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

/* 
Credits to the guys at this discussion: https://github.com/librespot-org/librespot/discussions/1562
for helping figure out how spotify's TOTP generation works.
Also thanks to the guys at https://github.com/KRTirtho/spotube for actually implementing it in their code,
since I mostly just adapted it from there :P
*/

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

/**
 * Spotify lyrics provider using Spotify's internal (mostly undocumented) API.
 */
class SpotifyProvider {
    private initPromise: Promise<void>
    private CLIENT_TOKEN: string
    private ACCESS_TOKEN: string

    constructor() {
        this.initPromise = this.initialize()
    }

    // Initialize the provider by fetching necessary tokens.
    // I swear, spotify is so fucking annoying with this, jesus christ.
    // Like, why can't you just have a public lyrics API, Spotify?
    // This will most likely break in the future, but whatever, what can you do.
    private async initialize() {
        const {totp, version} = await generateTotp()
        const cookie = (await loadCredentials()).spotifyCookie
        if (!cookie) throw new Error("Spotify cookie not found in credentials.")

        const ACCESS_TOKEN_URL = `${SPOTIFY_WEB_TOKEN_URL}?reason=init&productType=web-player&totp=${totp}&totpServer=${totp}&totpVer=${version}`

        // Use user's provided spotify to generate a valid access token. 

        const res = await fetch(ACCESS_TOKEN_URL, {
            headers: {
                'Cookie': cookie,
                'User-Agent': SPOTIFY_USER_AGENT
            }
        })
        
        const accessTokenResponse: SpotifyAccessTokenResponse = await res.json()
        this.ACCESS_TOKEN = accessTokenResponse.accessToken

        // Generate random device ID (32-character hex string), so the user stays anonymous.
        // This is probably not necessary, but eh, why not.
        // Also, spotify seems to only accept lowercase hex characters, so we do that too.
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

        // Fetch client token, which is required for the lyrics API.
        // Should last for a long time, so we only fetch it once during initialization.
        // Also, fetch a new one every time we initialize the provider (AKA when the app starts).
        // Spotify really loves their tokens, huh.
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

    // Thank GOD, we can now finally fetch the lyrics.
    async getLyrics(id: string): Promise<GenericLyrics | null> {
        // Wait for initialization to complete
        await this.initPromise
        
        const URL = `${SPOTIFY_LYRICS_BASE_URL}/${id}?format=json&vocalRemoval=false&market=from_token`

        console.log("Client Token:", this.CLIENT_TOKEN)
        console.log("Access Token:", this.ACCESS_TOKEN)
        
        const response = await fetch(URL, {
            // Necessary headers for Spotify Closed API response.
            // Seriously Spotify? You guys couldn't expose this?
            // Holy, these guys are something else.
            headers: {
                'App-Platform': 'WebPlayer',
                'Accept': 'application/json',
                'Authorization': `Bearer ${this.ACCESS_TOKEN}`,
                'Client-Token': this.CLIENT_TOKEN,
                'User-Agent': SPOTIFY_USER_AGENT,
                'Spotify-App-Version': SPOTIFY_APP_VERSION,
            },
        })

        try {
            if (response.ok) {
                const lyricsResponse = (await response.json()) as SpotifyLyrics
                const synced = lyricsResponse.lyrics.syncType == "LINE_SYNCED" ? true : false
                const lines: GenericLyricsLine[] = lyricsResponse.lyrics.lines.map((line) => {
                    return {
                        content: line.words,
                        startTimeMs: line.startTimeMs
                    }
                })
                const properLyrics: GenericLyrics = {
                    provider: "spotify",
                    synced: synced,
                    lines: lines
                }

                return properLyrics
            } else if (response.status === 404) {
                console.log("No lyrics found for this track on Spotify.")
                return null
            } else {
                console.error("Error fetching lyrics from Spotify:", response.status, response.statusText)
                return null
            }
        } catch (e) {
            console.log(e)
        }
    }
}

export const spotifyProvider = new SpotifyProvider()