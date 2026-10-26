<script lang="ts">
  import { ArrowLeft, RefreshCw } from "$shared/ui/Icons.svelte";
  import { errorMessage, getMediaItem, setSeasonProgress } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import { isTvShowDetail, type TvShowDetail } from "$shared/types";
  import SeasonRow from "$widgets/media-detail/SeasonRow.svelte";

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
    class="text-muted hover:text-ink inline-flex items-center gap-2 text-sm font-semibold transition"
    onclick={onBack}><ArrowLeft size={16} aria-hidden="true" />{i18n.t.common.back}</button
  >

  {#if loading}
    <div class="space-y-4" aria-hidden="true">
      <div class="bg-card h-7 w-64 animate-pulse rounded"></div>
      {#each Array(3) as _, index (index)}
        <div class="bg-card h-32 animate-pulse rounded-lg"></div>
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
        class="bg-accent hover:bg-accent-hover inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium text-white transition"
        onclick={retry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button
      >
    </div>
  {:else if show}
    <section class="bg-surface overflow-hidden rounded-lg">
      <div class="flex gap-4 p-5">
        <div class="bg-card h-28 w-20 shrink-0 overflow-hidden rounded-md">
          {#if show.coverUrl}
            <img src={show.coverUrl} alt={show.title} class="h-full w-full object-cover" />
          {/if}
        </div>
        <div class="min-w-0 self-center">
          <p class="text-accent-soft text-xs font-semibold tracking-[0.16em] uppercase">
            {i18n.t.navigation.tvshow}
          </p>
          <h2 class="text-ink mt-1 truncate text-xl font-bold tracking-tight">
            {show.title}
          </h2>
          <p class="text-muted mt-2 text-sm">
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
        <div class="bg-surface text-muted rounded-lg p-8 text-center text-sm">
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
