<script lang="ts">
  import { FileText } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import ModuleCard from "./ModuleCard.svelte";

  /**
   * Block 2 — standalone personal-notes editor. One bindable string, no API calls: the caller
   * decides when (and whether) to persist the text.
   */
  interface Props {
    flat?: boolean;
    showLabel?: boolean;
    notes: string;
  }

  let { notes = $bindable(""),
    flat = false,
    showLabel = true,
  }: Props = $props();
</script>

<ModuleCard flat={flat} showLabel={showLabel} title={i18n.t.createModal.modules.notes}>
  {#snippet icon()}
    <FileText size={15} aria-hidden="true" />
  {/snippet}
  <!-- Flat mode fills its host (the workspace window): the textarea stretches with the window
       instead of staying at its rows height. Standalone use keeps the fixed-ish height. -->
  <textarea
    class="bg-field placeholder:text-muted w-full rounded-lg border border-white/10 p-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30 {flat
      ? 'h-full min-h-0 flex-1 resize-none'
      : 'min-h-[120px] resize-y'}"
    rows={5}
    bind:value={notes}
    placeholder={i18n.t.createModal.placeholders.notes}></textarea>
</ModuleCard>
