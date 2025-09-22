export type Sources = "spotify" | "youtube" | "soundcloud"

export class Artist {
    type = "artist"; 
    name: string;
    thumbnailURL: string;

    constructor(name: string, thumbnailURL: string) {
        this.name = name;
        this.thumbnailURL = thumbnailURL
    }
}

export class Song {
    type = "song";
    title: string;
    artist: Artist;
    source: Sources;
    URL: string;
    thumbnailURL: string;

    constructor(title: string, artist: Artist, source: Sources, URL: string, thumbnailURL: string) {
        this.title = title;
        this.artist = artist;
        this.source = source;
        this.URL = URL;
        this.thumbnailURL = thumbnailURL;
    }
}

class BaseSongList {
    title: string;
    songs: Array<Song> | undefined;
    thumbnailURL: string;

    constructor(title: string, songs: Array<Song> | undefined, thumbnailURL: string) {
        this.title = title;
        this.songs = songs;
        this.thumbnailURL = thumbnailURL;
    }
}

export class Album extends BaseSongList {
    type = "album";
    artist: Artist;

    constructor(title: string, artist: Artist, songs: Array<Song> | undefined, thumbnailURL: string) {
        super(title, songs, thumbnailURL);
        this.artist = artist
    }
}

export class Playlist extends BaseSongList {
    type = "playlist";
    author: string;

    constructor(title: string, author: string, songs: Array<Song> | undefined, thumbnailURL: string) {
        super(title, songs, thumbnailURL);
        this.author = author
    }
}