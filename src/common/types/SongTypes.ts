import { secondsToSecAndMin, secondsToSecMinHour } from "../../frontend/utils/Utils";
import { 
    SimplifiedAlbum as SpotifySimplifiedAlbum,
    TopTracksResult as SpotifyTopTracksResult,
    Artist as SpotifyArtist
} from "@spotify/web-api-ts-sdk";


export const SongSourcesList = ["local", "spotify", "youtube", "soundcloud"] as const
export type SongSources = typeof SongSourcesList[number]

/**
 * A generic media item
 * @variable id - The unique identifier for the item
 * @variable source - The source of the media item (e.g., Spotify, YouTube)
 */
export class GenericCommon {
    id: string
    source: SongSources

    constructor(id: string, source: SongSources) {
        this.id = id
        this.source = source
    }
}

/**
 * A user with basic information
 * @variable displayName - The user's display name
 * @variable avatarURL - The user's avatar image URL
 * @variable followerCount - The user's follower count
 * @variable profileURL - The user's profile URL
 */
export class GenericSimpleUser extends GenericCommon {
    displayName: string
    avatarURL?: string
    followerCount?: number
    profileURL?: string

    constructor(id: string, source: SongSources, displayName: string, avatarURL?: string, followerCount?: number, profileURL?: string) {
        super(id, source)
        this.displayName = displayName
        this.avatarURL = avatarURL
        this.followerCount = followerCount
        this.profileURL = profileURL
    }
}

/**
 * A user with additional information
 * @variable email - The user's email address
 * @variable country - The user's country of residence
*/
export class GenericUser extends GenericSimpleUser {
    email?: string
    country?: string

    constructor(id: string, source: SongSources, displayName: string, avatarURL?: string, followerCount?: number, profileURL?: string, email?: string, country?: string) {
        super(id, source, displayName, avatarURL, followerCount, profileURL)
        this.email = email
        this.country = country
    }
}

/**
 * An artist with basic information
 * @variable name - The name of the artist
 * @variable thumbnailURL - The URL of the artist's thumbnail image
 */
export class GenericSimpleArtist extends GenericCommon {
    name: string;
    thumbnailURL: string;

    constructor(id: string, source: SongSources, name: string, thumbnailURL: string) {
        super(id, source);
        this.name = name;
        this.thumbnailURL = thumbnailURL;
    }
}

/**
 * An artist with additional information (usually for artist profile pages)
 * @variable monthlyListeners - The artist's monthly listeners count
 * @variable topSongs - The artist's top songs
 */

export class GenericArtist extends GenericSimpleArtist {
    monthlyListeners: number;
    topSongs: GenericSong[];
    albums: GenericSimpleAlbum[];

    constructor(id: string, source: SongSources, name: string, thumbnailURL: string, monthlyListeners: number, topSongs: GenericSong[], albums: GenericSimpleAlbum[]) {
        super(id, source, name, thumbnailURL);
        this.monthlyListeners = monthlyListeners;
        this.topSongs = topSongs;
        this.albums = albums;
    }
}

/**
 * Just a song
 * @variable title - The title of the song
 * @variable artists - The artists of the song (simple artists, as to not create circular references)
 * @variable thumbnailURL - The thumbnail image URL of the song
 * @variable explicit - Whether the song is explicit
 * @variable album - The album the song belongs to (also simple to avoid circular references)
 * @variable durationSecs - The duration of the song in seconds
 */

export class GenericSong extends GenericCommon {
    title: string;
    artists: Array<GenericSimpleArtist>;
    thumbnailURL: string;
    explicit: boolean;
    album?: GenericSimpleAlbum;
    durationSecs: number;
    durationFormatted: string;

    constructor(title: string, artists: Array<GenericSimpleArtist>, explicit: boolean, duration: number, source: SongSources, id: string, thumbnailURL: string, album?: GenericSimpleAlbum) {
        super(id, source)
        this.title = title;
        this.artists = artists;
        this.source = source;
        this.thumbnailURL = thumbnailURL;
        this.explicit = explicit
        this.durationSecs = duration
        this.album = album;

        this.durationFormatted = secondsToSecAndMin(duration)
    }
}

