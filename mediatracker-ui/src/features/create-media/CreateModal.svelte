<script lang="ts">
  import EditMediaWorkspace from "$features/edit-media/EditMediaWorkspace.svelte";
  import type { MediaItem } from "$shared/types";

  /**
   * Legacy entry point kept for the existing lazy import in `App.svelte`. The editor itself lives
   * in `features/edit-media/EditMediaWorkspace.svelte` — a fullscreen spatial canvas of draggable
   * windows — and this thin adapter preserves the historical prop contract.
   */
  interface Props {
    isOpen: boolean;
    onClose: () => void;
    onCreated: (media: MediaItem) => void;
    editingItem?: MediaItem;
  }

  let { isOpen, onClose, onCreated, editingItem }: Props = $props();
</script>

<EditMediaWorkspace {isOpen} {onClose} {onCreated} {editingItem} />
