import { secondsToSecAndMin, secondsToSecMinHour } from "../utils/Utils";

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
    artists: Array<Artist>;
    source: Sources;
    thumbnailURL: string;
    explicit: boolean;
    durationSecs: number;
    durationFormatted: string;

    constructor(title: string, artists: Array<Artist>, explicit: boolean, duration: number, source: Sources, thumbnailURL: string) {
        this.title = title;
        this.artists = artists;
        this.source = source;
        this.thumbnailURL = thumbnailURL;
        this.explicit = explicit
        this.durationSecs = duration

        this.durationFormatted = secondsToSecAndMin(duration)
    }
}

export class BaseSongList {
    id: string;
    title: string;
    songs: Array<Song> | undefined;
    thumbnailURL: string;
    durationSecs: number;
    durationFormatted: string;

    constructor(title: string, songs: Array<Song> | undefined, thumbnailURL: string, id: string) {
        this.id = id
        this.title = title;
        this.songs = songs;
        this.thumbnailURL = thumbnailURL;

        this.durationSecs = 0

        songs.forEach((song) => {
            this.durationSecs += song.durationSecs
        })

        this.durationFormatted = secondsToSecMinHour(this.durationSecs)
    }
}

export class Album extends BaseSongList {
    artists: Array<Artist>;
    explicit: boolean;
    label: string;
    releaseDate: Date;

    constructor(title: string, artists: Array<Artist>, label: string, releaseDate: Date, explicit: boolean, songs: Array<Song> | undefined, thumbnailURL: string, id: string) {
        super(title, songs, thumbnailURL, id);
        this.artists = artists;
        this.label = label
        this.explicit = explicit
        this.releaseDate = releaseDate
    }
}

export class Playlist extends BaseSongList {
    author: string;

    constructor(title: string, author: string, songs: Array<Song> | undefined, thumbnailURL: string, id: string) {
        super(title, songs, thumbnailURL, id);
        this.author = author
    }
}


export const SidebarItemTypes = ["Playlist", "Album", "Artist"] as const
export type SidebarItemType = typeof SidebarItemTypes[number]

export type SidebarItem = {
    id: "Playlist",
    item: Playlist 
} | { 
    id: "Album",
    item: Album
} | {
    id: "Artist",
    item: Artist
}

export type youtubeSongType = {
    etag: string,
    id: {
        kind: "youtube#video",
        videoId: string,
    },
    kind: "youtube#searchResult",
    snippet: youtubeSnippetType
}

export type youtubeSnippetType = {
    channelId: string,
    channelTitle: string,
    description: string,
    liveBroadcastContent: string,
    publishTime: string,
    publishedAt: string,
    thumbnails: {
        default: youtubeThumbnailType,
        high: youtubeThumbnailType,
        medium: youtubeThumbnailType,
    },
    title: string
}

export type youtubeThumbnailType = {
    height: number,
    url: string,
    width: number
}

export type youtubeSearchType = {
    etag: string,
    items: youtubeSongType[],
    kind: string,
    nextPageToken: string,
    pageInfo: {
        resultsPerPage: number,
        totalResults: number
    },
    regionCode: string
}

export const SidebarListTypes = ["Playlists", "Albums", "Artists"] as const
export type SidebarListType = typeof SidebarListTypes[number]

export enum LoopingEnum {
    Off = 0,
    List = 1,
    Song = 2
}