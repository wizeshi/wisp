# wisp - The open, fast & unified music player

wisp is a Flutter-based music player, with (pretty much) modular support for multiple extractors from services such as Spotify and Youtube.

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

I'm also working on adding support for more services (e.g. Apple Music, Deezer, Tidal, Qobuz, etc) Check the [Roadmap](https://github.com/wizeshi/wisp/blob/main/docs/en/ROADMAP.md) for more info on that.
(P.S: if you want support for a service early, either offer me a subscription to it, or better yet, open a PR with an extractor for it :D)

## Installation

The app is currently distributed and maintained for Windows, Linux & Android (ARM64). If you want to know why, go to the FAQ below. 

Follow the [Installation Guide](https://github.com/wizeshi/wisp/blob/main/docs/en/INSTALLATION_GUIDE.md)

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
I mean yeah, they do. I did this because for some reason, apps like Spotube frequently don't work (and I just don't like their UI, sorry)

#### Is this ready?
Mostly. Right now, it's mostly missing (some) writing to spotify and source mixing (not finished as well). Everything else is on the Roadmap.

#### Why is this only avaliable on 3 platforms?
Well, they're the ones I have access to. I don't have a Mac, neither do I have an iPhone, so I can't develop for macOS or iOS. If you want to help me bring support to those (and other) platforms, create a PR with the features for them.

Further, as seen in the installation guide, complete Linux integration is somewhat limited (mostly due to Flutter packaging issues). See the guide for more info.

Even more, Android support is not limited to just ARM64, but you'll have a worse time in any other architecture. This is because the app embeds NodeJS, and I can only distribute the ARM64 version of it, since it's the only one I have access to. If you want to help out with that, create a PR with the other architectures' binaries and I'll add them to distribution.

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