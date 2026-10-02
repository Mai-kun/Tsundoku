<script lang="ts">
    import type { Snippet } from "svelte";
    import ImageIcon from "lucide-svelte/icons/image";
    import LoaderCircle from "lucide-svelte/icons/loader-circle";
    import X from "lucide-svelte/icons/x";
    import { errorMessage, translateText } from "$lib/api";
    import Modal from "$lib/components/common/Modal.svelte";
    import DetailHeader, {
        type RatingBadge,
    } from "$lib/components/media/details/DetailHeader.svelte";
    import { i18n } from "$lib/i18n/index.svelte";
    import { showToast } from "$lib/stores/toast.svelte";
    import type { ExternalMedia, SearchMediaType } from "$lib/types";
    import { loadExternalDetails } from "$lib/utils/externalDetailPrefetch";
    import { sourceBadgeClasses } from "../mediaLabels";

    interface Props {
        /** The search hit. Rendered immediately, then enriched by the full details. */
        item: ExternalMedia;
        /** Aggregator category. `anime` is a search-only type, so it comes from the caller. */
        type: SearchMediaType;
        onClose: () => void;
        /** Add-to-library / open-in-library buttons, owned by the search modal. */
        actions: Snippet;
    }

    let { item, type, onClose, actions }: Props = $props();

    let details = $state<ExternalMedia | null>(null);
    let loading = $state(false);
    let loadError = $state<unknown>(null);

    let synopsisExpanded = $state(false);
    let isSynopsisTranslated = $state(false);
    let translatingSynopsis = $state(false);
    let translatedSynopsis = $state<string | null>(null);

    // Details win field by field: the search hit can carry a cover or title the
    // aggregator knows better, and the reverse is just as common.
    let media = $derived<ExternalMedia>({ ...item, ...stripEmpty(details) });
    let originalTitle = $derived(
        media.romajiTitle ?? media.originalTitle ?? null,
    );
    let synopsisText = $derived(media.description?.trim() ?? "");
    let synopsisExpandable = $derived(synopsisText.length > 280);

    function stripEmpty(source: ExternalMedia | null): Partial<ExternalMedia> {
        if (!source) return {};
        return Object.fromEntries(
            Object.entries(source).filter(
                ([, value]) =>
                    value !== null &&
                    value !== undefined &&
                    value !== "" &&
                    !(Array.isArray(value) && value.length === 0),
            ),
        );
    }

    function typeLabel(): string {
        return type === "anime"
            ? i18n.t.navigation.anime
            : i18n.t.types[type];
    }

    let ratings = $derived.by<RatingBadge[]>(() => {
        const list: RatingBadge[] = [];
        const seen = new Set<string>();

        for (const r of media.ratings ?? []) {
            const source = (r.source || "").trim();
            if (!source) continue;
            const key = source.toLowerCase();
            if (seen.has(key)) continue;
            seen.add(key);
            list.push({
                source,
                score:
                    typeof r.rating === "number" && r.rating > 0
                        ? r.rating
                        : null,
                votes: r.votes ?? null,
            });
        }

        // Sources that report a single score without a ratings array still deserve a
        // badge, otherwise the header shows no rating at all.
        if (
            list.length === 0 &&
            media.rating &&
            media.rating > 0 &&
            media.externalSource
        ) {
            list.push({
                source: media.externalSource,
                score: media.rating,
                votes: media.ratingVotes ?? null,
            });
        }

        return list;
    });

    let tags = $derived.by<string[]>(() => {
        const list = [typeLabel()];
        const formats = i18n.t.detail.mangaFormats as Record<string, string>;
        if (media.mangaFormat) list.push(formats[media.mangaFormat] ?? "");
        if (media.platform) list.push(media.platform);
        if (media.studio) list.push(media.studio);
        if (media.author) list.push(media.author);
        return [...new Set(list.filter(Boolean))];
    });

    function formatDate(value?: string | null, year?: number | null): string {
        if (value) return value;
        if (year && year > 0)
            return i18n.current === "ru" ? `${year} РіРѕРґ` : `${year}`;
        return i18n.t.detailModal.dateEmpty;
    }

    function countLabel(): string {
        switch (type) {
            case "manga":
                return i18n.t.detail.chaptersLabel;
            case "book":
                return i18n.t.detail.pagesLabel;
            case "game":
                return i18n.t.detail.hoursLabel;
            default:
                return i18n.t.detail.episodesLabel;
        }
    }

    function countValue(): string | null {
        if (type === "manga") {
            const chapters = media.chapters ?? media.totalCount ?? null;
            const volumes = media.volumes ?? null;
            if (chapters === null && volumes === null) return null;
            return [
                chapters !== null ? `${chapters}` : null,
                volumes !== null
                    ? `${i18n.t.detail.volumesLabel}: ${volumes}`
                    : null,
            ]
                .filter(Boolean)
                .join(" В· ");
        }

        if (type === "game") {
            return media.totalCount !== null && media.totalCount !== undefined
                ? `${media.totalCount}`
                : null;
        }

        const total = media.totalCount ?? media.episodes?.length ?? null;
        return total !== null ? `${total}` : null;
    }

    /**
     * Release status arrives as a raw provider string ("RELEASING", "Current",
     * "Р’ СЌС„РёСЂРµ"), so it is matched by substring rather than parsed.
     */
    function releaseStatusLabel(): string {
        const raw = media.releaseStatus?.trim().toUpperCase();
        if (!raw) return i18n.t.detailModal.valueEmpty;

        const statuses = i18n.t.detail.releaseStatuses as Record<string, string>;
        if (raw.includes("CANCEL")) return statuses.cancelled;
        if (raw.includes("HIATUS") || raw.includes("РџРђРЈР—"))
            return statuses.hiatus;
        if (
            raw.includes("NOT_YET") ||
            raw.includes("UPCOMING") ||
            raw.includes("ANNOUNCE") ||
            raw.includes("РЎРљРћР Рћ")
        )
            return statuses.notYetReleased;
        if (
            raw.includes("RELEASING") ||
            raw.includes("CURRENT") ||
            raw.includes("ONGOING") ||
            raw.includes("Р’Р«РџРЈРЎРљ") ||
            raw.includes("Р­Р¤РР ")
        )
            return statuses.releasing;
        return statuses.finished;
    }

    /** Providers may send a list or a comma-joined string; both show the same. */
    function list(value?: string[] | string | null): string[] {
        if (Array.isArray(value)) return value;
        return value ? value.split(",").map((part) => part.trim()) : [];
    }

    let specRows = $derived.by<{ label: string; value: string }[]>(() => {
        const empty = i18n.t.detail.previewModal.noData;
        const rows: { label: string; value: string }[] = [];

        if (type === "game") {
            rows.push({
                label: i18n.t.detail.releaseDateLabel,
                value: formatDate(media.releaseDate, media.releaseYear),
            });
        } else {
            rows.push({
                label: i18n.t.detail.startDateLabel,
                value: formatDate(media.releaseDate, media.releaseYear),
            });
            rows.push({
                label: i18n.t.detail.endDateLabel,
                value: media.endDate
                    ? formatDate(media.endDate, null)
                    : i18n.t.detailModal.dateEmpty,
            });
        }

        rows.push({
            label: i18n.t.status.label,
            value: releaseStatusLabel(),
        });

        const count = countValue();
        if (count) rows.push({ label: countLabel(), value: count });

        if (media.runtimeMinutes && media.runtimeMinutes > 0) {
            rows.push({
                label: i18n.t.detail.durationLabel,
                value:
                    type === "movie"
                        ? i18n.t.card.movie(media.runtimeMinutes)
                        : `${media.runtimeMinutes} ${i18n.t.detail.minPerEp}`,
            });
        }

        if (media.studio) {
            rows.push({
                label: i18n.t.detailModal.studio,
                value: media.studio,
            });
        }
        if (media.author) {
            rows.push({
                label: i18n.t.detailModal.author,
                value: media.author,
            });
        }
        if (media.platform && type !== "game") {
            rows.push({
                label: i18n.t.detailModal.platform,
                value: media.platform,
            });
        }

        rows.push({
            label: i18n.t.detail.genresLabel,
            value: list(media.genres).join(", ") || empty,
        });
        rows.push({
            label: i18n.t.detail.tagsLabel,
            value: list(media.tags).join(", ") || empty,
        });

        rows.push({
            label: i18n.t.detail.source,
            value: media.externalSource || empty,
        });

        return rows;
    });

    async function toggleTranslateSynopsis() {
        if (!synopsisText || translatingSynopsis) return;

        if (isSynopsisTranslated) {
            isSynopsisTranslated = false;
            return;
        }

        if (translatedSynopsis) {
            isSynopsisTranslated = true;
            return;
        }

        translatingSynopsis = true;
        try {
            const target = i18n.current === "en" ? "en" : "ru";
            const res = await translateText(synopsisText, target);
            if (res?.translatedText) {
                translatedSynopsis = res.translatedText;
                isSynopsisTranslated = true;
            }
        } catch (error) {
            showToast(errorMessage(error), "error");
        } finally {
            translatingSynopsis = false;
        }
    }

    $effect(() => {
        // Re-runs when the opened hit changes; a late response must not overwrite the
        // title the user is actually looking at.
        const key = `${type}:${item.externalSource ?? ""}:${item.externalId}`;
        let active = true;

        loading = true;
        loadError = null;
        synopsisExpanded = false;
        isSynopsisTranslated = false;
        translatedSynopsis = null;

        loadExternalDetails(type, item)
            .then((loaded) => {
                if (active) details = loaded;
            })
            .catch((error) => {
                if (active) loadError = error;
            })
            .finally(() => {
                if (active) loading = false;
            });

        return () => {
            active = false;
        };
    });
