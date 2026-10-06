# wisp - The open, fast & unified music player

wisp is a Flutter-based music player, with modular support (coming soon) for multiple extractors from services such as Spotify and Youtube.

## Features

* Easy to use UI, with styles to ensure you feel right at home, no matter the service you're coming from. 
* Great, almost-native, performance
* Multiple self-updating YouTube audio extractors.
* Modular provider support. Currently, you can build providers using JS for Authentication, and Lyrics and Metadata extraction. These here are official and have direct developer support:
    * Spotify - Auth, Lyrics, Metadata
    * SpicyLyrics - Auth, Lyrics
    * LRCLib - Lyrics
    * BetterLyrics - Lyrics
* Cache support for everything, guaranteeing full offline support.

If you want support for any other providers, you can add them yourself, or ask nicely!

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
Kind of. You can already use it fully in terms of reading, but writing support is iffy at best. There's still some kinks to iron out. Check the [Roadmap](https://github.com/wizeshi/wisp/blob/main/docs/en/ROADMAP.md)

## Acknowledgements
There's a lot of free software out there which I was inspired by or used as reference when developing wisp. Here's a couple of them:
YT-DLP, librespot, Spotube, Meld, NewPipeExtractor, YouTube.js

## Contributing

Want to make your own provider? Check out the spec [here](https://github.com/wizeshi/wisp/blob/main/providers/README.md)

If you wanna to the app itself, check [this](https://github.com/wizeshi/wisp/blob/main/docs/en/CONTRIBUTING.md) out

## License

The current version of wisp is licensed under the GPLv3 license, which makes it Free Software.
You may study, redistribute and modify the software, though you should not the official "wisp" branding and assets to avoid confusion. 
This may change at a later date, but it is not retroactive. For more information, see [LICENSE.md](LICENSE.md)