
# wisp - A unified music player
# wisp - A unified music player

wisp is an Electron-based (yeah, I know) song player, with support for multiple extractors from services such as Spotify and Youtube.

## Features

* Familiar, easy to use UI
* Pretty decent performance
* Extractors from services such as:
    * Youtube (official API & Innertube, metadata & audio)
    * Spotify (official API, metadata)
* Song & Search caching (not implemented)
* Lyrics from the following services (also not implemented):
    * Musixmatch
    * Genius (unsynced)
    * NetEase
    * LrcLib
## Installation

Follow the [Installation Guide](https://github.com/wizeshi/wisp/blob/master/docs/INSTALLATION_GUIDE.md)
## Roadmap

Currently, wisp is missing a lot of features that I'm working on.

* Ability to sync playlists from services, even if they have custom songs



## FAQ

#### Why does this exist? Aren't there already services like Spotube?
I mean yeah, they do. I did this because for some reason, Spotube wasn't working (and I also didn't like the UI) 

#### Is this ready?
Kinda? Contrary to the last release, it should (?) work in production (every localhost-based url has been handled). But does it WORK though? No clue.

## Acknowledgements
An enourmous thanks to all of the incredible people who have helped develop the following software:
* The [Spotify Web API TypeScript SDK](https://github.com/spotify/spotify-web-api-ts-sdk/)
* [YouTube.js](https://github.com/LuanRT/YouTube.js)
* [YT-DLP](https://github.com/yt-dlp/yt-dlp) (these guys are awesome)
* [FFmpeg](https://github.com/FFmpeg/FFmpeg)
* The [Material UI Framework](https://github.com/mui/material-ui)
* [Electron](https://github.com/electron/electron)
## Contributing

If you wanna contribute (no idea why), check out [contributing.md](https://github.com/wizeshi/wisp/blob/master/docs/CONTRIBUTING.md)


## License

[MIT](https://github.com/wizeshi/wisp/blob/master/LICENSE)