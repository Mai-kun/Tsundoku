<script lang="ts">
    import ImageIcon from "lucide-svelte/icons/image";
    import LoaderCircle from "lucide-svelte/icons/loader-circle";
    import Plus from "lucide-svelte/icons/plus";
    import Star from "lucide-svelte/icons/star";
    import X from "lucide-svelte/icons/x";
    import Modal from "$lib/components/common/Modal.svelte";
    import { i18n } from "$lib/i18n/index.svelte";
    import { MEDIA_STATUS, type MediaStatus } from "$lib/types";
    import { formatMediaDisplayType, statusLabel } from "../detailFormatters";
    import type { RatingBadge, RelatedEntry } from "../detailTypes";

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

    let {
        item,
        badges,
        loading,
        adding,
        status,
        onStatusChange,
        onAdd,
        onClose,
    }: Props = $props();

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
        !!item &&
            (item.type === "manga" ||
                item.format === "NOVEL" ||
                item.format === "MANGA"),
    );
</script>
{#if item}
    <Modal isOpen onClose={onClose} labelledBy="related-preview-title">
        <div class="flex max-h-[85vh] flex-col p-6">
            <h2 id="related-preview-title" class="sr-only">{item.title}</h2>
            <button
                type="button"
                class="tap absolute right-4 top-4 z-10 grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink cursor-pointer"
                title={i18n.t.common.close}
                aria-label={i18n.t.common.close}
                onclick={onClose}
            >
                <X size={18} aria-hidden="true" />
            </button>

            <div class="overflow-y-auto pr-1">
                <div class="flex flex-col gap-5 sm:flex-row">
                    <div
                        class="mx-auto aspect-[2/3] w-40 shrink-0 overflow-hidden rounded-lg bg-canvas sm:mx-0"
                    >
                        {#if item.coverUrl}
                            <img
                                src={item.coverUrl}
                                alt={item.title}
                                class="h-full w-full object-cover"
                            />
                        {:else}
                            <div class="grid h-full place-items-center text-muted">
                                <ImageIcon
                                    size={32}
                                    stroke-width={1.25}
                                    aria-hidden="true"
                                />
                            </div>
                        {/if}
                    </div>

                    <div class="min-w-0 flex-1 space-y-3">
                        <div class="flex flex-wrap items-center gap-2">
                            <span
                                class="rounded-full bg-elevated px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-accent-soft"
                            >
                                {formatMediaDisplayType(item)}
                            </span>
                            {#if item.relationType}
                                <span
                                    class="rounded-full bg-accent/20 border border-accent/40 px-2.5 py-0.5 text-[11px] font-semibold text-accent-soft"
                                >
                                    {item.relationType}
                                </span>
                            {/if}
                            <span
                                class="rounded-full border border-white/10 bg-field px-2.5 py-0.5 text-[11px] font-semibold text-muted"
                            >
                                AniList
                            </span>
                        </div>

                        <div>
                            <h3 class="mt-1 text-lg font-bold text-ink">{item.title}</h3>
                            {#if item.originalTitle}
                                <p class="text-xs text-muted">{item.originalTitle}</p>
                            {/if}
                        </div>

                        {#if badges.length > 0}
                            <div class="flex flex-wrap items-center gap-2">
                                {#each badges as r (r.source)}
                                    <div
                                        class="inline-flex items-center gap-1 rounded-md border border-white/10 bg-field px-2 py-0.5 text-xs"
                                    >
                                        <span class="font-medium text-muted"
                                            >{r.source}:</span
                                        >
                                        {#if r.score !== null && r.score > 0}
                                            <span
                                                class="flex items-center gap-0.5 font-bold text-star"
                                            >
                                                <Star
                                                    size={11}
                                                    fill="currentColor"
                                                    aria-hidden="true"
                                                />
                                                {r.score.toFixed(1)}
                                            </span>
                                        {:else if loading}
                                            <LoaderCircle
                                                size={12}
                                                class="animate-spin text-muted"
                                                role="status"
                                                aria-label={i18n.t.common.loading}
                                            />
                                        {:else}
                                            <span class="text-xs text-muted">—</span>
                                        {/if}
                                    </div>
                                {/each}
                            </div>
                        {:else}
                            <div
                                class="inline-flex items-center gap-1 rounded-md border border-white/10 bg-field px-2 py-0.5 text-xs text-muted"
                            >
                                <Star size={11} aria-hidden="true" />
                                <span>{i18n.t.detail.previewModal.noRatings}</span>
                            </div>
                        {/if}

                        <div class="space-y-1 text-xs text-muted">
                            <div>
                                <span class="font-medium text-ink"
                                    >{i18n.t.detail.previewModal.year}:</span
                                >
                                {item.year ?? i18n.t.detail.previewModal.noData}
                            </div>
                            {#if isMangaLike}
                                <div>
                                    <span class="font-medium text-ink"
                                        >{i18n.t.detail.previewModal.author}:</span
                                    >
                                    {item.author ?? i18n.t.detail.previewModal.noData}
                                </div>
                            {:else}
                                <div>
                                    <span class="font-medium text-ink"
                                        >{i18n.t.detail.previewModal.studio}:</span
                                    >
                                    {item.studio ?? i18n.t.detail.previewModal.noData}
                                </div>
                            {/if}
                            <div>
                                <span class="font-medium text-ink"
                                    >{i18n.t.detail.previewModal.count}:</span
                                >
                                {#if count}
                                    {count.value}
                                    {count.unit}
                                {:else}
                                    {i18n.t.detail.previewModal.noData}
                                {/if}
                            </div>
                        </div>

                        <div class="pt-2 flex flex-wrap items-center gap-3">
                            <div class="flex items-center gap-2">
                                <label
                                    for="preview-status"
                                    class="text-xs font-medium text-muted"
                                >
                                    {i18n.t.detail.previewModal.initialStatus}:
                                </label>
                                <select
                                    id="preview-status"
                                    value={status}
                                    onchange={(e) =>
                                        onStatusChange(
                                            Number(
                                                e.currentTarget.value,
                                            ) as MediaStatus,
                                        )}
                                    class="rounded-md border border-white/10 bg-field px-2.5 py-1.5 text-xs font-medium text-ink outline-none focus:border-accent"
                                >
                                    {#each statusOptions as opt (opt)}
                                        <option value={opt}
                                            >{statusLabel(opt)}</option
                                        >
                                    {/each}
                                </select>
                            </div>

                            <button
                                type="button"
                                class="inline-flex items-center gap-2 rounded-lg border border-white/10 bg-field px-4 py-2 text-xs font-semibold text-ink transition hover:border-accent hover:bg-panel disabled:cursor-wait disabled:opacity-70 cursor-pointer"
                                disabled={adding}
                                onclick={() => onAdd(status)}
                            >
                                {#if adding}
                                    <div
                                        class="h-4 w-4 animate-spin rounded-full border-2 border-accent border-t-transparent"
                                    ></div>
                                    <span
                                        >{i18n.t.detail.previewModal
                                            .addingToLibrary}</span
                                    >
                                {:else}
                                    <Plus size={16} aria-hidden="true" />
                                    <span
                                        >{i18n.t.detail.previewModal
                                            .addToLibrary}</span
                                    >
                                {/if}
                            </button>
                        </div>
                    </div>
                </div>

                <div class="mt-5 border-t border-border pt-4">
                    <h4
                        class="text-xs font-semibold uppercase tracking-wider text-muted"
                    >
                        {i18n.t.detail.previewModal.description}
                    </h4>
                    {#if item.description}
                        <p
                            class="mt-1.5 whitespace-pre-line text-xs leading-relaxed text-muted"
                        >
                            {item.description}
                        </p>
                    {:else}
                        <p class="mt-1.5 text-xs italic text-muted/70">
                            {i18n.t.detail.previewModal.noDescription}
                        </p>
                    {/if}
                </div>
            </div>
        </div>
    </Modal>
{/if}
