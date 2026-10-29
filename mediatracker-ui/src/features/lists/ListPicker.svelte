<script lang="ts">
  import {
    addMediaToList,
    errorMessage,
    getLists,
    getListsForMedia,
    removeMediaFromList,
  } from "$shared/api/api";
  import CreateListModal from "$features/lists/CreateListModal.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import { List, Plus } from "$shared/ui/Icons";
  import type { CustomListSummary } from "$shared/types";
  import Modal from "$shared/ui/Modal.svelte";

  interface Props {
    mediaId: string;
  }
  let { mediaId }: Props = $props();
  let open = $state(false);
  let createOpen = $state(false);
  let loading = $state(false);
  let lists = $state.raw<CustomListSummary[]>([]);
  let included = $state<string[]>([]);
  let busyIds = $state<string[]>([]);

  async function showPicker() {
    open = true;
    loading = true;
    try {
      [lists, included] = await Promise.all([getLists(), getListsForMedia(mediaId)]);
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      loading = false;
    }
  }

  async function toggle(list: CustomListSummary) {
    if (busyIds.includes(list.id)) return;
    const wasIncluded = included.includes(list.id);
    included = wasIncluded ? included.filter((id) => id !== list.id) : [...included, list.id];
    busyIds = [...busyIds, list.id];
    try {
      if (wasIncluded) await removeMediaFromList(list.id, mediaId);
      else await addMediaToList(list.id, mediaId);
      showToast(
        wasIncluded ? i18n.t.views.listRemoved(list.name) : i18n.t.views.listAdded(list.name),
      );
    } catch (error) {
      included = wasIncluded ? [...included, list.id] : included.filter((id) => id !== list.id);
      showToast(errorMessage(error), "error");
    } finally {
      busyIds = busyIds.filter((id) => id !== list.id);
    }
  }

  async function refreshLists() {
    try {
      lists = await getLists();
    } catch (error) {
      showToast(errorMessage(error), "error");
    }
  }
</script>

<button
  type="button"
  class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
  onclick={() => void showPicker()}
>
  <List size={15} class="text-[var(--color-accent-soft)]" aria-hidden="true" />{i18n.t.views
    .listAddTo}
</button>

<Modal isOpen={open} onClose={() => (open = false)} labelledBy="list-picker-title">
  <div class="p-5 sm:p-6">
    <div class="flex items-center justify-between gap-3">
      <h2 id="list-picker-title" class="text-ink text-lg font-bold">
        {i18n.t.views.listPickerTitle}
      </h2>
      <button
        type="button"
        class="text-accent-soft inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-semibold hover:bg-white/5"
        onclick={() => (createOpen = true)}><Plus size={14} />{i18n.t.views.listNew}</button
      >
    </div>
    {#if loading}<p class="text-muted py-8 text-center text-sm">{i18n.t.common.loading}</p>
    {:else if lists.length === 0}<p class="text-muted py-8 text-center text-sm">
        {i18n.t.views.listPickerEmpty}
      </p>
    {:else}<div class="mt-4 max-h-[60vh] space-y-1 overflow-y-auto">
        {#each lists as list (list.id)}
          <label
            class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-3 transition hover:bg-white/[0.05]"
          >
            <input
              type="checkbox"
              checked={included.includes(list.id)}
              disabled={busyIds.includes(list.id)}
              onchange={() => void toggle(list)}
              class="h-4 w-4 accent-indigo-500"
            />
            <span
              class="grid h-8 w-8 place-items-center rounded-lg text-white"
              style={`background:${list.color ?? "#5844e0"}`}><List size={15} /></span
            >
            <span class="text-ink min-w-0 flex-1 truncate text-sm font-medium">{list.name}</span>
            <span class="text-muted text-xs">{i18n.t.views.listTitles(list.itemsCount)}</span>
          </label>
        {/each}
      </div>{/if}
  </div>
</Modal>

<CreateListModal
  isOpen={createOpen}
  onClose={() => (createOpen = false)}
  onSaved={() => void refreshLists()}
/>
