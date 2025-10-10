
# wisp

wisp is an Electron-based (yeah, I know) song player, with support for extractors from services such as Spotify and Youtube.


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
## Roadmap

Currently, wisp is missing a lot of features that I'm working on.

* Ability to sync playlists from services, even if they have custom songs



## FAQ

#### Why does this exist? Aren't there already services like Spotube?
I mean yeah, they do. I did this because for some reason, Spotube wasn't working (and I also didn't like the UI) 

#### Is this ready?
HELL NO. This doesn't even work in production right now (because of the use of the localhost/127.0.0.1 protocols). In the near future though, maybe.

## Acknowledgements
An enourmous thanks to all of the incredible people who have helped develop the following software:
* The [Spotify Web API TypeScript SDK](https://github.com/spotify/spotify-web-api-ts-sdk/)
* [YouTube.js](https://github.com/LuanRT/YouTube.js)
* The [Material UI Framework](https://github.com/mui/material-ui)
* [Electron](https://github.com/electron/electron)
## How to Run Locally

Clone the project

```bash
  git clone https://github.com/wizeshi/wisp.git
```

Go to the project directory

```bash
  cd wisp
```

Install dependencies

```bash
  npm install
```

Start the app

```bash
  npm run start
```


## License

[MIT](https://choosealicense.com/licenses/mit/)
