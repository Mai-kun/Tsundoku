<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import FormField from "./FormField.svelte";

    interface Props {
        author: string;
        totalChapters: string;
        currentVolume: string;
        /** Doubles as the total-volume field; the parent owns the binding. */
        totalVolumes: string;
    }

    let {
        author = $bindable(),
        totalChapters = $bindable(),
        currentVolume = $bindable(),
        totalVolumes = $bindable(),
    }: Props = $props();
</script>

<div class="grid gap-4 sm:grid-cols-2">
    <FormField label={i18n.t.createModal.fields.author}>
        <input
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            bind:value={author}
            placeholder={i18n.t.createModal.placeholders.author}
        />
    </FormField>

    <FormField label={i18n.t.createModal.fields.totalChapters}>
        <input
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            type="number"
            min="0"
            bind:value={totalChapters}
        />
    </FormField>
</div>

<div class="grid gap-4 sm:grid-cols-2">
    <FormField label={i18n.t.createModal.fields.currentVolume}>
        <input
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            type="number"
            min="0"
            bind:value={currentVolume}
        />
    </FormField>

    <FormField label={i18n.t.detail.tabVolumes}>
        <input
            class="h-10 w-full rounded-lg border border-white/10 bg-field px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            type="number"
            min="0"
            bind:value={totalVolumes}
            placeholder="1"
        />
    </FormField>
</div>