/**
 * A base class for song lists (playlists, albums, etc.)
 */

export class GenericBaseSongList extends GenericCommon {
    title: string;
    songs: Array<GenericSong> | undefined;
    thumbnailURL: string;
    durationSecs: number;
    durationFormatted: string;
    total?: number; // Total number of items (for pagination)
    hasMore?: boolean; // Whether there are more items to load

    constructor(title: string, songs: Array<GenericSong> | undefined, thumbnailURL: string, id: string, source: SongSources) {
        super(id, source);
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

/** An album with basic information
 * @variable title - The title of the album
 * @variable thumbnailURL - The URL of the album's thumbnail image
 * @variable artists - The artists of the album (simple artists to avoid circular references)
 * @variable label - The record label of the album
 * @variable releaseDate - The release date of the album
 */

export class GenericSimpleAlbum extends GenericCommon {
    title: string;
    thumbnailURL: string;

    artists: Array<GenericSimpleArtist>;
    label: string;
    releaseDate: Date;
    
    constructor(id: string, source: SongSources, title: string, thumbnailURL: string, artists: GenericSimpleArtist[], releaseDate: Date, label: string) {
        super(id, source);
        this.title = title;
        this.thumbnailURL = thumbnailURL;
        this.artists = artists;
        this.releaseDate = releaseDate
        this.label = label
    }
}

/** An album with additional information
 * @variable title - The title of the album
 * @variable thumbnailURL - The URL of the album's thumbnail image
 * @variable artists - The artists of the album (simple artists to avoid circular references)
 * @variable label - The record label of the album
 * @variable releaseDate - The release date of the album
 * @variable explicit - Whether the album is explicit
 * @variable songs - The songs in the album
 */

export class GenericAlbum extends GenericBaseSongList {
    artists: Array<GenericSimpleArtist>;
    explicit: boolean;
    label: string;
    releaseDate: Date;

    constructor(title: string, artists: Array<GenericSimpleArtist>, label: string, releaseDate: Date, explicit: boolean, songs: Array<GenericSong> | undefined, thumbnailURL: string, id: string, source: SongSources) {
        super(title, songs, thumbnailURL, id, source);
        this.artists = artists;
        this.label = label
        this.explicit = explicit
        this.releaseDate = releaseDate
    }
}

export class PlaylistItem extends GenericSong {
    addedAt: Date;
    trackNumber: number;

    constructor(title: string, artists: Array<GenericSimpleArtist>, explicit: boolean, duration: number, source: SongSources, id: string, thumbnailURL: string, addedAt: Date, trackNumber: number, album?: GenericSimpleAlbum) {
        super(title, artists, explicit, duration, source, id, thumbnailURL, album);
        this.addedAt = addedAt;
        this.trackNumber = trackNumber;
    }
}

export class GenericPlaylist extends GenericBaseSongList {
    declare songs: Array<PlaylistItem>;
    author: GenericSimpleUser;

    constructor(title: string, author: GenericSimpleUser, songs: Array<PlaylistItem> | undefined, thumbnailURL: string, id: string, source: SongSources) {
        super(title, songs, thumbnailURL, id, source);
        this.author = author
    }
}

export const SidebarItemTypes = ["Playlist", "Album", "Artist"] as const
export type SidebarItemType = typeof SidebarItemTypes[number]

export type SidebarItem = {
    id: "Playlist",
    item: GenericPlaylist 
} | { 
    id: "Album",
    item: GenericAlbum
} | {
    id: "Artist",
    item: GenericArtist
}

export const SidebarListTypes = ["Playlists", "Albums", "Artists"] as const
export type SidebarListType = typeof SidebarListTypes[number]

export enum LoopingEnum {
    Off = 0,
    List = 1,
    Song = 2
}