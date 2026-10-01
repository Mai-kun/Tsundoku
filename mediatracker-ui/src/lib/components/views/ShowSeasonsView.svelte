<script lang="ts">
    import ArrowLeft from "lucide-svelte/icons/arrow-left";
    import RefreshCw from "lucide-svelte/icons/refresh-cw";
    import { errorMessage, getMediaItem, setSeasonProgress } from "$lib/api";
    import { i18n } from "$lib/i18n/index.svelte";
    import { isTvShowDetail, type TvShowDetail } from "$lib/types";
    import SeasonRow from "../media/SeasonRow.svelte";

    interface Props {
        mediaId: string;
        refreshKey: number;
        onBack: () => void;
        onMediaChanged: () => void;
    }

    let { mediaId, refreshKey, onBack, onMediaChanged }: Props = $props();

    let show = $state<TvShowDetail | null>(null);
    let loading = $state(true);
    let loadError = $state<unknown>(null);
    let requestSequence = 0;

    $effect(() => {
        void refreshKey;
        void mediaId;
        void loadShow(++requestSequence);
    });

    async function loadShow(sequence: number) {
        loading = true;
        loadError = null;

        try {
            const media = await getMediaItem(mediaId);
            if (!isTvShowDetail(media)) {
                throw new Error("Media item is not a TV show");
            }

            if (sequence === requestSequence) {
                show = media;
            }
        } catch (error) {
            if (sequence === requestSequence) {
                loadError = error;
            }
        } finally {
            if (sequence === requestSequence) {
                loading = false;
            }
        }
    }

    function retry() {
        void loadShow(++requestSequence);
    }
</script>

<div class="mx-auto max-w-4xl space-y-6">
    <button
        type="button"
        class="inline-flex items-center gap-2 text-sm font-semibold text-muted transition hover:text-ink"
        onclick={onBack}
        ><ArrowLeft size={16} aria-hidden="true" />{i18n.t.common.back}</button
    >

    {#if loading}
        <div class="space-y-4" aria-hidden="true">
            <div class="h-7 w-64 animate-pulse rounded bg-card"></div>
            {#each Array(3) as _, index (index)}
                <div class="h-32 animate-pulse rounded-lg bg-card"></div>
            {/each}
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
    {:else if loadError}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
        >
            <p class="text-sm text-rose-200" role="alert">
                {errorMessage(loadError)}
            </p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
                onclick={retry}
                ><RefreshCw size={15} aria-hidden="true" />{i18n.t.common
                    .retry}</button
            >
        </div>
    {:else if show}
        <section class="overflow-hidden rounded-lg bg-surface">
            <div class="flex gap-4 p-5">
                <div
                    class="h-28 w-20 shrink-0 overflow-hidden rounded-md bg-card"
                >
                    {#if show.coverUrl}
                        <img
                            src={show.coverUrl}
                            alt={show.title}
                            class="h-full w-full object-cover"
                        />
                    {/if}
                </div>
                <div class="min-w-0 self-center">
                    <p
                        class="text-xs font-semibold uppercase tracking-[0.16em] text-accent-soft"
                    >
                        {i18n.t.navigation.tvshow}
                    </p>
                    <h2
                        class="mt-1 truncate text-xl font-bold tracking-tight text-ink"
                    >
                        {show.title}
                    </h2>
                    <p class="mt-2 text-sm text-muted">
                        {show.totalEpisodesWatched} / {show.totalEpisodesCount} ·
                        {show.seasonsCount}
                    </p>
                </div>
            </div>
        </section>

        <section class="space-y-3">
            <h1 class="text-lg font-bold tracking-wide text-white">
                {i18n.t.views.seasonsOf(show.title)}
            </h1>
            {#if (show.seasons ?? []).length === 0}
                <div
                    class="rounded-lg bg-surface p-8 text-center text-sm text-muted"
                >
                    {i18n.t.views.noSeasons}
                </div>
            {:else}
                <div class="space-y-3">
                    {#each show.seasons ?? [] as season (season.id)}
                        <SeasonRow
                            {season}
                            onProgress={setSeasonProgress}
                            onProgressCommitted={onMediaChanged}
                        />
                    {/each}
                </div>
            {/if}
        </section>
    {/if}
</div>
