# wisp - The open, fast & unified music player

wisp is a Flutter-based music player, with modular support (coming soon) for multiple extractors from services such as Spotify and Youtube.

## Features

* Easy to use UI, with styles to ensure you feel right at home, no matter the service you're coming from. 
* Great, almost-native, performance
* Extractors from services such as:
    * Youtube (Innertube, metadata & audio)
    * Spotify (internal API, metadata, maybe audio in the future)
* Everything caching (support for audio, and metadata caches for everything, playlists, songs, you name it)
* Lyrics (synced & unsynced) from the following services:
    * Spotify
    * LrcLib
    * BetterLyrics

I'm also working on adding support for more services (e.g. Apple Music, Deezer, Tidal, Qobuz, etc) Check the [Roadmap](https://github.com/wizeshi/wisp/blob/main/docs/en/ROADMAP.md) for more info on that.
(P.S: if you want support for a service early, either offer me a subscription to it, or better yet, open a PR with an extractor for it :D)

## Installation

The app is currently distributed and maintained for Windows, MacOS (Apple Silicon), Linux, Android (ARM64) & iOS.

Installation is very simple. 
On desktop, grab the wisp_installer executable for your platform from the [installer repo releases](https://github.com/wizeshi/wisp_installer/releases/latest) and run it. It will guide you through the installation process.
On Android, grab the APK from the [installer repo releases](https://github.com/wizeshi/wisp_installer/releases/latest) and install it. You may need to allow installation from unknown sources in your settings.

## Roadmap

Currently, wisp is missing a lot of features that I'm working on.
If you want to know what's coming or want to help out, check the list [here](https://github.com/wizeshi/wisp/blob/main/docs/en/ROADMAP.md)

## FAQ
#### What the hell does "wisp" mean?
It originally stood for "wizeshi's interfaceable song provider", since everything I develop must, for some reason, adhere to this naming scheme: 

1. Start with my username (narcissistic tendencies I guess); 
2. Be an acronym for something. 

So, that was the best I could do, but these days nothing on the app itself reflects the original name (since it has been reworked so many times).

#### Why does this exist? Aren't there already services like Spotube?
I mean yeah, they do. Though 1. they're not as cool and 2. they have very limited support. For example, Spotube is currently busy remaking their app in Kotlin Multiplatform due to architecture reasons, leaving the app essentially dead for the time being. 

#### Is this ready?
Mostly. Right now, it's mostly missing (some) writing to spotify and source mixing (not finished as well). Also crossfade has some weird kinks. Everything else is on the Roadmap.

## Acknowledgements
Special thanks to all of the people who have contributed to the following projects:
* [Flutter](https://flutter.dev/) - Best cross-platform framework out there, and therefore the one I use for this project.
* [YT-DLP](https://github.com/yt-dlp/yt-dlp) - The best YouTube extractor CLI out there (could be better with native android support tho).
* [librespot](https://github.com/librespot-org/librespot) - The best FOSS Spotify client implementation. 
* [Spotube](https://github.com/KRTirtho/spotube) - The (other) best music player. These guys' work (and librespot's) has been a godsend for this project, since I was able to learn (and shamelessly copy) a lot of the internal workings of Spotify's API from them.
* [YoutubeExplodeDart](https://github.com/Hexer10/youtube_explode_dart) - Best YouTube metadata extractor.
* [just_audio](https://github.com/ryanheise/just_audio/) & [mpv](https://mpv.io/) - Incredible audio player interface, with even better performance. 

## Contributing

If you wanna contribute (no idea why), check out [contributing.md](https://github.com/wizeshi/wisp/blob/main/docs/en/CONTRIBUTING.md)

## License

This project is currently licensed under the [MIT License](https://github.com/wizeshi/wisp/blob/main/LICENSE) but, since the project is at an early stage, that may change in the future.
If I use your code in this project, and the license is not compatible, please let me know (or create an exception :D).