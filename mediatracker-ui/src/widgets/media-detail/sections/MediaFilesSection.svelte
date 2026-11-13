<script module lang="ts">
  const BOOK_FILE_RE = /\.(epub|fb2|fb2\.zip|mobi|azw3?|djvu?)$/i;
  const ARCHIVE_RE = /\.(zip|rar|7z|cbz|cbr|tar|gz)$/i;
  const DOCUMENT_RE = /\.(pdf|docx?|odt|rtf|txt)$/i;
</script>

<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import {
    Archive,
    BookOpen,
    Download,
    Eye,
    FileText,
    LoaderCircle,
    Paperclip,
    Plus,
    Trash2,
  } from "$shared/ui/Icons";
  import {
    attachMediaFile,
    detachMediaFile,
    errorMessage,
    mediaFileDownloadUrl,
    openMediaFile,
  } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import type { MediaAttachment } from "$shared/types";

  interface Props {
    mediaId: string;
    attachments: readonly MediaAttachment[];
    /** Fired after a mutation so the parent can re-fetch the card. */
    onChanged?: () => void;
  }

  let { mediaId, attachments, onChanged }: Props = $props();

  const t = $derived(i18n.t.detail);
  let fileInput = $state<HTMLInputElement | null>(null);
  let uploading = $state(false);
  let dragOver = $state(false);
  let busyId = $state<string | null>(null);

  const isBookFile = (name: string) => BOOK_FILE_RE.test(name);
  const isArchive = (name: string) => ARCHIVE_RE.test(name);
  const isDocument = (name: string) => DOCUMENT_RE.test(name);

  function iconFor(name: string) {
    if (isBookFile(name)) return BookOpen;
    if (isArchive(name)) return Archive;
    if (isDocument(name)) return FileText;
    return Paperclip;
  }

  function formatSize(bytes: number): string {
    return t.filesSize(bytes);
  }

  async function upload(file: File) {
    if (uploading) return;
    uploading = true;
    try {
      await attachMediaFile(mediaId, file);
      showToast({ title: t.filesAttached, description: i18n.t.toast.descCreated });
      onChanged?.();
    } catch (error) {
      showToast({ title: t.filesAttachFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    } finally {
      uploading = false;
    }
  }

  function onPick(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (file) void upload(file);
    input.value = "";
  }

  function onDrop(event: DragEvent) {
    event.preventDefault();
    dragOver = false;
    const file = event.dataTransfer?.files?.[0];
    if (file) void upload(file);
  }

  async function open(attachment: MediaAttachment) {
    if (busyId) return;
    busyId = attachment.id;
    try {
      await openMediaFile(mediaId, attachment.id);
      showToast({ title: t.filesOpened, description: i18n.t.toast.descOpened });
    } catch (error) {
      showToast({ title: t.filesOpenFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    } finally {
      busyId = null;
    }
  }

  function download(attachment: MediaAttachment) {
    // The browser handles the transfer: the server sets Content-Disposition with the
    // original file name, so an anchor with the download attribute is the whole flow.
    const anchor = document.createElement("a");
    anchor.href = mediaFileDownloadUrl(mediaId, attachment.id);
    anchor.download = attachment.fileName;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }

  async function remove(attachment: MediaAttachment) {
    if (busyId) return;
    if (!window.confirm(t.filesDeleteConfirm(attachment.fileName))) return;
    busyId = attachment.id;
    try {
      await detachMediaFile(mediaId, attachment.id);
      showToast({ title: t.filesDeleted, description: i18n.t.toast.descDeleted });
      onChanged?.();
    } catch (error) {
      showToast({ title: t.filesDeleteFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    } finally {
      busyId = null;
    }
  }
</script>

<section
  aria-label={t.filesTitle}
  class="space-y-3 rounded-xl border bg-[var(--color-panel-line)] p-5 shadow-sm {dragOver
    ? 'border-indigo-500/40'
    : 'border-white/[0.06]'}"
  ondragover={(event) => {
    event.preventDefault();
    dragOver = true;
  }}
  ondragleave={() => (dragOver = false)}
  ondrop={onDrop}
>
  <!-- Section header: same anatomy as LinkedSourcesSection -->
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-2">
      <Paperclip size={16} class="text-accent-soft shrink-0" aria-hidden="true" />
      <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">{t.filesTitle}</h2>
      {#if attachments.length > 0}
        <span class="rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-bold text-slate-300">
          {attachments.length}
        </span>
      {/if}
    </div>

    <button
      type="button"
      class="tap hover:border-accent hover:bg-accent/20 grid size-8 cursor-pointer place-items-center rounded-lg border border-white/10 bg-white/5 text-slate-300 transition hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
      onclick={() => fileInput?.click()}
      disabled={uploading}
      title={t.filesAttach}
      aria-label={t.filesAttach}
    >
      {#if uploading}
        <LoaderCircle size={15} class="animate-spin" aria-hidden="true" />
      {:else}
        <Plus size={16} aria-hidden="true" />
      {/if}
    </button>
  </div>
  <input type="file" class="hidden" bind:this={fileInput} onchange={onPick} />

  {#if attachments.length === 0}
    <p class="text-muted text-sm">{t.filesEmpty}</p>
  {:else}
    <ul class="space-y-2" class:opacity-60={dragOver}>
      {#each attachments as attachment (attachment.id)}
        {@const Icon = iconFor(attachment.fileName)}
        <li
          class="group flex items-center justify-between gap-3 rounded-xl border border-white/5 bg-[#151a26] p-3 transition hover:border-white/10"
        >
          <div class="flex min-w-0 items-center gap-3">
            <Icon size={16} class="text-accent-soft shrink-0" aria-hidden="true" />
            <div class="min-w-0">
              <p class="truncate text-xs font-medium text-slate-200" title={attachment.fileName}>
                {attachment.fileName}
              </p>
              <p class="text-[11px] text-slate-400">{formatSize(attachment.fileSizeBytes)}</p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-1.5">
            <!-- Compact icon row: open in a system app, browser download, delete. -->
            <button
              type="button"
              class="tap flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/5 bg-white/[0.03] text-slate-400 transition hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
              onclick={() => open(attachment)}
              disabled={busyId === attachment.id}
              title={t.filesOpen}
              aria-label={t.filesOpen}
            >
              {#if busyId === attachment.id}
                <LoaderCircle size={14} class="animate-spin" aria-hidden="true" />
              {:else}
                <Eye size={14} aria-hidden="true" />
              {/if}
            </button>
            <button
              type="button"
              class="tap flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/5 bg-white/[0.03] text-slate-400 transition hover:bg-white/10 hover:text-white"
              onclick={() => download(attachment)}
              title={t.filesDownload}
              aria-label={t.filesDownload}
            >
              <Download size={14} aria-hidden="true" />
            </button>
            <button
              type="button"
              class="tap flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/5 bg-white/[0.03] text-rose-400 transition hover:border-rose-500/20 hover:bg-rose-500/10 disabled:cursor-not-allowed disabled:opacity-50"
              onclick={() => remove(attachment)}
              disabled={busyId === attachment.id}
              title={t.filesDelete}
              aria-label={t.filesDelete}
            >
              <Trash2 size={14} aria-hidden="true" />
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {/if}

  {#if dragOver}
    <p class="text-xs font-medium text-[var(--color-accent-soft)]">{t.filesDropHere}</p>
  {/if}
</section>
