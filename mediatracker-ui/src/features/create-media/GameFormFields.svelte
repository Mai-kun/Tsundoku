<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import FormField from "./FormField.svelte";

  interface Props {
    platform: string;
    hoursPlayed: string;
  }

  let { platform = $bindable(), hoursPlayed = $bindable() }: Props = $props();
</script>

<div class="grid gap-4 sm:grid-cols-2">
  <FormField label={i18n.t.createModal.fields.platform}>
    <input
      class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      bind:value={platform}
      placeholder={i18n.t.createModal.placeholders.platform}
    />
  </FormField>

  <FormField label={i18n.t.createModal.fields.hoursPlayed}>
    <input
      class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
      type="number"
      min="0"
      bind:value={hoursPlayed}
    />
  </FormField>
</div>
