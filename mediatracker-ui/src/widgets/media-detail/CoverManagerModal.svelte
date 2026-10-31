<script lang="ts">
  import {
    BookOpen,
    Check,
    Image as ImageIcon,
    Link2,
    LoaderCircle,
    Plus,
    Trash2,
    Upload,
    X,
  } from "$shared/ui/Icons";
  import {
    addCoverByFile,
    addCoverByUrl,
    deleteCover,
    errorMessage,
    fetchVolumeCovers,
    selectCover,
  } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import { fullSizeCoverUrl } from "$entities/media/model/coverUrl";
  import type { MediaCoverItem, MediaDetail } from "$shared/types";

  interface Props {
    isOpen: boolean;
    media: MediaDetail;
    onClose: () => void;
    onUpdate: (updated: MediaDetail) => void;
  }

  let { isOpen, media, onClose, onUpdate }: Props = $props();

  let addMode = $state<"url" | "file">("url");
  let urlInput = $state("");
  let fileInput = $state<HTMLInputElement | null>(null);
  let selectedFile = $state<File | null>(null);
  let setAsActive = $state(true);

  let busy = $state(false);
  let fetchingVolumes = $state(false);
  let actionId = $state<string | null>(null);
  let error = $state<unknown>(null);
  let deletingId = $state<string | null>(null);

  const covers = $derived<MediaCoverItem[]>(media.covers ?? []);

  function isActiveCover(cover: MediaCoverItem): boolean {
    if (!media.coverUrl) return false;
    const cleanMedia = media.coverUrl.split("?")[0];
    const cleanCover = cover.thumbUrl.split("?")[0];
    return cleanMedia === cleanCover || cleanMedia.includes(cover.id);
  }

  function handleFileChange(event: Event) {
    const target = event.target as HTMLInputElement;
    if (target.files && target.files.length > 0) {
      selectedFile = target.files[0];
    } else {
      selectedFile = null;
    }
  }

  async function handleAddByUrl() {
    const trimmed = urlInput.trim();
    if (!trimmed || busy) return;
    busy = true;
    error = null;
    try {
      const updated = await addCoverByUrl(media.id, trimmed, null, setAsActive);
      urlInput = "";
      onUpdate(updated);
      showToast(i18n.t.coversModal.coverAdded, "success");
    } catch (err) {
      error = err;
    } finally {
      busy = false;
    }
  }

  async function handleAddByFile() {
    if (!selectedFile || busy) return;
    busy = true;
    error = null;
    try {
      const updated = await addCoverByFile(media.id, selectedFile, null, setAsActive);
      selectedFile = null;
      if (fileInput) fileInput.value = "";
      onUpdate(updated);
      showToast(i18n.t.coversModal.coverUploaded, "success");
    } catch (err) {
      error = err;
    } finally {
      busy = false;
    }
  }

  async function handleSelect(coverId: string) {
    if (busy) return;
    busy = true;
    actionId = coverId;
    error = null;
    try {
      const updated = await selectCover(media.id, coverId);
      onUpdate(updated);
      showToast(i18n.t.coversModal.coverSelected, "success");
    } catch (err) {
      error = err;
    } finally {
      busy = false;
      actionId = null;
    }
  }

  async function handleDelete(coverId: string) {
    if (busy) return;
    busy = true;
    actionId = coverId;
    error = null;
    try {
      const updated = await deleteCover(media.id, coverId);
      deletingId = null;
      onUpdate(updated);
      showToast(i18n.t.coversModal.coverDeleted, "success");
    } catch (err) {
      error = err;
    } finally {
      busy = false;
      actionId = null;
    }
  }

  async function handleFetchVolumes() {
    if (busy) return;
    busy = true;
    fetchingVolumes = true;
    error = null;
    try {
      const updated = await fetchVolumeCovers(media.id);
      onUpdate(updated);
      showToast(i18n.t.coversModal.volumesLoaded, "success");
    } catch (err) {
      error = err;
    } finally {
      busy = false;
      fetchingVolumes = false;
    }
  }
</script>

