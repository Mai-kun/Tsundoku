<script lang="ts">
  import { FileText } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import ModuleCard from "./ModuleCard.svelte";

  /**
   * Block 2 — standalone personal-notes editor. One bindable string, no API calls: the caller
   * decides when (and whether) to persist the text.
   */
  interface Props {
    notes: string;
  }

  let { notes = $bindable("") }: Props = $props();
</script>

<ModuleCard title={i18n.t.createModal.modules.notes}>
  {#snippet icon()}
    <FileText size={15} aria-hidden="true" />
  {/snippet}
  <textarea
    class="bg-field placeholder:text-muted min-h-[120px] w-full resize-y rounded-lg border border-white/10 p-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
    rows={5}
    bind:value={notes}
    placeholder={i18n.t.createModal.placeholders.notes}></textarea>
</ModuleCard>
