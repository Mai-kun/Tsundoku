<script lang="ts">
  import { Image as ImageIcon, LoaderCircle, Plus, Star, X } from "$shared/ui/Icons";
  import Modal from "$shared/ui/Modal.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, type MediaStatus } from "$shared/types";
  import { formatMediaDisplayType, statusLabel } from "$widgets/media-detail/detailFormatters";
  import type { RatingBadge, RelatedEntry } from "$widgets/media-detail/detailTypes";

  interface Props {
    /** Null when no external entry is being previewed. */
    item: RelatedEntry | null;
    badges: readonly RatingBadge[];
    loading: boolean;
    adding: boolean;
    status: MediaStatus;
    onStatusChange: (status: MediaStatus) => void;
    onAdd: (status: MediaStatus) => void;
    onClose: () => void;
  }

  let { item, badges, loading, adding, status, onStatusChange, onAdd, onClose }: Props = $props();

  const statusOptions: readonly MediaStatus[] = [
    MEDIA_STATUS.planned,
    MEDIA_STATUS.inProgress,
    MEDIA_STATUS.completed,
    MEDIA_STATUS.onHold,
    MEDIA_STATUS.dropped,
  ];

  /** Episodes / chapters / volumes: whichever the provider reported, in that order. */
  const count = $derived.by(() => {
    if (!item) return null;
    if (item.episodes) {
      return { value: item.episodes, unit: i18n.t.searchModal.countUnits.anime };
    }
    if (item.chapters) {
      return { value: item.chapters, unit: i18n.t.searchModal.countUnits.manga };
    }
    if (item.volumes) {
      return { value: item.volumes, unit: i18n.t.searchModal.countUnits.manga };
    }
    return null;
  });

  const isMangaLike = $derived(
    !!item && (item.type === "manga" || item.format === "NOVEL" || item.format === "MANGA"),
  );
</script>

