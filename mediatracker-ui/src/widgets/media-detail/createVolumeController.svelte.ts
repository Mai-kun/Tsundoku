import { i18n } from "$shared/i18n/index.svelte";
import { addVolume, deleteVolume, setVolumeProgress, updateVolume } from "$shared/api/api";
import { MEDIA_STATUS, type MangaVolume } from "$shared/types";

export interface VolumeControllerOptions {
    /** The manga detail being edited; mutations are applied optimistically to it. */
    getMedia: () => MangaDetailLike | null;
    /** Re-reads the detail from the server after a structural change (add/delete). */
    reload: () => Promise<void>;
    /** Lets the parent refresh the library after a successful mutation. */
    onUpdate: () => void;
}

type MangaDetailLike = {
    id: string;
    type: string;
    totalVolumes?: number | null;
    volumes?: MangaVolume[];
};

/** Chapters are the granular unit when present; otherwise the volume tracks pages. */
function usesChapters(vol: MangaVolume): boolean {
    return vol.totalChapters > 0;
}

export function volumeCurrent(vol: MangaVolume): number {
    return usesChapters(vol) ? vol.currentChapter : vol.currentPage;
}

export function volumeTotal(vol: MangaVolume): number {
    if (usesChapters(vol)) return vol.totalChapters;
    return vol.totalPages > 0 ? vol.totalPages : 200;
}

export function volumePercent(vol: MangaVolume): number {
    const total = volumeTotal(vol);
    return total > 0 ? Math.min((volumeCurrent(vol) / total) * 100, 100) : 0;
}

export function isVolumeDone(vol: MangaVolume): boolean {
    const total = volumeTotal(vol);
    return (
        vol.status === MEDIA_STATUS.completed ||
        (total > 0 && volumeCurrent(vol) >= total)
    );
}

export function volumeProgressLabel(vol: MangaVolume): string {
    if (usesChapters(vol)) {
        return i18n.t.card.chapters(vol.currentChapter, vol.totalChapters);
    }
    return `${vol.currentPage} / ${vol.totalPages > 0 ? vol.totalPages : 200} pp.`;
}

/**
 * The shape the controller exposes. Derived from the factory itself so a new action cannot be
 * added to the implementation without the type the UI components consume noticing.
 */
export type VolumeController = ReturnType<typeof createVolumeController>;

/**
 * All volume mutations: optimistic write, one API call, rollback on failure.
 *
 * The stepper, "mark read" and "unmark read" buttons used to be three near-identical
 * functions that each re-derived the chapter/page branch and re-wrote the busy flag.
 */
