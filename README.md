# wisp - A unified music player

wisp is a Flutter-based song player, with (pretty much) modular support for multiple extractors from services such as Spotify and Youtube.

## Features

* Familiar, easy to use UI
* Great, almost-native, performance
* Extractors from services such as:
    * Youtube (Innertube, metadata (WIP) & audio)
    * Spotify (official API, metadata)
* Song & Search caching
* Lyrics (synced & unsynced) from the following services:
    * Spotify (unofficial, removed temporarily)
    * LrcLib

## Installation

The app is currently distributed and maintained for Windows, Linux & Android. If you want to know why, go to the FAQ below. 

Follow the [Installation Guide](https://github.com/wizeshi/wisp/blob/main/docs/en/INSTALLATION_GUIDE.md)

## Roadmap

Currently, wisp is missing a lot of features that I'm working on.

Here's the TODO list (24/50)
- Bugs:
    - [x] Can't change volume when playback is paused
    - [x] Fix clicking on "Go to X" switching the displayed sidebar type to X
    - [x] Player bar marquee leaves out the last character
    - [x] Fix right click menu position 
    - [x] The app remembers which song played last, but can't play it (since it doesn't fetch the stream URL of the current song on startup).
    - [x] Fix cache manager retries sometimes crashing the app
    - [x] Play/pause button in list view song row only appears for a split second after hovering (only when player is playing though). 
    - [x] Fix skipping buttons, they sometimes do not work
    - [x] Fix icons in mobile (media control icon is just a white circle now)
- Future changes:
    - [x] Change print statements to a logging framework
    - [x] Adjust player bar loading spinner size
    - [x] Wire up titlebar navigation buttons (back & forward)
    - [x] Wire up buttons in List & Artist views (desktop)
    - [x] Make volume button clickable (to mute)
    - [x] Remove three dot menu from desktop
    - [x] Make the download circle in each song be dynamically updated as the song is downloaded 
    - [x] When a song is playing, its name where it is shown (home screen, artist & list views, etc..., except in the player bar & full player) should be in the app's main color.
    - [x] Remove double headers (e.g. settings has two.)
    - [x] Remove button redundencies (e.g. in the list view, download button shows both as its standalone button and in the three dots menu)
    - [x] Remove/change code deemed so by the Flutter linter
    - [x] Change lyrics' empty lines to a music icon (🎶)
    - [x] Make song, artist, playlist and album names be clickable on desktop (e.g. song and artist should be clickable on the playerbar (song should go to the song's album), artist should be clickable under all other song instances, album should be clickable on the list view, etc... also, they should be right-clickable)
    - [ ] Add audio service support for windows (audio_service_win)
- Planned features: 
    - [x] Player preferences (whether it was looping, shuffled, volume), should last between restarts
    - [x] Add metadata caching
        - [x] All metadata related to something (e.g. for a song: song info, artist info, album info) should be fetched the first time the song plays, except if it already had been fetched before
        - [x] This metadata should have an expiration timestamp
        - [x] When using the metadata (e.g. artist info) in context where it is the main content (e.g. artist info page), re-fetch it every time (load the cached metadata first, ask spotify for new metadata, then dynamically update what is different after the new one comes)
        - [x] When using the metadata (e.g. artist info) in context where it is NOT the main content (e.g. home screen), should only re-fetch it if the expiration timestamp is smaller than the current timestamp (which means it has expired. should still show the old metadata while getting the new though)
        - [x] This allows for true offline playback (since it allows us to view playlists offline)
    - [x] Add an option in the context menu to change a song's cached youtube video ID (for use when the songs don't match), should open a dialog with a text box.
    - [x] Make right-click context menu compatible with playlists, albums & artists. Should work even in the sidebar. Should also have option to download it's metadata.
    - [x] Add a right-side sidebar (desktop, for now playing info, artist info, queue info, also to have lyrics preview on desktop)
    - [x] Add auto token refreshing
    - [x] Add non-native desktop notifications as a ~~collapsable snackbar area~~ notification icon on the ~~top right of the screen~~ titlebar
    - [x] Add artist info to the full player (mobile)
    - [x] Add main song cover color as a semi-transparent top to bottom fading background on the full screen player (mobile)
    - [x] Add shuffling & looping to the media session controls
    - [x] Add a single lyrics line in between the song cover and the title in the full player (mobile) 
    - [x] Add lyrics caching
    - [x] Add Discord RPC support (the "Listening to" messages and whatever)
    - [x] Add playlist folders (unfortunately unable to sync with spotify :/)
    - [x] Add ability to like songs, and see the Liked Songs playlist in the playlists tab. 
    - [x] Add YouTube metadata sourcing (only searching for tracks, since youtube doesn't label things as albums and whatever)
    - [x] Add playlist source mixing:
        - [x] Add playlist creation, deletion and renaming
        - [x] Add ability to add songs to playlists
        - [x] Add ability save mixed playlists to a provider, but only save that provider's tracks (e.g. in a PL with both YT & Spotify, if the provider is Spotify, only save Spotify songs on Spotify)
        - [x] Add ability to sync and detach from the original provider (trying to keep songs intact)
    - [ ] Add the Connect capability (being able to control devices remotely, probably with bluetooth/nearby devices for now)
    - [ ] Add a fullscreen player (desktop)
    - [ ] Add minimizing to the tray area (desktop)


## FAQ

#### What the hell does "wisp" mean?
It originally stood for "wizeshi's interfaceable song provider", since everything I develop must, for some reason, adhere to this naming scheme: 

1. Start with my username (narcissistic tendencies I guess); 
2. Be an acronym for something. 

So, that was the best I could do, but these days nothing on the app itself reflects the original name (since it has been reworked so many times).

#### Why does this exist? Aren't there already services like Spotube?
I mean yeah, they do. I did this because for some reason, apps like Spotube frequently don't work (and I also usually don't like the UI)

#### Is this ready?
Mostly. Right now, it's mostly missing writing to spotify, source mixing and controlling playback from other devices.

#### Why is this only avaliable on 3 platforms?
Well, they're the ones I have access to. I don't have a Mac, neither do I have an iPhone, so I can't developer for macOS or iOS. If you want to help me bring support to those (and other) platforms, create a PR with the features for them.

## Acknowledgements
An enourmous thank you to all of the incredible people who have contributed to the development of the following software:
* [Flutter](https://flutter.dev/)
* [YT-DLP](https://github.com/yt-dlp/yt-dlp) (these guys are awesome)
* [YoutubeExplodeDart](https://github.com/Hexer10/youtube_explode_dart)
* [just_audio](https://github.com/ryanheise/just_audio/) & [mpv](https://mpv.io/)
* [audio_service](https://github.com/ryanheise/audio_service/issues)

## Contributing

If you wanna contribute (no idea why), check out [contributing.md](https://github.com/wizeshi/wisp/blob/main/docs/en/CONTRIBUTING.md)

## License

This project is currently licensed under the [MIT License](https://github.com/wizeshi/wisp/blob/main/LICENSE)