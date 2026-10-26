<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import FormField from "./FormField.svelte";

  interface Props {
    durationMinutes: string;
    studio: string;
    isAnime: boolean;
  }

  let {
    durationMinutes = $bindable(),
    studio = $bindable(),
    isAnime = $bindable(),
  }: Props = $props();
</script>

<div class="grid gap-4 sm:grid-cols-2">
  <FormField label={i18n.t.createModal.fields.durationMinutes}>
    <input
      class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      type="number"
      min="0"
      bind:value={durationMinutes}
    />
  </FormField>

  <FormField label={i18n.t.createModal.fields.studio}>
    <input
      class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      bind:value={studio}
      placeholder={i18n.t.createModal.placeholders.studio}
    />
  </FormField>
</div>

<label class="text-muted inline-flex items-center gap-2 text-sm">
  <input class="accent-accent h-4 w-4" type="checkbox" bind:checked={isAnime} />
  {i18n.t.createModal.fields.isAnime}
</label>
