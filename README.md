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

The app is currently distributed and maintained for Windows (x64), macOS (Apple Silicon), Linux (x64), Android (ARM64) & iOS.
Other architectures are either not tested yet, or fully unsupported.

To install the app, just grab a corresponding file from the "Releases" tab to the side!
If you are confused about what "x64" or "ARM" mean, don't worry. 
If you're on mobile or on a Mac (2021+), you're most likely on ARM64. Everyone else is probably on x64.

## Roadmap

Currently, wisp is missing a lot of features that I'm working on.
If you want to know what's coming or want to help out, check the list [here](https://github.com/wizeshi/wisp/blob/main/docs/en/ROADMAP.md)

## FAQ
#### What the hell does "wisp" mean?
It originally stood for "wizeshi's interfaceable song provider", since everything I develop must, for some reason, adhere to this naming scheme: 

1. Start with my username (narcissistic tendencies I guess); 
2. Be an acronym for something. 

So, that was the best I could do, but these days nothing on the app itself reflects the original name (since it has been reworked so many times). I'm actually thinking about better name ideas, but I can't seem to come up with anything else. 

#### Why does this exist? Aren't there already services like Spotube?
I mean yeah, they do. Though 1. they're not as cool and 2. they have very limited support. For example, Spotube is currently busy remaking their app in Kotlin Multiplatform due to architecture reasons, leaving the app essentially dead for the time being. 

#### Is this ready?
Mostly. Right now, it's mostly missing (some) writing to spotify and source mixing (not finished as well). Also crossfade has some weird kinks. Everything else is on the Roadmap.

## Acknowledgements
There's a lot of free software out there which I was inspired by or used as reference when developing wisp. Here's a couple of them:
YT-DLP, librespot, Spotube, Meld, NewPipeExtractor, YouTube.js

## Contributing

If you wanna contribute (no idea why), check [this](https://github.com/wizeshi/wisp/blob/main/docs/en/CONTRIBUTING.md) out

## License

The current version of wisp is licensed under the GPLv3 license, which makes it Free Software.
You may study, redistribute and modify the software, though you should not the official "wisp" branding and assets to avoid confusion. 
This may change at a later date, but it is not retroactive. For more information, see [LICENSE.md](LICENSE.md)