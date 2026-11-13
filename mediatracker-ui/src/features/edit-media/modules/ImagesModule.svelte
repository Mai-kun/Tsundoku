<script lang="ts">
  import { Check, Image as ImageIcon, LoaderCircle, Trash2, Upload } from "$shared/ui/Icons";
  import {
    addCoverByFile,
    addCoverByUrl,
    deleteCover,
    errorMessage,
    selectCover,
  } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import { isValidCoverUrl } from "$entities/media/model/coverUrl";
  import ModuleCard from "./ModuleCard.svelte";
  import type { MediaCoverItem, MediaDetail } from "$shared/types";

  /**
   * Block 6 — cover and image management. Without a media id (a brand-new entry) it offers the
   * direct cover-URL field; for an existing title it grows into full cover management through the
   * server endpoints: paste one or many URLs (one per line), upload or drop local files, and pick
   * which stored cover is the active one. Every server action comes back through `onCoversChange`
   * so the caller keeps its preview in sync.
   */
  interface Props {
    mediaId: string | null;
    coverUrl: string;
    /** Alt text for previews; the title being edited. */
    title: string;
    covers?: MediaCoverItem[];
    onCoversChange?: (updated: MediaDetail) => void;
  }

  let {
    mediaId,
    coverUrl = $bindable(""),
    title,
    covers = [],
    onCoversChange,
  }: Props = $props();

  let busy = $state(false);
  let actionId = $state<string | null>(null);
  let error = $state<unknown>(null);
  let urlDraft = $state("");
  let setAsActive = $state(true);
  let isDragging = $state(false);
  let fileInput = $state<HTMLInputElement | null>(null);

  function splitUrls(raw: string): string[] {
    return raw
      .split(/\n/)
      .map((value) => value.trim())
      .filter(Boolean);
  }

  const urlDraftCount = $derived(splitUrls(urlDraft).length);

  async function addUrls() {
    const urls = splitUrls(urlDraft).filter((url) => isValidCoverUrl(url));
    if (!mediaId || urls.length === 0 || busy) return;
    busy = true;
    error = null;
    try {
      let updated: MediaDetail | null = null;
      for (const url of urls) {
        updated = await addCoverByUrl(mediaId, url, null, setAsActive);
      }
      if (updated) {
        coverUrl = updated.coverUrl ?? coverUrl;
        onCoversChange?.(updated);
      }
      urlDraft = "";
    } catch (err) {
      error = err;
    } finally {
      busy = false;
    }
  }

  async function uploadFiles(files: FileList | File[]) {
    if (!mediaId || busy) return;
    const list = Array.from(files).filter((file) => file.type.startsWith("image/"));
    if (list.length === 0) return;
    busy = true;
    error = null;
    try {
      let updated: MediaDetail | null = null;
      for (const file of list) {
        updated = await addCoverByFile(mediaId, file, null, setAsActive);
      }
      if (updated) {
        coverUrl = updated.coverUrl ?? coverUrl;
        onCoversChange?.(updated);
      }
      if (fileInput) fileInput.value = "";
    } catch (err) {
      error = err;
    } finally {
      busy = false;
    }
  }

  async function handleSelect(cover: MediaCoverItem) {
    if (!mediaId || busy) return;
    busy = true;
    actionId = cover.id;
    error = null;
    try {
      const updated = await selectCover(mediaId, cover.id);
      coverUrl = updated.coverUrl ?? coverUrl;
      onCoversChange?.(updated);
    } catch (err) {
      error = err;
    } finally {
      busy = false;
      actionId = null;
    }
  }

  async function handleDelete(cover: MediaCoverItem) {
    if (!mediaId || busy) return;
    busy = true;
    actionId = cover.id;
    error = null;
    try {
      const updated = await deleteCover(mediaId, cover.id);
      onCoversChange?.(updated);
    } catch (err) {
      error = err;
    } finally {
      busy = false;
      actionId = null;
    }
  }

  function isActiveCover(cover: MediaCoverItem): boolean {
    if (!coverUrl) return false;
    return coverUrl.split("?")[0] === cover.thumbUrl.split("?")[0] || coverUrl.includes(cover.id);
  }
</script>

