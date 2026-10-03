<script lang="ts">
    import { Minus, Plus } from "$shared/ui/Icons.svelte";
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
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            bind:value={studio}
            placeholder={i18n.t.createModal.placeholders.studio}
        />
    </FormField>

    <FormField label={i18n.t.createModal.fields.network}>
        <input
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            bind:value={network}
            placeholder={i18n.t.createModal.placeholders.network}
        />
    </FormField>
</div>

<label class="inline-flex items-center gap-2 text-sm text-muted">
    <input class="h-4 w-4 accent-accent" type="checkbox" bind:checked={isAnime} />
    {i18n.t.createModal.fields.isAnime}
</label>

<div class="space-y-3 rounded-xl border border-white/10 bg-field/50 p-3">
    <div class="flex items-center justify-between">
        <p class="text-sm font-semibold text-ink">
            {i18n.t.navigation.seasons}
        </p>
        <button
            type="button"
            class="inline-flex items-center gap-1.5 text-xs font-semibold text-accent-soft transition hover:text-ink"
            onclick={addSeason}
            ><Plus size={14} aria-hidden="true" />{i18n.t.createModal
                .addSeason}</button
        >
    </div>
    {#each seasons as season, index (index)}
        <div class="grid gap-2 sm:grid-cols-[5rem_1fr_7rem_auto]">
            <input
                class="h-9 rounded-lg border border-white/10 bg-field px-2 text-sm outline-none focus:border-accent"
                type="number"
                min="1"
                bind:value={season.seasonNumber}
                aria-label={i18n.t.createModal.fields.season}
            /><input
                class="h-9 rounded-lg border border-white/10 bg-field px-2 text-sm outline-none placeholder:text-muted focus:border-accent"
                bind:value={season.title}
                placeholder={i18n.t.createModal.placeholders.season}
            /><input
                class="h-9 rounded-lg border border-white/10 bg-field px-2 text-sm outline-none placeholder:text-muted focus:border-accent"
                type="number"
                min="0"
                bind:value={season.totalEpisodes}
                placeholder={i18n.t.createModal.fields.episodes}
            /><button
                type="button"
                class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-rose-400/10 hover:text-rose-300"
                aria-label={i18n.t.common.delete}
                onclick={() => removeSeason(index)}
                ><Minus size={16} aria-hidden="true" /></button
            >
        </div>
    {/each}
</div>