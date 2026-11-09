<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";

  /**
   * Full-screen settings. The section panel (sources, search, backup...) is the same component the
   * old overlay modal used — rendered here embedded, without the modal chrome, so the whole settings
   * surface keeps one implementation instead of a forked copy. `initialTab` lets other parts of the
   * app deep-link into a specific section (default: sources).
   */
  interface Props {
    initialTab?:
      | "sources"
      | "search"
      | "backup"
      | "import"
      | "reading"
      | "apiTokens"
      | "update"
      | "storage"
      | "desktop"
      | "appearance";
    onImportCompleted: () => void;
    onNavigateToList?: (id: string) => void;
    onTestSearch?: (sourceId: string, type?: string) => void;
  }

  let {
    initialTab = "sources",
    onImportCompleted,
    onNavigateToList,
    onTestSearch,
  }: Props = $props();
</script>

<div class="h-full w-full flex overflow-hidden">
  {#await import("$features/settings/SettingsModal.svelte") then { default: SettingsPanel }}
    <div class="view-fade h-full w-full flex overflow-hidden" aria-label={i18n.t.settingsModal.title}>
      <SettingsPanel
        isOpen={false}
        onClose={() => {}}
        {onImportCompleted}
        {onNavigateToList}
        {onTestSearch}
        embedded
        {initialTab}
      />
    </div>
  {:catch error}
    {@const _ = console.error("Failed to load settings view:", error)}
  {/await}
</div>
