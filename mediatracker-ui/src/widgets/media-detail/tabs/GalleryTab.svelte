<script module lang="ts">
  const FILENAME_EXT_RE = /\.[a-z0-9]+$/i;
</script>

<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Image, LoaderCircle, Trash2, Upload } from "$shared/ui/Icons";
  import { openLightbox } from "$shared/ui/lightbox.svelte";
  import { openContextMenu } from "$shared/ui/contextMenu.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import {
    deleteGalleryImage,
    errorMessage,
    revealInExplorer,
    setGalleryAsCover,
    uploadGalleryImage,
  } from "$shared/api/api";
  import type { MediaGalleryItem } from "$shared/types";

  interface Props {
    mediaId: string;
    gallery: readonly MediaGalleryItem[];
    /** Fired after a mutation so the parent can re-fetch the card (and the tab counter). */
    onChanged?: () => void;
  }

  let { mediaId, gallery, onChanged }: Props = $props();

  const t = $derived(i18n.t.detail);
  let fileInput = $state<HTMLInputElement | null>(null);
  let uploading = $state(false);
  let deletingId = $state<string | null>(null);

  /**
   * Ctrl+V screenshots: a paste event carries the image as a ClipboardItem blob, so the whole
   * flow is "grab the first image item, upload it as-is". Listener sits on window and is
   * registered only while the tab is mounted.
   */
  function handlePaste(event: ClipboardEvent) {
    const items = event.clipboardData?.items;
    if (!items) return;

    for (const item of items) {
      if (!item.type.startsWith("image/")) continue;

      const blob = item.getAsFile();
      if (blob) {
        event.preventDefault();
        void upload(blob);
      }
      return;
    }
  }

  $effect(() => {
    window.addEventListener("paste", handlePaste);
    return () => window.removeEventListener("paste", handlePaste);
  });

  async function upload(image: Blob, title?: string) {
    if (uploading) return;
    uploading = true;
    try {
      await uploadGalleryImage(mediaId, image, title);
      showToast({ title: t.galleryScreenshotAdded, description: i18n.t.toast.descCreated });
      onChanged?.();
    } catch (error) {
      showToast({ title: t.galleryUploadFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    } finally {
      uploading = false;
    }
  }

  function onPick(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (file) void upload(file, file.name);
    input.value = "";
  }

  async function remove(entry: MediaGalleryItem) {
    if (deletingId) return;
    if (!window.confirm(t.galleryDeleteConfirm)) return;
    deletingId = entry.id;
    try {
      await deleteGalleryImage(mediaId, entry.id);
      showToast({ title: t.galleryDeleted, description: i18n.t.toast.descDeleted });
      onChanged?.();
    } catch (error) {
      showToast({ title: t.galleryDeleteFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    } finally {
      deletingId = null;
    }
  }

  /**
   * Right-click menu on a gallery card. Every action routes through the same endpoints the
   * rest of the UI uses; clipboard writes go through the async Clipboard API and only report
   * success after the browser actually accepted the payload.
   */
  function handleImageContextMenu(event: MouseEvent, entry: MediaGalleryItem) {
    event.preventDefault();
    openContextMenu(event.clientX, event.clientY, [
      {
        id: "view",
        label: t.galleryViewFull,
        icon: "browser",
        action: () => openLightbox(entry.originalUrl),
      },
      {
        id: "reveal",
        label: t.galleryReveal,
        icon: "folder",
        action: () => void reveal(entry),
      },
      {
        id: "copy-image",
        label: t.galleryCopyImage,
        icon: "copy",
        action: () => void copyImage(entry),
      },
      {
        id: "copy-url",
        label: t.galleryCopyUrl,
        icon: "link",
        action: () => void copyUrl(entry),
      },
      {
        id: "download",
        label: t.galleryDownloadImage,
        icon: "download",
        action: () => downloadImage(entry),
      },
      {
        id: "set-cover",
        label: t.gallerySetCover,
        icon: "image",
        action: () => void setCover(entry),
      },
      { id: "sep", kind: "separator" },
      {
        id: "delete",
        label: t.galleryDelete,
        icon: "delete",
        kind: "danger",
        action: () => void remove(entry),
      },
    ]);
  }

  /** The screenshots live on the server: reveal the owning folder in the platform file manager. */
  async function reveal(entry: MediaGalleryItem) {
    try {
      await revealInExplorer(`media/${mediaId}/gallery/${entry.id}`);
    } catch (error) {
      showToast({ title: t.galleryRevealFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    }
  }

  async function copyImage(entry: MediaGalleryItem) {
    try {
      const response = await fetch(entry.originalUrl);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      const pngBlob = blob.type === "image/png" ? blob : await toPng(blob);
      await navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob })]);
      showToast({ title: t.galleryImageCopied, description: i18n.t.toast.descCopied });
    } catch (error) {
      showToast({ title: t.galleryCopyFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    }
  }

  /**
   * Chromium only accepts image/png on the clipboard write path, so a webp screenshot is
   * re-encoded through a canvas before it lands in the buffer.
   */
  function toPng(blob: Blob): Promise<Blob> {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(blob);
      const image = document.createElement("img");
      image.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = image.naturalWidth;
        canvas.height = image.naturalHeight;
        const ctx = canvas.getContext("2d");
        if (!ctx) {
          URL.revokeObjectURL(url);
          reject(new Error("Canvas 2d context unavailable"));
          return;
        }
        ctx.drawImage(image, 0, 0);
        URL.revokeObjectURL(url);
        canvas.toBlob(
          (png) => (png ? resolve(png) : reject(new Error("Canvas toBlob failed"))),
          "image/png",
        );
      };
      image.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error("Image decode failed"));
      };
      image.src = url;
    });
  }

  async function copyUrl(entry: MediaGalleryItem) {
    try {
      await navigator.clipboard.writeText(entry.originalUrl);
      showToast({ title: t.galleryUrlCopied, description: i18n.t.toast.descCopied });
    } catch (error) {
      showToast({ title: t.galleryCopyFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    }
  }

  function downloadImage(entry: MediaGalleryItem) {
    const name =
      entry.title && FILENAME_EXT_RE.test(entry.title)
        ? entry.title
        : `${entry.title ?? "screenshot"}.webp`;
    const anchor = document.createElement("a");
    anchor.href = entry.originalUrl;
    anchor.download = name;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }

  async function setCover(entry: MediaGalleryItem) {
    try {
      await setGalleryAsCover(mediaId, entry.id);
      showToast({ title: t.gallerySetCoverDone, description: i18n.t.toast.descSaved });
      // The sidebar caches the poster by URL: a refetch brings the new cover cache-buster along.
      onChanged?.();
    } catch (error) {
      showToast({ title: t.gallerySetCoverFailed, description: errorMessage(error), type: "error", durationMs: 5000 });
    }
  }
</script>

<div class="space-y-4">
  <div class="flex flex-wrap items-center justify-between gap-2">
    <p class="text-muted text-xs">{t.galleryPasteHint}</p>
    <button
      type="button"
      class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-white/10 bg-white/[0.04] px-2.5 py-1 text-xs font-medium text-slate-300 transition hover:border-indigo-500/40 hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
      onclick={() => fileInput?.click()}
      disabled={uploading}
    >
      {#if uploading}
        <LoaderCircle size={14} class="animate-spin" aria-hidden="true" />
        {t.galleryUploading}
      {:else}
        <Upload size={14} aria-hidden="true" />
        {t.galleryUpload}
      {/if}
    </button>
    <input type="file" accept="image/*" class="hidden" bind:this={fileInput} onchange={onPick} />
  </div>

  {#if gallery.length === 0}
    <div
      class="text-muted flex flex-col items-center gap-2 rounded-xl border border-dashed border-white/10 bg-[var(--color-panel-line)] p-10 text-sm"
    >
      <Image size={28} aria-hidden="true" />
      <p>{t.galleryEmpty}</p>
    </div>
  {:else}
    <!-- Adaptive grid: 2 columns on a phone up to 4 on a wide screen; cards keep a 16:9
         ratio so mixed portrait/landscape screenshots line up into even rows. -->
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
      {#each gallery as entry (entry.id)}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <!-- The card wrapper carries the contextmenu handler; the interactive semantics
             belong to the two buttons inside (lightbox opener + delete). -->
        <div
          class="group relative aspect-video overflow-hidden rounded-xl border border-white/[0.06] bg-black/20"
          title={entry.title ?? undefined}
          oncontextmenu={(event) => handleImageContextMenu(event, entry)}
        >
          <!-- The card itself is a button (a11y-clean lightbox opener); the delete control
               is a sibling overlay so no interactive element nests inside another. -->
          <button
            type="button"
            class="block h-full w-full cursor-pointer"
            onclick={() => openLightbox(entry.originalUrl)}
          >
            <img
              src={entry.thumbUrl}
              alt={entry.title ?? "Screenshot"}
              loading="lazy"
              class="h-full w-full object-cover transition group-hover:scale-[1.03]"
            />
          </button>
          <button
            type="button"
            class="absolute top-2 right-2 cursor-pointer rounded-lg border border-white/10 bg-black/70 p-1.5 text-slate-200 opacity-0 transition group-hover:opacity-100 hover:border-red-500/50 hover:text-red-400 disabled:cursor-not-allowed"
            onclick={() => void remove(entry)}
            disabled={deletingId === entry.id}
            aria-label={t.galleryDeleteConfirm}
          >
            {#if deletingId === entry.id}
              <LoaderCircle size={14} class="animate-spin" aria-hidden="true" />
            {:else}
              <Trash2 size={14} aria-hidden="true" />
            {/if}
          </button>
        </div>
      {/each}
    </div>
  {/if}
</div>
