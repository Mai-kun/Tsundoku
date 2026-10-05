<script lang="ts">
    import { X } from "$shared/ui/Icons.svelte";
    import { createMedia, errorMessage, updateMedia } from "$shared/api/api";
    import { isValidCoverUrl } from "$entities/media/model/coverUrl";
    import Modal from "$shared/ui/Modal.svelte";
    import BookFormFields from "./BookFormFields.svelte";
    import GameFormFields from "./GameFormFields.svelte";
    import MangaFormFields from "./MangaFormFields.svelte";
    import MovieFormFields from "./MovieFormFields.svelte";
    import TvShowFormFields from "./TvShowFormFields.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { SeasonDraft } from "./TvShowFormFields.svelte";
    import { loadMediaDetail } from "$features/prefetch-details/mediaDetailPrefetch";
    import {
        MEDIA_STATUS,
        type CreateMediaPayload,
        type CreateSeasonPayload,
        type MediaDetail,
        type MediaItem,
        type MediaStatus,
        type MediaType,
        type UpdateMediaPayload,
    } from "$shared/types";

    type CreateType = MediaType;

    interface Props {
        isOpen: boolean;
        onClose: () => void;
        onCreated: (media: MediaItem) => void;
        editingItem?: MediaItem;
    }

    let { isOpen, onClose, onCreated, editingItem }: Props = $props();

    const types: CreateType[] = ["game", "movie", "tvshow", "book", "manga"];

    let type = $state<CreateType>("game");
    let title = $state("");
    let coverUrl = $state("");
    let notes = $state("");
    let platform = $state("");
    let hoursPlayed = $state("");
    let author = $state("");
    let totalPages = $state("");
    let totalChapters = $state("");
    let currentVolume = $state("");
    let durationMinutes = $state("");
    let isAnime = $state(false);
    let studio = $state("");
    let network = $state("");
    let seasons = $state<SeasonDraft[]>([]);
    let submitting = $state(false);
    let submitError = $state<unknown>(null);
    let validationError = $state("");
    let score = $state("");
    let startedAt = $state("");
    let finishedAt = $state("");
    let status = $state<MediaStatus>(MEDIA_STATUS.planned);
    let editingInitialized = $state(false);
    let titleInput = $state<HTMLInputElement | null>(null);

    /**
     * Notes are a detail-only field: the list the grid holds does not carry them, so prefilling from
     * `editingItem` alone always produced an empty textarea and a save silently re-submitted that
     * empty value. The detail is fetched (from the prefetch cache when warm) so the field shows the
     * stored text and can actually be edited or cleared.
     */
    $effect(() => {
        if (!isOpen || !editingItem || editingInitialized) return;

        applyEditableFields(editingItem);
        editingInitialized = true;

        const id = editingItem.id;
        void loadMediaDetail(id)
            .then((detail) => {
                if (!isOpen || editingItem?.id !== id) return;
                applyEditableFields(detail);
            })
            .catch(() => {});
    });

    $effect(() => {
        if (isOpen) titleInput?.focus();
    });

    function applyEditableFields(item: MediaItem | MediaDetail) {
        type = item.type;
        title = item.title;
        coverUrl = item.coverUrl ?? "";
        notes = "notes" in item ? (item.notes ?? "") : "";
        score = item.score?.toString() ?? "";
        startedAt = item.startedAt?.slice(0, 16) ?? "";
        finishedAt = item.finishedAt?.slice(0, 16) ?? "";
        status = item.status;

        // The type-specific fields live on the same state, so they have to be reset on every apply:
        // switching an edited row from a game to a book would otherwise keep the game's platform.
        platform = "";
        hoursPlayed = "";
        author = "";
        totalPages = "";
        totalChapters = "";
        currentVolume = "";
        durationMinutes = "";
        isAnime = false;
        studio = "";
        network = "";
        seasons = [];

        if (item.type === "game") {
            platform = item.platform ?? "";
            hoursPlayed = item.hoursPlayed?.toString() ?? "";
        } else if (item.type === "book") {
            author = item.author ?? "";
            totalPages = item.totalPages?.toString() ?? "";
        } else if (item.type === "manga") {
            author = item.author ?? "";
            totalChapters = item.totalChapters?.toString() ?? "";
            currentVolume = item.currentVolume?.toString() ?? "";
            // The manga form reuses totalPages as the volume count, so it has to read totalVolumes.
            totalPages = item.totalVolumes?.toString() ?? "";
        } else if (item.type === "movie") {
            durationMinutes = item.durationMinutes?.toString() ?? "";
            isAnime = item.isAnime ?? false;
            studio = item.studio ?? "";
        } else if (item.type === "tvshow") {
            isAnime = item.isAnime ?? false;
            studio = item.studio ?? "";
            network = item.network ?? "";
            // Seasons ride on the detail payload only; the library row the form opens with has none.
            seasons = ("seasons" in item ? item.seasons ?? [] : []).map(
                (season) => ({
                    seasonNumber: season.seasonNumber?.toString() ?? "",
                    title: season.title ?? "",
                    totalEpisodes: season.totalEpisodes?.toString() ?? "",
                }),
            );
        }
    }

    function numberOrNull(value: string): number | null {
        const parsed = Number(value);
        return value.trim() !== "" && Number.isFinite(parsed) ? parsed : null;
    }

    function optionalText(value: string): string | null {
        return value.trim() || null;
    }

    function buildSeasons(): CreateSeasonPayload[] {
        return seasons
            .filter(
                (season) => season.title.trim() || season.totalEpisodes.trim(),
            )
            .map((season, index) => ({
                seasonNumber: numberOrNull(season.seasonNumber) ?? index + 1,
                title:
                    season.title.trim() ||
                    `${i18n.t.createModal.fields.season} ${index + 1}`,
                totalEpisodes: Math.max(
                    numberOrNull(season.totalEpisodes) ?? 0,
                    0,
                ),
                status: MEDIA_STATUS.planned,
            }));
    }

    function buildPayload(): CreateMediaPayload {
        const common = {
            title: title.trim(),
            status: MEDIA_STATUS.planned,
            coverUrl: optionalText(coverUrl),
            notes: optionalText(notes),
        };

        switch (type) {
            case "game":
                return {
                    ...common,
                    type: "game",
                    platform: platform.trim(),
                    hoursPlayed: numberOrNull(hoursPlayed),
                };
            case "book":
                return {
                    ...common,
                    type: "book",
                    author: author.trim(),
                    totalPages: numberOrNull(totalPages),
                };
            case "manga":
                return {
                    ...common,
                    type: "manga",
                    author: author.trim() || undefined,
                    totalChapters: numberOrNull(totalChapters),
                    currentVolume: numberOrNull(currentVolume) ?? 1,
                    totalVolumes: numberOrNull(totalPages) ?? 1,
                };
            case "movie":
                return {
                    ...common,
                    type: "movie",
                    durationMinutes: numberOrNull(durationMinutes),
                    isAnime,
                    studio: optionalText(studio),
                };
            case "tvshow":
                return {
                    ...common,
                    type: "tvshow",
                    isAnime,
                    studio: optionalText(studio),
                    network: optionalText(network),
                    seasons: buildSeasons(),
                };
        }
    }

    function resetForm() {
        type = "game";
        title = "";
        coverUrl = "";
        notes = "";
        platform = "";
        hoursPlayed = "";
        author = "";
        totalPages = "";
        totalChapters = "";
        currentVolume = "";
        durationMinutes = "";
        isAnime = false;
        studio = "";
        network = "";
        seasons = [];
        submitError = null;
        status = MEDIA_STATUS.planned;
        editingInitialized = false;
        score = "";
        startedAt = "";
        finishedAt = "";
        validationError = "";
    }

    function close() {
        if (submitting) return;
        resetForm();
        onClose();
    }

    async function submit() {
        validationError = "";
        submitError = null;

        if (!title.trim()) {
            validationError = i18n.t.createModal.validation.titleRequired;
            titleInput?.focus();
            return;
        }

        if (!isValidCoverUrl(coverUrl)) {
            validationError = i18n.t.createModal.validation.coverUrlInvalid;
            return;
        }

        submitting = true;

        try {
            const saved = editingItem
                ? await updateMedia(editingItem.id, {
                      title: title.trim(),
                      score: numberOrNull(score),
                      notes: optionalText(notes),
                      coverUrl: optionalText(coverUrl),
                      startedAt: startedAt
                          ? new Date(startedAt).toISOString()
                          : null,
                      finishedAt: finishedAt
                          ? new Date(finishedAt).toISOString()
                          : null,
                      status,
                  } satisfies UpdateMediaPayload)
                : await createMedia(buildPayload());
            resetForm();
            onCreated(saved);
            onClose();
        } catch (error) {
            submitError = error;
        } finally {
            submitting = false;
        }
    }

    </script>

