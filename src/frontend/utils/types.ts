import { secondsToSecAndMin, secondsToSecMinHour } from "./utils";

export type Sources = "spotify" | "youtube" | "soundcloud"

export class Artist {
    name: string;
    thumbnailURL: string;

    constructor(name: string, thumbnailURL: string) {
        this.name = name;
        this.thumbnailURL = thumbnailURL
    }
}

export class Song {
    title: string;
    artist: Artist;
    source: Sources;
    URL: string;
    thumbnailURL: string;
    explicit: boolean;
    durationSecs: number;
    durationFormatted: string;

    constructor(title: string, artist: Artist, explicit: boolean, duration: number, source: Sources, URL: string, thumbnailURL: string) {
        this.title = title;
        this.artist = artist;
        this.source = source;
        this.URL = URL;
        this.thumbnailURL = thumbnailURL;
        this.explicit = explicit
        this.durationSecs = duration

        this.durationFormatted = secondsToSecAndMin(duration)
    }
}

class BaseSongList {
    title: string;
    songs: Array<Song> | undefined;
    thumbnailURL: string;
    durationSecs: number;
    durationFormatted: string;

    constructor(title: string, songs: Array<Song> | undefined, thumbnailURL: string) {
        this.title = title;
        this.songs = songs;
        this.thumbnailURL = thumbnailURL;

        this.durationSecs = 0

        songs.forEach((song, index) => {
            this.durationSecs += song.durationSecs
        })

        this.durationFormatted = secondsToSecMinHour(this.durationSecs)
    }
}

export class Album extends BaseSongList {
    artist: Artist;
    explicit: boolean;
    label: string;

    constructor(title: string, artist: Artist, label: string, explicit: boolean, songs: Array<Song> | undefined, thumbnailURL: string) {
        super(title, songs, thumbnailURL);
        this.artist = artist
        this.label = label
        this.explicit = explicit
    }
}

export class Playlist extends BaseSongList {
    author: string;

    constructor(title: string, author: string, songs: Array<Song> | undefined, thumbnailURL: string) {
        super(title, songs, thumbnailURL);
        this.author = author
    }
}