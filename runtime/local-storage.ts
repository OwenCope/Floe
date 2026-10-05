// An extension's LocalStorage: one JSON file in its support folder, shared by every process of the extension.
import fs from "node:fs";

type Items = Record<string, any>;

/// The file operations, replaceable so a test can count them or make one fail.
export const storagePersistence = {
    read(file: string): string {
        return fs.readFileSync(file, "utf8");
    },
    /// Written beside the file and renamed over it, so a kill mid-write keeps the previous complete file.
    /// The name carries the pid: two processes of one extension must not share a temporary file.
    write(file: string, content: string) {
        const temporary = `${file}.${process.pid}.tmp`;
        fs.writeFileSync(temporary, content);
        fs.renameSync(temporary, file);
    },
    /// What tells an unchanged file from a changed one without reading it.
    stamp(file: string): string | undefined {
        try {
            const info = fs.statSync(file);
            return `${info.mtimeMs}:${info.size}:${info.ino}`;
        } catch {
            return undefined;
        }
    },
    keepAside(file: string) {
        fs.renameSync(file, `${file}.unreadable-${Date.now()}`);
    },
};

export function createLocalStorage(file: () => string) {
    let known: { file: string; stamp: string | undefined; items: Items } | undefined;

    /// The items on disk. Reread only when the file changed, which another process of the extension may have done.
    function load(): Items {
        const path = file();
        const stamp = storagePersistence.stamp(path);
        if (known?.file === path && known.stamp === stamp) return known.items;
        let items: Items = {};
        if (stamp !== undefined) {
            try {
                const parsed = JSON.parse(storagePersistence.read(path));
                if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
                items = parsed;
            } catch {
                // A file that cannot be read is moved aside, not overwritten: it may be all of someone's saved data.
                try {
                    storagePersistence.keepAside(path);
                } catch {}
                known = { file: path, stamp: undefined, items: {} };
                return known.items;
            }
        }
        known = { file: path, stamp, items };
        return items;
    }

    function save(items: Items) {
        const path = file();
        storagePersistence.write(path, JSON.stringify(items));
        known = { file: path, stamp: storagePersistence.stamp(path), items };
    }

    /// Runs a write inside a promise, so one that fails rejects and a caller's catch() sees it.
    function writing(work: () => void): Promise<void> {
        return new Promise((resolve) => {
            work();
            resolve();
        });
    }

    return {
        getItem<T = string>(key: string): Promise<T | undefined> {
            return Promise.resolve(load()[key] as T | undefined);
        },
        setItem(key: string, value: unknown): Promise<void> {
            return writing(() => save({ ...load(), [key]: value }));
        },
        removeItem(key: string): Promise<void> {
            return writing(() => {
                const items = load();
                if (!(key in items)) return;
                const rest = { ...items };
                delete rest[key];
                save(rest);
            });
        },
        allItems<T = Items>(): Promise<T> {
            // A copy: what the caller does to it must not reach the next read.
            return Promise.resolve({ ...load() } as T);
        },
        clear(): Promise<void> {
            return writing(() => save({}));
        },
    };
}
