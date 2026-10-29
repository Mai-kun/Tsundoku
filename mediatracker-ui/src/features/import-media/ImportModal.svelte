<script lang="ts">
  import Modal from "$shared/ui/Modal.svelte";

  interface Props {
    isOpen: boolean;
    onClose: () => void;
    onImportCompleted: () => void;
    onNavigateToList?: (id: string) => void;
  }

  let { isOpen, onClose, onImportCompleted, onNavigateToList }: Props = $props();
</script>

<Modal {isOpen} {onClose} size="xl" labelledBy="import-modal-title">
  <div class="thin-scroll flex h-full min-h-0 flex-col overflow-y-auto p-6">
    {#if isOpen}
      {#await import("./ImportPanel.svelte") then { default: ImportPanel }}
        <ImportPanel {onImportCompleted} {onNavigateToList} {onClose} showCloseButton={true} />
      {/await}
    {/if}
  </div>
</Modal>
