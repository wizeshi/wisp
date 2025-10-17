import { UserData } from "../../backend/utils/types";

class DataManager {
    private data: UserData | null = null
    private listeners: Set<(data: UserData) => void> = new Set()

    async load(): Promise<UserData> {
        this.data = await window.electronAPI.info.data.load()
        this.notifyListeners()
        return this.data
    }

    async save(newData: UserData): Promise<void> {
        await window.electronAPI.info.data.save(newData)
        this.data = newData
        this.notifyListeners()
    }

    async update(partial: Partial<UserData>) {
        const updated = { ...this.data, ...partial }
        await this.save(updated)
        return updated
    }

    getCached(): UserData | null {
        return this.data
    }

    subscribe(listener: (data: UserData) => void) {
        this.listeners.add(listener)
        return () => this.listeners.delete(listener)
    }

    private lastNotifiedData: UserData | null = null;
    private shallowEqual(objA: UserData, objB: UserData) {
        if (objA === objB) return true;
        if (!objA || !objB) return false;
        const keysA = Object.keys(objA);
        const keysB = Object.keys(objB);
        if (keysA.length !== keysB.length) return false;
        for (const key of keysA) {
            if (objA[key as keyof UserData] !== objB[key as keyof UserData]) return false;
        }
        return true;
    }

    private notifyListeners() {
        if (this.data && !this.shallowEqual(this.data, this.lastNotifiedData as UserData)) {
            this.listeners.forEach(listener => listener(this.data));
            this.lastNotifiedData = { ...this.data };
        }
    }
}

export const dataManager = new DataManager()