{#if item}
  <Modal isOpen {onClose} labelledBy="related-preview-title">
    <div class="flex max-h-[85vh] flex-col p-6">
      <h2 id="related-preview-title" class="sr-only">{item.title}</h2>
      <button
        type="button"
        class="tap text-muted hover:bg-elevated hover:text-ink absolute top-4 right-4 z-10 grid h-8 w-8 cursor-pointer place-items-center rounded-lg transition"
        title={i18n.t.common.close}
        aria-label={i18n.t.common.close}
        onclick={onClose}
      >
        <X size={18} aria-hidden="true" />
      </button>

      <div class="overflow-y-auto pr-1">
        <div class="flex flex-col gap-5 sm:flex-row">
          <div
            class="bg-canvas mx-auto aspect-[2/3] w-40 shrink-0 overflow-hidden rounded-lg sm:mx-0"
          >
            {#if item.coverUrl}
              <img
                src={item.coverUrl}
                alt={item.title}
                referrerpolicy="no-referrer"
                class="h-full w-full object-cover"
              />
            {:else}
              <div class="text-muted grid h-full place-items-center">
                <ImageIcon size={32} stroke-width={1.25} aria-hidden="true" />
              </div>
            {/if}
          </div>

          <div class="min-w-0 flex-1 space-y-3">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="bg-elevated text-accent-soft rounded-full px-2.5 py-0.5 text-[11px] font-semibold tracking-wider uppercase"
              >
                {formatMediaDisplayType(item)}
              </span>
              {#if item.relationType}
                <span
                  class="bg-accent/20 border-accent/40 text-accent-soft rounded-full border px-2.5 py-0.5 text-[11px] font-semibold"
                >
                  {item.relationType}
                </span>
              {/if}
              <span
                class="bg-field text-muted rounded-full border border-white/10 px-2.5 py-0.5 text-[11px] font-semibold"
              >
                AniList
              </span>
            </div>

            <div>
              <h3 class="text-ink mt-1 text-lg font-bold">{item.title}</h3>
              {#if item.originalTitle}
                <p class="text-muted text-xs">{item.originalTitle}</p>
              {/if}
            </div>

            {#if badges.length > 0}
              <div class="flex flex-wrap items-center gap-2">
                {#each badges as r (r.source)}
                  <div
                    class="bg-field inline-flex items-center gap-1 rounded-md border border-white/10 px-2 py-0.5 text-xs"
                  >
                    <span class="text-muted font-medium">{r.source}:</span>
                    {#if r.score !== null && r.score > 0}
                      <span class="text-star flex items-center gap-0.5 font-bold">
                        <Star size={11} fill="currentColor" aria-hidden="true" />
                        {r.score.toFixed(1)}
                      </span>
                    {:else if loading}
                      <LoaderCircle
                        size={12}
                        class="text-muted animate-spin"
                        role="status"
                        aria-label={i18n.t.common.loading}
                      />
                    {:else}
                      <span class="text-muted text-xs">—</span>
                    {/if}
                  </div>
                {/each}
              </div>
            {:else}
              <div
                class="bg-field text-muted inline-flex items-center gap-1 rounded-md border border-white/10 px-2 py-0.5 text-xs"
              >
                <Star size={11} aria-hidden="true" />
                <span>{i18n.t.detail.previewModal.noRatings}</span>
              </div>
            {/if}

            <div class="text-muted space-y-1 text-xs">
              <div>
                <span class="text-ink font-medium">{i18n.t.detail.previewModal.year}:</span>
                {item.year ?? i18n.t.detail.previewModal.noData}
              </div>
              {#if isMangaLike}
                <div>
                  <span class="text-ink font-medium">{i18n.t.detail.previewModal.author}:</span>
                  {item.author ?? i18n.t.detail.previewModal.noData}
                </div>
              {:else}
                <div>
                  <span class="text-ink font-medium">{i18n.t.detail.previewModal.studio}:</span>
                  {item.studio ?? i18n.t.detail.previewModal.noData}
                </div>
              {/if}
              <div>
                <span class="text-ink font-medium">{i18n.t.detail.previewModal.count}:</span>
                {#if count}
                  {count.value}
                  {count.unit}
                {:else}
                  {i18n.t.detail.previewModal.noData}
                {/if}
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-3 pt-2">
              <div class="flex items-center gap-2">
                <label for="preview-status" class="text-muted text-xs font-medium">
                  {i18n.t.detail.previewModal.initialStatus}:
                </label>
                <select
                  id="preview-status"
                  value={status}
                  onchange={(e) => onStatusChange(Number(e.currentTarget.value) as MediaStatus)}
                  class="bg-field text-ink focus:border-accent rounded-md border border-white/10 px-2.5 py-1.5 text-xs font-medium outline-none"
                >
                  {#each statusOptions as opt (opt)}
                    <option value={opt}>{statusLabel(opt)}</option>
                  {/each}
                </select>
              </div>

              <button
                type="button"
                class="bg-field text-ink hover:border-accent hover:bg-panel inline-flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-4 py-2 text-xs font-semibold transition disabled:cursor-wait disabled:opacity-70"
                disabled={adding}
                onclick={() => onAdd(status)}
              >
                {#if adding}
                  <div
                    class="border-accent h-4 w-4 animate-spin rounded-full border-2 border-t-transparent"
                  ></div>
                  <span>{i18n.t.detail.previewModal.addingToLibrary}</span>
                {:else}
                  <Plus size={16} aria-hidden="true" />
                  <span>{i18n.t.detail.previewModal.addToLibrary}</span>
                {/if}
              </button>
            </div>
          </div>
        </div>

        <div class="border-border mt-5 border-t pt-4">
          <h4 class="text-muted text-xs font-semibold tracking-wider uppercase">
            {i18n.t.detail.previewModal.description}
          </h4>
          {#if item.description}
            <p class="text-muted mt-1.5 text-xs leading-relaxed whitespace-pre-line">
              {item.description}
            </p>
          {:else}
            <p class="text-muted/70 mt-1.5 text-xs italic">
              {i18n.t.detail.previewModal.noDescription}
            </p>
          {/if}
        </div>
      </div>
    </div>
  </Modal>
{/if}