<Modal {isOpen} {onClose} labelledBy="cover-manager-title" size="lg">
  <div class="flex max-h-[85vh] flex-col overflow-hidden">
    <!-- Header -->
    <header
      class="flex shrink-0 items-center justify-between border-b border-white/[0.08] px-5 py-4"
    >
      <div class="flex items-center gap-2">
        <ImageIcon size={18} class="text-[var(--color-accent-soft)]" aria-hidden="true" />
        <h2 id="cover-manager-title" class="text-base font-bold text-white">
          {i18n.t.coversModal.title}
        </h2>
        {#if covers.length > 0}
          <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-slate-300">
            {covers.length}
          </span>
        {/if}
      </div>
      <button
        type="button"
        class="text-muted hover:text-ink grid h-8 w-8 place-items-center rounded-lg transition hover:bg-white/5"
        onclick={onClose}
        aria-label={i18n.t.common.close}
      >
        <X size={16} aria-hidden="true" />
      </button>
    </header>

    <!-- Add cover section -->
    <div class="shrink-0 border-b border-white/[0.08] bg-black/20 p-4">
      <div class="flex flex-wrap items-center justify-between gap-3 pb-3">
        <div class="flex flex-wrap items-center gap-2">
          <div
            class="flex items-center gap-1 rounded-lg border border-white/10 bg-white/5 p-0.5 text-xs"
          >
            <button
              type="button"
              class="flex items-center gap-1.5 rounded-md px-3 py-1.5 font-medium transition {addMode ===
              'url'
                ? 'bg-indigo-600 text-white'
                : 'text-slate-400 hover:text-white'}"
              onclick={() => (addMode = "url")}
            >
              <Link2 size={13} aria-hidden="true" />
              {i18n.t.coversModal.addByUrl}
            </button>
            <button
              type="button"
              class="flex items-center gap-1.5 rounded-md px-3 py-1.5 font-medium transition {addMode ===
              'file'
                ? 'bg-indigo-600 text-white'
                : 'text-slate-400 hover:text-white'}"
              onclick={() => (addMode = "file")}
            >
              <Upload size={13} aria-hidden="true" />
              {i18n.t.coversModal.uploadFile}
            </button>
          </div>

          {#if media.type === "manga"}
            <button
              type="button"
              class="flex items-center gap-1.5 rounded-lg border border-indigo-500/30 bg-indigo-500/10 px-3 py-1.5 text-xs font-medium text-indigo-300 transition hover:bg-indigo-500/20 hover:text-white disabled:opacity-50"
              disabled={busy}
              onclick={() => void handleFetchVolumes()}
              title={i18n.t.coversModal.fetchVolumes}
            >
              {#if fetchingVolumes}
                <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
                <span>{i18n.t.coversModal.fetchingVolumes}</span>
              {:else}
                <BookOpen size={13} aria-hidden="true" />
                <span>{i18n.t.coversModal.fetchVolumes}</span>
              {/if}
            </button>
          {/if}
        </div>

        <label class="flex cursor-pointer items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            bind:checked={setAsActive}
            class="rounded border-white/20 bg-white/10 text-indigo-600 focus:ring-indigo-500"
          />
          <span>{i18n.t.coversModal.setAsActive}</span>
        </label>
      </div>

      {#if addMode === "url"}
        <form
          onsubmit={(e) => {
            e.preventDefault();
            void handleAddByUrl();
          }}
          class="flex gap-2"
        >
          <input
            type="url"
            bind:value={urlInput}
            placeholder={i18n.t.coversModal.urlPlaceholder}
            class="h-9 flex-1 rounded-lg border border-white/10 bg-[#1c202b] px-3 text-xs text-white outline-none placeholder:text-slate-500 focus:border-indigo-500/60"
            disabled={busy}
          />
          <button
            type="submit"
            class="flex shrink-0 items-center gap-1.5 rounded-lg bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-50"
            disabled={busy || !urlInput.trim()}
          >
            {#if busy && !actionId}
              <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
              <span>{i18n.t.coversModal.downloading}</span>
            {:else}
              <Plus size={14} aria-hidden="true" />
              <span>{i18n.t.common.add}</span>
            {/if}
          </button>
        </form>
      {:else}
        <div class="flex items-center gap-2">
          <label
            class="flex h-9 flex-1 cursor-pointer items-center justify-between truncate rounded-lg border border-white/10 bg-[#1c202b] px-3 text-xs text-slate-300 hover:border-white/20"
          >
            <span class="truncate">
              {selectedFile ? selectedFile.name : i18n.t.coversModal.chooseFile}
            </span>
            <input
              type="file"
              accept="image/*"
              class="hidden"
              bind:this={fileInput}
              onchange={handleFileChange}
              disabled={busy}
            />
          </label>
          <button
            type="button"
            class="flex shrink-0 items-center gap-1.5 rounded-lg bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-50"
            disabled={busy || !selectedFile}
            onclick={() => void handleAddByFile()}
          >
            {#if busy && !actionId}
              <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
              <span>{i18n.t.coversModal.uploading}</span>
            {:else}
              <Upload size={14} aria-hidden="true" />
              <span>{i18n.t.common.add}</span>
            {/if}
          </button>
        </div>
      {/if}

      {#if error}
        <p class="mt-2 text-xs text-rose-300" role="alert">
          {errorMessage(error)}
        </p>
      {/if}
    </div>

    <!-- Gallery grid -->
    <div class="thin-scroll flex-1 overflow-y-auto p-4">
      {#if covers.length === 0 && !media.coverUrl}
        <div class="flex flex-col items-center justify-center py-12 text-center text-slate-400">
          <ImageIcon size={36} class="mb-2 text-slate-500" aria-hidden="true" />
          <p class="text-sm font-medium">{i18n.t.coversModal.noCovers}</p>
        </div>
      {:else if covers.length === 0 && media.coverUrl}
        <!-- Fallback if covers array is empty but title has a single legacy coverUrl -->
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
          <div
            style="contain: layout paint;"
            class="group relative aspect-[2/3] overflow-hidden rounded-xl border-2 border-emerald-500/80 shadow-md ring-2 ring-emerald-500/40"
          >
            <img
              src={fullSizeCoverUrl(media.coverUrl)}
              alt={media.title}
              loading="lazy"
              decoding="async"
              class="h-full w-full object-cover"
            />
            <div
              class="absolute top-2 left-2 flex items-center gap-1 rounded-md bg-emerald-600/95 px-2 py-0.5 text-[11px] font-bold text-white shadow"
            >
              <Check size={14} strokeWidth={3} aria-hidden="true" />
              <span>{i18n.t.coversModal.activeBadge}</span>
            </div>
          </div>
        </div>
      {:else}
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
          {#each covers as cover (cover.id)}
            {@const active = isActiveCover(cover)}
            <div
              style="contain: layout paint;"
              class="group relative aspect-[2/3] overflow-hidden rounded-xl transition {active
                ? 'border-2 border-emerald-500/80 ring-2 ring-emerald-500/40'
                : 'cursor-pointer border-2 border-transparent'}"
            >
              <img
                src={cover.thumbUrl}
                alt={cover.source ?? media.title}
                loading="lazy"
                decoding="async"
                referrerpolicy="no-referrer"
                class="h-full w-full object-cover transition duration-200 group-hover:scale-105"
              />

              <!-- Whole-image click selects an inactive cover -->
              {#if !active}
                <button
                  type="button"
                  class="absolute inset-0 cursor-pointer"
                  title={i18n.t.coversModal.select}
                  aria-label={i18n.t.coversModal.select}
                  disabled={busy}
                  onclick={() => void handleSelect(cover.id)}
                ></button>
              {/if}

              <!-- Active badge (top-left) -->
              {#if active}
                <div
                  class="absolute top-2 left-2 z-10 flex items-center gap-1 rounded-md bg-emerald-600/95 px-2 py-0.5 text-[11px] font-bold text-white shadow"
                >
                  <Check size={14} strokeWidth={3} aria-hidden="true" />
                  <span>{i18n.t.coversModal.activeBadge}</span>
                </div>
              {:else}
                <button
                  type="button"
                  class="absolute top-2 left-2 z-10 grid size-8 place-items-center rounded-lg border border-white/20 bg-black/70 text-white opacity-0 shadow-md transition duration-150 group-hover:opacity-100 hover:border-indigo-500 hover:bg-indigo-600 disabled:opacity-50"
                  title={i18n.t.coversModal.select}
                  aria-label={i18n.t.coversModal.select}
                  disabled={busy}
                  onclick={() => void handleSelect(cover.id)}
                >
                  {#if busy && actionId === cover.id}
                    <LoaderCircle size={16} class="animate-spin" aria-hidden="true" />
                  {:else}
                    <Check size={16} strokeWidth={2.5} aria-hidden="true" />
                  {/if}
                </button>
              {/if}

              <!-- Delete (top-right, on hover) -->
              <button
                type="button"
                class="absolute top-2 right-2 z-10 grid size-8 place-items-center rounded-lg border border-white/20 bg-black/70 text-slate-300 opacity-0 shadow-md transition duration-150 group-hover:opacity-100 hover:border-rose-500 hover:bg-rose-600 hover:text-white disabled:opacity-50"
                title={i18n.t.coversModal.delete}
                aria-label={i18n.t.coversModal.delete}
                disabled={busy}
                onclick={(e) => {
                  e.stopPropagation();
                  deletingId = cover.id;
                }}
              >
                <Trash2 size={14} aria-hidden="true" />
              </button>

              <!-- Delete confirmation -->
              {#if deletingId === cover.id}
                <div
                  class="absolute inset-0 z-20 grid place-items-center bg-black/85 p-3"
                  role="alertdialog"
                  aria-label={i18n.t.coversModal.delete}
                >
                  <div class="flex flex-col items-center gap-2 text-center">
                    <span class="text-xs font-semibold text-white">
                      {i18n.t.coversModal.delete}?
                    </span>
                    <div class="flex items-center gap-2">
                      <button
                        type="button"
                        class="rounded-md bg-rose-600 px-2.5 py-1 text-xs font-bold text-white transition hover:bg-rose-500 disabled:opacity-50"
                        disabled={busy}
                        onclick={() => void handleDelete(cover.id)}
                      >
                        {#if busy && actionId === cover.id}
                          <LoaderCircle size={12} class="animate-spin" aria-hidden="true" />
                        {:else}
                          {i18n.t.common.delete}
                        {/if}
                      </button>
                      <button
                        type="button"
                        class="rounded-md bg-white/10 px-2.5 py-1 text-xs font-semibold text-slate-200 transition hover:bg-white/20"
                        onclick={() => (deletingId = null)}
                      >
                        {i18n.t.common.cancel}
                      </button>
                    </div>
                  </div>
                </div>
              {/if}

              <!-- Source label (bottom, on hover) -->
              {#if cover.source}
                <div
                  class="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/60 to-transparent p-3 pt-8 opacity-0 transition duration-150 group-hover:opacity-100"
                >
                  <span class="line-clamp-2 text-xs font-bold text-white drop-shadow">
                    {cover.source}
                  </span>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </div>
</Modal>
