<script lang="ts">
  import Modal from "$shared/ui/Modal.svelte";
  import ImportPanel from "./ImportPanel.svelte";

  interface Props {
    isOpen: boolean;
    onClose: () => void;
    onImportCompleted: () => void;
    onNavigateToList?: (id: string) => void;
  }

  let { isOpen, onClose, onImportCompleted, onNavigateToList }: Props = $props();
</script>

<Modal {isOpen} {onClose} size="xl" labelledBy="import-modal-title">
  <div class="h-full flex flex-col min-h-0 p-6 overflow-y-auto thin-scroll">
    <ImportPanel
      {onImportCompleted}
      {onNavigateToList}
      {onClose}
      showCloseButton={true}
    />
  </div>
</Modal>