<Modal {isOpen} onClose={close} labelledBy="create-media-title">
    <div class="flex flex-col max-h-[85vh]">
        <header
            class="flex shrink-0 items-start justify-between gap-4 border-b border-white/[0.07] px-5 py-5 sm:px-6"
        >
            <div>
                <p
                    class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
                >
                    {i18n.t.createModal.eyebrow}
                </p>
                <h2
                    id="create-media-title"
                    class="mt-1 text-xl font-bold tracking-tight text-ink"
                >
                    {editingItem
                        ? i18n.current === "ru"
                            ? "Редактировать медиа"
                            : "Edit Media"
                        : i18n.t.createModal.title}
                </h2>
            </div>
            <button
                type="button"
                class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink"
                aria-label={i18n.t.common.close}
                onclick={close}><X size={18} aria-hidden="true" /></button
            >
        </header>

        <form
            class="max-h-[75vh] space-y-5 overflow-y-auto p-5 sm:p-6"
            onsubmit={(event) => {
                event.preventDefault();
                void submit();
            }}
        >
            {#if validationError}
                <p
                    class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200"
                    role="alert"
                >
                    {validationError}
                </p>
            {/if}
            {#if submitError}
                <p
                    class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200"
                    role="alert"
                >
                    {errorMessage(submitError)}
                </p>
            {/if}

            <div class="grid gap-4 sm:grid-cols-2">
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.createModal.fields.type}</span><select
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        bind:value={type}
                        >{#each types as mediaType}<option value={mediaType}
                                >{i18n.t.types[mediaType]}</option
                            >{/each}</select
                    ></label
                >
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.createModal.fields.title}</span><input
                        bind:this={titleInput}
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        bind:value={title}
                        placeholder={i18n.t.createModal.placeholders.title}
                        required
                    /></label
                >
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.createModal.fields.score}</span><input
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        type="number"
                        min="1"
                        max="10"
                        bind:value={score}
                    /></label
                >
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.status.label}</span><select
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-accent"
                        bind:value={status}
                        >{#each Object.values(MEDIA_STATUS) as value}<option
                                {value}
                                >{i18n.t.status[
                                    value === 0
                                        ? "planned"
                                        : value === 1
                                          ? "inProgress"
                                          : value === 2
                                            ? "completed"
                                            : value === 3
                                              ? "paused"
                                              : "dropped"
                                ]}</option
                            >{/each}</select
                    ></label
                >
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.createModal.fields.startedAt}</span><input
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-accent"
                        type="datetime-local"
                        bind:value={startedAt}
                    /></label
                >
                <label class="space-y-1.5 text-sm font-medium text-ink"
                    ><span>{i18n.t.createModal.fields.finishedAt}</span><input
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-accent"
                        type="datetime-local"
                        bind:value={finishedAt}
                    /></label
                >
            </div>

            <div>
                <label class="block space-y-1.5 text-sm font-medium text-ink">
                    <span>{i18n.t.createModal.fields.coverUrl}</span>
                    <input
                        class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        type="text"
                        bind:value={coverUrl}
                    />
                </label>
            </div>

            <div>
                <label class="block space-y-1.5 text-sm font-medium text-ink">
                    <span>{i18n.t.createModal.fields.notes}</span>
                    <textarea
                        class="min-h-[140px] w-full resize-y rounded-lg border border-white/10 bg-field p-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        rows={5}
                        bind:value={notes}
                        placeholder={i18n.t.createModal.placeholders.notes}
                    ></textarea>
                </label>
            </div>

            {#if type === "game"}
                <GameFormFields bind:platform bind:hoursPlayed />
            {:else if type === "book"}
                <BookFormFields bind:author bind:totalPages />
            {:else if type === "manga"}
                <!-- The volume count shares the totalPages state; the payload reads it back as totalVolumes. -->
                <MangaFormFields
                    bind:author
                    bind:totalChapters
                    bind:currentVolume
                    bind:totalVolumes={totalPages}
                />
            {:else if type === "movie"}
                <MovieFormFields
                    bind:durationMinutes
                    bind:studio
                    bind:isAnime
                />
            {:else}
                <TvShowFormFields
                    bind:studio
                    bind:network
                    bind:isAnime
                    bind:seasons
                />
            {/if}

            <footer
                class="flex shrink-0 justify-end gap-3 border-t border-white/[0.07] pt-5"
            >
                <button
                    type="button"
                    class="tap rounded-md px-3 py-2 text-sm font-semibold text-muted transition hover:text-ink"
                    onclick={close}>{i18n.t.common.cancel}</button
                >
                <button
                    type="submit"
                    class="tap rounded-md bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover disabled:cursor-wait disabled:opacity-70"
                    disabled={submitting}
                >
                    {submitting
                        ? i18n.t.common.saving
                        : editingItem
                          ? i18n.t.common.save
                          : i18n.t.common.add}
                </button>
            </footer>
        </form>
    </div>
</Modal>