</script>

<Modal isOpen={true} {onClose} labelledBy="external-preview-title" size="lg">
    <div class="flex max-h-[88vh] flex-col">
        <button
            type="button"
            class="tap absolute right-4 top-4 z-10 grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink"
            aria-label={i18n.t.common.close}
            onclick={onClose}
        >
            <X size={18} aria-hidden="true" />
        </button>

        <div class="min-h-0 flex-1 overflow-y-auto px-6 pb-5 pt-5">
            {#if loading && !details}
                <div
                    class="flex items-center justify-center gap-2 py-16 text-sm text-muted"
                >
                    <LoaderCircle
                        size={16}
                        class="animate-spin"
                        aria-hidden="true"
                    />
                    {i18n.t.common.loading}
                </div>
            {:else}
                <div class="flex flex-col gap-6 lg:flex-row">
                    <!-- Left column: poster + read-only characteristics. Status,
                         progress and actions stay out: nothing here is in the library. -->
                    <aside class="w-full shrink-0 space-y-4 lg:w-64">
                        <div
                            class="mx-auto aspect-[2/3] w-40 overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] shadow-lg lg:w-full"
                        >
                            {#if media.coverUrl}
                                <img
                                    src={media.coverUrl}
                                    alt={media.title}
                                    class="h-full w-full object-cover"
                                    decoding="async"
                                />
                            {:else}
                                <div
                                    class="grid h-full place-items-center text-muted"
                                >
                                    <ImageIcon
                                        size={32}
                                        stroke-width={1.25}
                                        aria-hidden="true"
                                    />
                                </div>
                            {/if}
                        </div>

                        <div>
                            <h2
                                class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200"
                            >
                                {i18n.t.detail.detailsTitle}
                            </h2>
                            <div class="panel">
                                <dl class="divide-y divide-white/5 text-sm">
                                    {#each specRows as row, idx (`${row.label}-${idx}`)}
                                        <div
                                            class="flex items-start justify-between gap-3 py-2.5 first:pt-0 last:pb-0"
                                        >
                                            <dt
                                                class="shrink-0 text-xs font-medium text-muted"
                                            >
                                                {row.label}
                                            </dt>
                                            <dd
                                                class="text-right text-xs font-medium text-white"
                                            >
                                                {row.value}
                                            </dd>
                                        </div>
                                    {/each}
                                </dl>
                            </div>
                        </div>
                    </aside>

                    <div class="min-w-0 flex-1 space-y-5">
                        <DetailHeader
                            title={media.title}
                            {originalTitle}
                            {tags}
                            {ratings}
                            {sourceBadgeClasses}
                            {synopsisText}
                            {synopsisExpanded}
                            {synopsisExpandable}
                            synopsisTranslated={isSynopsisTranslated}
                            {translatedSynopsis}
                            {translatingSynopsis}
                            onToggleTranslate={toggleTranslateSynopsis}
                            onToggleExpand={() =>
                                (synopsisExpanded = !synopsisExpanded)}
                        />

                        {#if loadError}
                            <p class="text-xs text-rose-300" role="alert">
                                {errorMessage(loadError)}
                            </p>
                        {/if}

                        {#if media.episodes && media.episodes.length > 0}
                            <section>
                                <h3
                                    class="text-xs font-semibold uppercase tracking-wider text-muted"
                                >
                                    {i18n.t.detail.previewModal.episodesList(
                                        media.episodes.length,
                                    )}
                                </h3>
                                <ul
                                    class="mt-2 max-h-56 space-y-1.5 overflow-y-auto pr-1"
                                >
                                    {#each media.episodes as ep (ep.number)}
                                        <li
                                            class="flex items-center justify-between gap-3 rounded bg-elevated/50 px-2.5 py-1.5 text-xs text-ink"
                                        >
                                            <span class="font-medium text-muted"
                                                >E{ep.number}</span
                                            >
                                            <span class="truncate text-right">
                                                {ep.title ||
                                                    i18n.t.detail.episodeTitle(
                                                        ep.number,
                                                    )}
                                            </span>
                                        </li>
                                    {/each}
                                </ul>
                            </section>
                        {/if}
                    </div>
                </div>
            {/if}
        </div>

        <!-- Actions live outside the scroller: a long episode list must never
             push "add to library" off the bottom of the panel. -->
        {#if !(loading && !details)}
            <div
                class="flex shrink-0 flex-wrap items-center gap-2 border-t border-white/[0.07] px-6 py-4"
            >
                {@render actions()}
            </div>
        {/if}
    </div>
</Modal>
