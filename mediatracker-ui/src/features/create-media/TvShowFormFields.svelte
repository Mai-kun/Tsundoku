<script lang="ts">
  import { Minus, Plus } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import FormField from "./FormField.svelte";

  export interface SeasonDraft {
    seasonNumber: string;
    title: string;
    totalEpisodes: string;
  }

  interface Props {
    studio: string;
    network: string;
    isAnime: boolean;
    seasons: SeasonDraft[];
  }

  let {
    studio = $bindable(),
    network = $bindable(),
    isAnime = $bindable(),
    seasons = $bindable(),
  }: Props = $props();

  function addSeason() {
    seasons = [
      ...seasons,
      {
        seasonNumber: String(seasons.length + 1),
        title: "",
        totalEpisodes: "",
      },
    ];
  }

  function removeSeason(index: number) {
    seasons = seasons.filter((_, seasonIndex) => seasonIndex !== index);
  }
</script>

<div class="grid gap-4 sm:grid-cols-2">
  <FormField label={i18n.t.createModal.fields.studio}>
    <input
      class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      bind:value={studio}
      placeholder={i18n.t.createModal.placeholders.studio}
    />
  </FormField>

  <FormField label={i18n.t.createModal.fields.network}>
    <input
      class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      bind:value={network}
      placeholder={i18n.t.createModal.placeholders.network}
    />
  </FormField>
</div>

<label class="text-muted inline-flex items-center gap-2 text-sm">
  <input class="accent-accent h-4 w-4" type="checkbox" bind:checked={isAnime} />
  {i18n.t.createModal.fields.isAnime}
</label>

<div class="bg-field/50 space-y-3 rounded-xl border border-white/10 p-3">
  <div class="flex items-center justify-between">
    <p class="text-ink text-sm font-semibold">
      {i18n.t.navigation.seasons}
    </p>
    <button
      type="button"
      class="text-accent-soft hover:text-ink inline-flex items-center gap-1.5 text-xs font-semibold transition"
      onclick={addSeason}
      ><Plus size={14} aria-hidden="true" />{i18n.t.createModal.addSeason}</button
    >
  </div>
  {#each seasons as season, index (index)}
    <div class="grid gap-2 sm:grid-cols-[5rem_1fr_7rem_auto]">
      <input
        class="bg-field focus:border-accent h-9 rounded-lg border border-white/10 px-2 text-sm outline-none"
        type="number"
        min="1"
        bind:value={season.seasonNumber}
        aria-label={i18n.t.createModal.fields.season}
      /><input
        class="bg-field placeholder:text-muted focus:border-accent h-9 rounded-lg border border-white/10 px-2 text-sm outline-none"
        bind:value={season.title}
        placeholder={i18n.t.createModal.placeholders.season}
      /><input
        class="bg-field placeholder:text-muted focus:border-accent h-9 rounded-lg border border-white/10 px-2 text-sm outline-none"
        type="number"
        min="0"
        bind:value={season.totalEpisodes}
        placeholder={i18n.t.createModal.fields.episodes}
      /><button
        type="button"
        class="text-muted grid h-9 w-9 place-items-center rounded-lg transition hover:bg-rose-400/10 hover:text-rose-300"
        aria-label={i18n.t.common.delete}
        onclick={() => removeSeason(index)}><Minus size={16} aria-hidden="true" /></button
      >
    </div>
  {/each}
</div>
