import { SidebarItemType, SidebarListType } from "../../common/types/SongTypes";

/**
 * Generic extractor base class
 * All methods throw errors by default - meant to be extended by specific extractors
 */
export class GenericExtractor {
    async search(searchTerms: string): Promise<unknown> {
        throw new Error(`Method 'search' not implemented: falling back to GenericExtractor`);
    }

    async isLoggedIn(): Promise<{ loggedIn: boolean; expired: boolean }> {
        throw new Error(`Method 'isLoggedIn' not implemented: falling back to GenericExtractor`);
    }

    async getUserInfo(): Promise<unknown> {
        throw new Error(`Method 'getUserInfo' not implemented: falling back to GenericExtractor`);
    }
    
    async getUserLists(type: SidebarListType): Promise<unknown> {
        throw new Error(`Method 'getUserLists' not implemented: falling back to GenericExtractor`);
    }
    
    async getUserDetails(id: string): Promise<unknown> {
        throw new Error(`Method 'getUserDetails' not implemented: falling back to GenericExtractor`);
    }
    
    async getListDetails(type: SidebarItemType, id: string): Promise<unknown> {
        throw new Error(`Method 'getListDetails' not implemented: falling back to GenericExtractor`);
    }
    
    async getArtistInfo(id: string): Promise<unknown> {
        throw new Error(`Method 'getArtistInfo' not implemented: falling back to GenericExtractor`);
    }
    
    async getArtistDetails(id: string): Promise<unknown> {
        throw new Error(`Method 'getArtistDetails' not implemented: falling back to GenericExtractor`);
    }
    
    async getUserHome(): Promise<unknown> {
        throw new Error(`Method 'getUserHome' not implemented: falling back to GenericExtractor`);
    }

    async getUserLikes(...args: unknown[]): Promise<unknown> {
        throw new Error(`Method 'getUserLikes' not implemented: falling back to GenericExtractor`);
    }
}

export const genericExtractor = new GenericExtractor()