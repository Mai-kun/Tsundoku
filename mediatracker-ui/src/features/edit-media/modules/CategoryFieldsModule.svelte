<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Clapperboard } from "$shared/ui/Icons";
  import BookFormFields from "$features/create-media/BookFormFields.svelte";
  import GameFormFields from "$features/create-media/GameFormFields.svelte";
  import MangaFormFields from "$features/create-media/MangaFormFields.svelte";
  import MovieFormFields from "$features/create-media/MovieFormFields.svelte";
  import TvShowFormFields from "$features/create-media/TvShowFormFields.svelte";
  import type { MediaType } from "$shared/types";
  import ModuleCard from "./ModuleCard.svelte";
  import type { CategoryDraft } from "./moduleTypes";

  /**
   * Block 5 — the type-specific fields, delegating to the existing per-category form components.
   * The whole bundle travels through one bindable `category` object. For an existing title the
   * season rows are read-only: the update contract has no season writes, seasons are edited on the
   * show's detail screen, so the form must not promise otherwise.
   */
  interface Props {
    type: MediaType;
    category: CategoryDraft;
    /** True when editing an existing row — switches the tv-show season list to read-only. */
    isEditing?: boolean;
  }

  let { type, category = $bindable(), isEditing = false }: Props = $props();
</script>

<ModuleCard title={i18n.t.createModal.modules.category}>
  {#snippet icon()}
    <Clapperboard size={15} aria-hidden="true" />
  {/snippet}
  <div class="space-y-3">
    {#if type === "game"}
      <GameFormFields bind:platform={category.platform} bind:hoursPlayed={category.hoursPlayed} />
    {:else if type === "book"}
      <BookFormFields
        bind:author={category.author}
        bind:totalPages={category.totalPages}
        bind:format={category.bookFormat}
        bind:totalChapters={category.totalChapters}
        bind:totalVolumes={category.bookTotalVolumes}
      />
    {:else if type === "manga"}
      <MangaFormFields
        bind:author={category.author}
        bind:totalChapters={category.totalChapters}
        bind:currentVolume={category.currentVolume}
        bind:totalVolumes={category.totalPages}
      />
    {:else if type === "movie"}
      <MovieFormFields
        bind:durationMinutes={category.durationMinutes}
        bind:studio={category.studio}
        bind:isAnime={category.isAnime}
      />
    {:else if type === "tvshow" && isEditing}
      <div class="space-y-3">
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="text-ink space-y-1.5 text-sm font-medium">
            <span>{i18n.t.createModal.fields.studio}</span>
            <input
              class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
              bind:value={category.studio}
              placeholder={i18n.t.createModal.placeholders.studio}
            />
          </label>
          <label class="text-ink space-y-1.5 text-sm font-medium">
            <span>{i18n.t.createModal.fields.network}</span>
            <input
              class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
              bind:value={category.network}
              placeholder={i18n.t.createModal.placeholders.network}
            />
          </label>
        </div>
        <label class="text-muted inline-flex items-center gap-2 text-sm">
          <input class="accent-accent h-4 w-4" type="checkbox" bind:checked={category.isAnime} />
          {i18n.t.createModal.fields.isAnime}
        </label>
        {#if category.seasons.length > 0}
          <div class="bg-field/50 space-y-2 rounded-xl border border-white/10 p-3">
            <p class="text-ink text-sm font-semibold">{i18n.t.navigation.seasons}</p>
            <ul class="space-y-1">
              {#each category.seasons as season (season.seasonNumber)}
                <li class="text-muted flex items-baseline justify-between gap-3 text-sm">
                  <span class="text-slate-300 truncate">
                    {i18n.t.createModal.fields.season} {season.seasonNumber}
                    {#if season.title}
                      — {season.title}
                    {/if}
                  </span>
                  <span class="shrink-0 text-xs">
                    {i18n.t.createModal.fields.episodes}: {season.totalEpisodes}
                  </span>
                </li>
              {/each}
            </ul>
            <p class="text-muted/70 text-xs">{i18n.t.createModal.seasonsReadonly}</p>
          </div>
        {/if}
      </div>
    {:else}
      <TvShowFormFields
        bind:studio={category.studio}
        bind:network={category.network}
        bind:isAnime={category.isAnime}
        bind:seasons={category.seasons}
      />
    {/if}
  </div>
</ModuleCard>