export function createVolumeController({
    getMedia,
    reload,
    onUpdate,
}: VolumeControllerOptions) {
    let busy = $state("");
    let error = $state<unknown>(null);

    let addDialogOpen = $state(false);
    let addTitle = $state("");
    let addChapters = $state(0);

    let editDialogOpen = $state(false);
    let editing = $state<MangaVolume | null>(null);
    let editTitle = $state("");
    let editPages = $state(200);
    let editChapters = $state(0);
    let editCurrentPage = $state(0);
    let editCurrentChapter = $state(0);

    /**
     * Applies a target counter value to a volume and persists it, deriving the status
     * from the new counter so the three callers cannot disagree about it.
     */
    async function commit(
        vol: MangaVolume,
        value: number,
        status: MangaVolume["status"],
    ): Promise<void> {
        if (usesChapters(vol)) {
            vol.currentChapter = value;
        } else {
            vol.currentPage = value;
        }
        vol.status = status;

        try {
            busy = vol.id;
            await setVolumeProgress(
                vol.id,
                usesChapters(vol)
                    ? { currentChapter: value }
                    : { currentPage: value },
            );
            onUpdate();
        } catch (err) {
            error = err;
        } finally {
            busy = "";
        }
    }

    async function stepVolume(vol: MangaVolume, delta: number): Promise<void> {
        if (!getMedia()) return;
        const total = volumeTotal(vol);
        const current = volumeCurrent(vol);
        const next = Math.max(
            0,
            total > 0 ? Math.min(current + delta, total) : current + delta,
        );
        if (next === current) return;

        const status =
            total > 0 && next >= total
                ? MEDIA_STATUS.completed
                : next > 0
                  ? MEDIA_STATUS.inProgress
                  : MEDIA_STATUS.planned;
        await commit(vol, next, status);
    }

    async function markComplete(vol: MangaVolume): Promise<void> {
        if (!getMedia()) return;
        const total = volumeTotal(vol);
        if (!total) return;
        await commit(vol, total, MEDIA_STATUS.completed);
    }

    async function unmarkComplete(vol: MangaVolume): Promise<void> {
        if (!getMedia()) return;
        await commit(vol, 0, MEDIA_STATUS.planned);
    }

    function openAdd(): void {
        const media = getMedia();
        if (!media || media.type !== "manga") return;
        addTitle = `Volume ${(media.volumes?.length ?? 0) + 1}`;
        addChapters = 0;
        addDialogOpen = true;
    }

    async function confirmAdd(): Promise<void> {
        const media = getMedia();
        if (!media || media.type !== "manga") return;
        const volNum = (media.volumes?.length ?? 0) + 1;
        addDialogOpen = false;
        try {
            busy = "add";
            await addVolume(media.id, {
                volumeNumber: volNum,
                title: addTitle || `Volume ${volNum}`,
                totalPages: 200,
                totalChapters: addChapters,
                currentPage: 0,
                currentChapter: 0,
            });
            await reload();
            onUpdate();
        } catch (err) {
            error = err;
        } finally {
            busy = "";
        }
    }

    /** Fills in the remaining volumes the metadata says exist but the library lacks. */
    async function generateMissing(): Promise<void> {
        const media = getMedia();
        if (!media || media.type !== "manga" || !media.totalVolumes) return;
        try {
            busy = "generate";
            const start = (media.volumes?.length ?? 0) + 1;
            const promises = [];
            for (let i = start; i <= media.totalVolumes; i++) {
                promises.push(
                    addVolume(media.id, {
                        volumeNumber: i,
                        title: `Volume ${i}`,
                        totalPages: 200,
                        totalChapters: 0,
                        currentPage: 0,
                        currentChapter: 0,
                    }),
                );
            }
            await Promise.all(promises);
            await reload();
            onUpdate();
        } catch (err) {
            error = err;
        } finally {
            busy = "";
        }
    }

    function openEdit(vol: MangaVolume): void {
        editing = vol;
        editTitle = vol.title || `Volume ${vol.volumeNumber}`;
        editPages = vol.totalPages > 0 ? vol.totalPages : 200;
        editChapters = vol.totalChapters ?? 0;
        editCurrentPage = vol.currentPage ?? 0;
        editCurrentChapter = vol.currentChapter ?? 0;
        editDialogOpen = true;
    }

    async function confirmEdit(): Promise<void> {
        const vol = editing;
        if (!vol || !getMedia()) return;
        editDialogOpen = false;

        const previous = {
            title: vol.title,
            totalPages: vol.totalPages,
            totalChapters: vol.totalChapters,
            currentPage: vol.currentPage,
            currentChapter: vol.currentChapter,
        };

        vol.title = editTitle;
        vol.totalPages = Math.max(editPages, 1);
        vol.totalChapters = Math.max(editChapters, 0);
        vol.currentPage = Math.min(Math.max(editCurrentPage, 0), editPages);
        vol.currentChapter = Math.min(
            Math.max(editCurrentChapter, 0),
            vol.totalChapters > 0 ? vol.totalChapters : 999999,
        );

        try {
            busy = vol.id;
            await updateVolume(vol.id, {
                title: vol.title,
                totalPages: vol.totalPages,
                totalChapters: vol.totalChapters,
                currentPage: vol.currentPage,
                currentChapter: vol.currentChapter,
            });
            onUpdate();
        } catch (err) {
            Object.assign(vol, previous);
            error = err;
        } finally {
            busy = "";
            editing = null;
        }
    }

    async function remove(vol: MangaVolume): Promise<void> {
        const media = getMedia();
        if (!media) return;
        const volName = vol.title || `Volume ${vol.volumeNumber}`;
        if (!confirm(`Delete ${volName}?`)) return;

        // The entry leaves the cached detail before the call, so a failure has to put
        // the whole list back rather than only the one volume.
        const prevVolumes = [...(media.volumes ?? [])];
        media.volumes = prevVolumes.filter((v) => v.id !== vol.id);
        try {
            busy = vol.id;
            await deleteVolume(vol.id);
            onUpdate();
        } catch (err) {
            media.volumes = prevVolumes;
            error = err;
        } finally {
            busy = "";
        }
    }

    return {
        get busy() {
            return busy;
        },
        get error() {
            return error;
        },
        get addDialogOpen() {
            return addDialogOpen;
        },
        get addTitle() {
            return addTitle;
        },
        set addTitle(value: string) {
            addTitle = value;
        },
        get addChapters() {
            return addChapters;
        },
        set addChapters(value: number) {
            addChapters = value;
        },
        get editDialogOpen() {
            return editDialogOpen;
        },
        get editTitle() {
            return editTitle;
        },
        set editTitle(value: string) {
            editTitle = value;
        },
        get editPages() {
            return editPages;
        },
        set editPages(value: number) {
            editPages = value;
        },
        get editChapters() {
            return editChapters;
        },
        set editChapters(value: number) {
            editChapters = value;
        },
        get editCurrentPage() {
            return editCurrentPage;
        },
        set editCurrentPage(value: number) {
            editCurrentPage = value;
        },
        get editCurrentChapter() {
            return editCurrentChapter;
        },
        set editCurrentChapter(value: number) {
            editCurrentChapter = value;
        },
        closeAdd: () => (addDialogOpen = false),
        closeEdit: () => (editDialogOpen = false),
        stepVolume,
        markComplete,
        unmarkComplete,
        openAdd,
        confirmAdd,
        generateMissing,
        openEdit,
        confirmEdit,
        remove,
    };
}