<ModuleCard title={i18n.t.createModal.modules.images} count={mediaId ? covers.length : undefined}>
  {#snippet icon()}
    <ImageIcon size={15} aria-hidden="true" />
  {/snippet}
  <div class="space-y-3">
    {#if !mediaId}
      <!-- New entry: nothing is stored yet, so the cover travels as a plain URL in the payload. -->
      <label class="text-ink block space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.coverUrl}</span>
        <input
          class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          type="text"
          bind:value={coverUrl}
          placeholder={i18n.t.coversModal.urlPlaceholder}
        />
      </label>
      <p class="text-muted/70 text-xs">{i18n.t.createModal.imagesModule.createModeHint}</p>
    {:else}
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.coversModal.addByUrl}</span>
        <textarea
          class="bg-field placeholder:text-muted min-h-[64px] w-full resize-y rounded-lg border border-white/10 p-2.5 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          rows={2}
          bind:value={urlDraft}
          placeholder={i18n.t.createModal.imagesModule.multiUrlsPlaceholder}></textarea>
      </label>
      <div class="flex items-center justify-between gap-2">
        <label class="text-muted inline-flex items-center gap-2 text-xs">
          <input class="accent-accent h-3.5 w-3.5" type="checkbox" bind:checked={setAsActive} />
          {i18n.t.coversModal.setAsActive}
        </label>
        <button
          type="button"
          class="tap bg-accent hover:bg-accent-hover rounded-lg px-3 py-1.5 text-xs font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-50"
          disabled={busy || urlDraftCount === 0}
          onclick={() => void addUrls()}
        >
          {#if busy}
            <LoaderCircle size={12} class="mr-1 inline animate-spin" aria-hidden="true" />
          {/if}
          {i18n.t.coversModal.addCover}{urlDraftCount > 1 ? ` (${urlDraftCount})` : ""}
        </button>
      </div>

      <div
        class="flex flex-col items-center gap-1.5 rounded-lg border border-dashed px-3 py-4 text-center transition {isDragging
          ? 'border-indigo-400/60 bg-indigo-500/10'
          : 'border-white/10'}"
        role="button"
        tabindex="0"
        aria-label={i18n.t.createModal.imagesModule.dropHere}
        ondragover={(event) => {
          event.preventDefault();
          isDragging = true;
        }}
        ondragleave={() => (isDragging = false)}
        ondrop={(event) => {
          event.preventDefault();
          isDragging = false;
          if (event.dataTransfer?.files?.length) void uploadFiles(event.dataTransfer.files);
        }}
        onkeydown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            fileInput?.click();
          }
        }}
        onclick={() => fileInput?.click()}
      >
        <Upload size={16} class="text-muted" aria-hidden="true" />
        <span class="text-muted text-xs">{i18n.t.createModal.imagesModule.dropHere}</span>
        <input
          type="file"
          accept="image/*"
          multiple
          class="hidden"
          bind:this={fileInput}
          onchange={(event) => {
            const target = event.currentTarget;
            if (target.files?.length) void uploadFiles(target.files);
          }}
        />
      </div>

      {#if error}
        <p class="text-xs text-rose-300" role="alert">{errorMessage(error)}</p>
      {/if}

      {#if covers.length > 0}
        <div class="grid grid-cols-3 gap-2 sm:grid-cols-4">
          {#each covers as cover (cover.id)}
            {@const active = isActiveCover(cover)}
            <div
              class="group relative aspect-[2/3] overflow-hidden rounded-lg border transition {active
                ? 'border-emerald-500/80'
                : 'border-white/10'}"
            >
              <img
                src={cover.thumbUrl}
                alt={title}
                loading="lazy"
                decoding="async"
                referrerpolicy="no-referrer"
                class="h-full w-full object-cover"
              />
              {#if active}
                <span
                  class="absolute top-1 left-1 flex items-center gap-0.5 rounded bg-emerald-600/95 px-1 py-0.5 text-[10px] font-bold text-white"
                >
                  <Check size={10} strokeWidth={3} aria-hidden="true" />
                  {i18n.t.coversModal.activeBadge}
                </span>
              {:else}
                <button
                  type="button"
                  class="absolute inset-0 cursor-pointer bg-black/0 transition group-hover:bg-black/40"
                  title={i18n.t.coversModal.select}
                  aria-label={i18n.t.coversModal.select}
                  disabled={busy}
                  onclick={() => void handleSelect(cover)}
                >
                  {#if busy && actionId === cover.id}
                    <span class="grid h-full place-items-center">
                      <LoaderCircle size={16} class="animate-spin text-white" aria-hidden="true" />
                    </span>
                  {/if}
                </button>
              {/if}
              <button
                type="button"
                class="absolute top-1 right-1 grid size-6 place-items-center rounded-md border border-white/20 bg-black/70 text-slate-300 opacity-0 transition group-hover:opacity-100 hover:text-rose-300 disabled:opacity-50"
                title={i18n.t.coversModal.delete}
                aria-label={i18n.t.coversModal.delete}
                disabled={busy}
                onclick={() => void handleDelete(cover)}
              >
                <Trash2 size={12} aria-hidden="true" />
              </button>
            </div>
          {/each}
        </div>
      {/if}
    {/if}
  </div>
</ModuleCard>
