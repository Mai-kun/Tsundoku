<script lang="ts">
    import { ChevronDown, LoaderCircle, Sparkles } from "$shared/ui/Icons.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import { errorMessage, getSources, getExternalDetails } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { ExternalMedia, MediaDetail, MediaType, SourceInfo } from "$shared/types";
    import { formatGenresList } from "$entities/media/model/genreLabel";

    interface Props {
        isOpen: boolean;
        busy: boolean;
        media?: MediaDetail | null;
        mediaType: MediaType | string;
        currentSource?: string | null;
        onFill: (source: string) => void;
        onClose: () => void;
    }

    let {
        isOpen,
        busy,
        media = null,
        mediaType,
        currentSource = null,
        onFill,
        onClose,
    }: Props = $props();

    let sources = $state<SourceInfo[]>([]);
    let source = $state("");
    let loadError = $state<string | null>(null);

    let previewLoading = $state(false);
    let previewData = $state<ExternalMedia | null>(null);

    const isRu = $derived(i18n.current === "ru");

    $effect(() => {
        if (!isOpen || sources.length > 0) return;
        let cancelled = false;
        void getSources()
            .then((list) => {
                if (!cancelled) sources = list.filter((s) => s.isEnabled);
            })
            .catch((error) => {
                if (!cancelled) loadError = errorMessage(error);
            });
        return () => {
            cancelled = true;
        };
    });

    const SOURCES_BY_TYPE: Record<string, readonly string[]> = {
        game: ["rawg", "steam"],
        movie: ["tmdb", "kinopoisk", "simkl"],
        tvshow: ["tmdb", "kinopoisk", "simkl"],
        anime: ["anilist", "mangadex", "shikimori"],
        manga: ["anilist", "mangadex", "shikimori"],
        book: ["openlibrary"],
    };

    const options = $derived.by(() => {
        const allowed = SOURCES_BY_TYPE[String(mediaType).toLowerCase()] ?? [];
        return sources
            .filter((entry) => entry.isEnabled && allowed.includes(entry.id))
            .map((entry) => ({ value: entry.id, label: entry.name }));
    });

    const selectedValue = $derived(
        options.find((o) => o.value.toLowerCase() === String(source).toLowerCase())?.value ??
            options.find(
                (o) =>
                    o.value.toLowerCase() === String(currentSource).toLowerCase() ||
                    o.label.toLowerCase() === String(currentSource).toLowerCase(),
            )?.value ??
            options[0]?.value ??
            "",
    );

    const selectedLabel = $derived(
        options.find((o) => o.value === selectedValue)?.label ?? "",
    );

    interface EmptyFieldCheck {
        id: string;
        label: string;
        isEmpty: boolean;
        getPreviewValue: (ext: ExternalMedia) => string | null;
    }

    const candidateFields = $derived.by((): EmptyFieldCheck[] => {
        if (!media) return [];
        const type = String(media.type).toLowerCase();
        const list: EmptyFieldCheck[] = [
            {
                id: "cover",
                label: isRu ? "Обложка" : "Cover",
                isEmpty: !media.coverUrl,
                getPreviewValue: (ext) => (ext.coverUrl ? (isRu ? "найдено" : "found") : null),
            },
            {
                id: "description",
                label: isRu ? "Синопсис" : "Synopsis",
                isEmpty: !media.description?.trim(),
                getPreviewValue: (ext) => (ext.description?.trim() ? (isRu ? "найдено" : "found") : null),
            },
            {
                id: "genres",
                label: isRu ? "Жанры" : "Genres",
                isEmpty: !media.genres || (Array.isArray(media.genres) ? media.genres.length === 0 : !media.genres.trim()),
                getPreviewValue: (ext) => {
                    if (Array.isArray(ext.genres) && ext.genres.length > 0) {
                        return formatGenresList(ext.genres).slice(0, 3).join(", ");
                    }
                    if (typeof ext.genres === "string" && ext.genres.trim()) {
                        return formatGenresList(ext.genres.split(",").map((g) => g.trim())).slice(0, 3).join(", ");
                    }
                    return null;
                },
            },
        ];

        // Studio / Author / Director
        if (type === "game") {
            list.push({
                id: "studio",
                label: isRu ? "Разработчик" : "Developer",
                isEmpty: !("studio" in media) || !media.studio?.trim(),
                getPreviewValue: (ext) => ext.studio?.trim() || null,
            });
        } else if (type === "book" || type === "manga") {
            list.push({
                id: "author",
                label: isRu ? "Автор" : "Author",
                isEmpty: !("author" in media) || !media.author?.trim(),
                getPreviewValue: (ext) => ext.author?.trim() || null,
            });
        } else {
            list.push({
                id: "studio",
                label: isRu ? "Студия" : "Studio",
                isEmpty: !("studio" in media) || !media.studio?.trim(),
                getPreviewValue: (ext) => ext.studio?.trim() || null,
            });
            if (type === "movie") {
                list.push({
                    id: "director",
                    label: isRu ? "Режиссёр" : "Director",
                    isEmpty: !("director" in media) || !media.director?.trim(),
                    getPreviewValue: (ext) => ext.author?.trim() || null,
                });
            }
        }

        // Release Date
        list.push({
            id: "releaseDate",
            label: isRu ? "Дата выхода" : "Release Date",
            isEmpty: !media.releaseDate && !media.releaseYear,
            getPreviewValue: (ext) => ext.releaseDate || (ext.releaseYear ? String(ext.releaseYear) : null),
        });

        // End Date
        if (type === "tvshow" || type === "manga" || (type === "movie" && (media as { isAnime?: boolean }).isAnime)) {
            list.push({
                id: "endDate",
                label: isRu ? "Дата окончания" : "End Date",
                isEmpty: !media.endDate,
                getPreviewValue: (ext) => ext.endDate || null,
            });
        }

        // Duration / Count
        if (type === "movie") {
            list.push({
                id: "duration",
                label: isRu ? "Хронометраж" : "Duration",
                isEmpty: !("durationMinutes" in media) || !media.durationMinutes || media.durationMinutes <= 0,
                getPreviewValue: (ext) => (ext.runtimeMinutes || ext.totalCount ? `${ext.runtimeMinutes || ext.totalCount} ${isRu ? "мин." : "min"}` : null),
            });
        } else if (type === "book") {
            list.push({
                id: "totalPages",
                label: isRu ? "Количество страниц" : "Page Count",
                isEmpty: !("totalPages" in media) || !(media as { totalPages?: number }).totalPages || (media as { totalPages?: number }).totalPages! <= 0,
                getPreviewValue: (ext) => (ext.totalCount ? `${ext.totalCount} ${isRu ? "стр." : "p."}` : null),
            });
        } else if (type === "manga") {
            list.push({
                id: "totalChapters",
                label: isRu ? "Количество глав" : "Chapter Count",
                isEmpty: !("totalChapters" in media) || !(media as { totalChapters?: number }).totalChapters || (media as { totalChapters?: number }).totalChapters! <= 0,
                getPreviewValue: (ext) => (ext.chapters || ext.totalCount ? `${ext.chapters || ext.totalCount} ${isRu ? "гл." : "ch."}` : null),
            });
        }

        // Trailer
        list.push({
            id: "trailer",
            label: isRu ? "Трейлер" : "Trailer",
            isEmpty: !media.trailerVideoId?.trim(),
            getPreviewValue: (ext) => (ext.trailerVideoId?.trim() ? (isRu ? "найдено" : "found") : null),
        });

        // Cast
        if (type === "movie" || type === "tvshow") {
            list.push({
                id: "cast",
                label: isRu ? "Актёры" : "Cast",
                isEmpty: !media.cast || media.cast.length === 0,
                getPreviewValue: (ext) => (ext.episodes ? null : null),
            });
        }

        return list;
    });

    const emptyFields = $derived(candidateFields.filter((f) => f.isEmpty));

    $effect(() => {
        if (!isOpen || !media || !selectedValue) {
            previewData = null;
            previewLoading = false;
            return;
        }

        const controller = new AbortController();
        previewLoading = true;

        void getExternalDetails(
            media.type,
            media.externalId ?? "",
            media.title,
            selectedValue,
            controller.signal,
        )
            .then((data) => {
                if (!controller.signal.aborted) {
                    previewData = data;
                }
            })
            .catch(() => {
                if (!controller.signal.aborted) {
                    previewData = null;
                }
            })
            .finally(() => {
                if (!controller.signal.aborted) {
                    previewLoading = false;
                }
            });

        return () => {
            controller.abort();
        };
    });
</script>

<Modal {isOpen} onClose={onClose} labelledBy="fill-missing-title">
    <div class="p-5">
        <h2
            id="fill-missing-title"
            class="inline-flex items-center gap-2 text-base font-semibold text-white"
        >
            <Sparkles
                size={16}
                class="text-[var(--color-accent-soft)]"
                aria-hidden="true"
            />
            {i18n.t.detail.fillMissingTitle}
        </h2>
        <p class="mt-1.5 text-sm text-muted">
            {i18n.t.detail.fillMissingHint}
        </p>
    </div>

    <div class="border-t border-white/[0.08] p-5">
        <div class="flex items-center justify-between gap-3">
            <span class="shrink-0 text-xs font-medium text-muted">
                {i18n.t.detail.fillMissingSource}
            </span>
            <div class="min-w-0 flex-1 text-right">
                {#if options.length > 0}
                    <PopoverMenu
                        id={`fill-missing-${mediaType}`}
                        {options}
                        selected={selectedValue}
                        onSelect={(value) => (source = String(value))}
                        label={i18n.t.detail.fillMissingSource}
                        placement="bottom-end"
                        class="max-h-56 min-w-[180px] overflow-y-auto"
                        optionClass="text-xs"
                        openOnHover
                        closeDelay={220}
                    >
                        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
                            <button
                                type="button"
                                popovertarget={popoverTargetId}
                                popovertargetaction="toggle"
                                style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                                class="tap flex max-w-[220px] items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-field)] px-2.5 py-1.5 text-xs text-white transition hover:bg-[var(--color-track-faint)] has-[:popover-open]:ring-1 has-[:popover-open]:ring-[var(--color-accent)]"
                                aria-haspopup="listbox"
                            >
                                <span class="truncate">{selectedLabel}</span>
                                <ChevronDown
                                    size={13}
                                    class="shrink-0 text-muted transition duration-200 has-[:popover-open]:rotate-180 has-[:popover-open]:text-white"
                                    aria-hidden="true"
                                />
                            </button>
                        {/snippet}
                    </PopoverMenu>
                {:else}
                    <span class="text-xs text-muted">—</span>
                {/if}
            </div>
        </div>
    </div>

    <!-- Preview of fields to be enriched -->
    <div class="border-t border-white/[0.08] p-5 space-y-3">
        <div class="flex items-center justify-between">
            <h3 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {isRu ? "Предпросмотр данных" : "Preview missing fields"}
            </h3>
            {#if previewLoading}
                <div class="flex items-center gap-1.5 text-xs text-muted">
                    <LoaderCircle size={13} class="animate-spin text-accent-soft" />
                    <span>{isRu ? "Проверка источника..." : "Checking source..."}</span>
                </div>
            {/if}
        </div>

        {#if previewLoading}
            <div class="space-y-2 py-1">
                {#each Array(Math.min(emptyFields.length || 3, 4)) as _, i (i)}
                    <div class="h-7 w-full animate-pulse rounded-lg bg-white/[0.04]"></div>
                {/each}
            </div>
        {:else if emptyFields.length === 0}
            <div class="rounded-lg bg-emerald-500/10 border border-emerald-500/20 px-3 py-2 text-xs text-emerald-300">
                {isRu ? "✓ Все основные поля тайтла уже заполнены." : "✓ All main fields are already filled."}
            </div>
        {:else}
            <ul class="space-y-1.5 max-h-52 overflow-y-auto thin-scroll pr-1">
                {#each emptyFields as field (field.id)}
                    {@const val = previewData ? field.getPreviewValue(previewData) : null}
                    <li
                        class="flex items-center justify-between gap-2 text-xs py-1.5 px-2.5 rounded-lg border transition {val
                            ? 'bg-emerald-500/10 border-emerald-500/25 text-emerald-200'
                            : 'bg-white/[0.02] border-white/[0.04] text-slate-400'}"
                    >
                        <div class="flex items-center gap-2 min-w-0">
                            {#if val}
                                <span class="text-emerald-400 font-bold shrink-0">✓</span>
                                <span class="font-semibold text-white truncate">{field.label}</span>
                                <span class="text-emerald-300/80 truncate">— {val}</span>
                            {:else}
                                <span class="text-muted shrink-0">—</span>
                                <span class="text-slate-300 truncate">{field.label}</span>
                                <span class="text-muted text-[11px] truncate">— {isRu ? "нет данных в источнике" : "no data in source"}</span>
                            {/if}
                        </div>
                        {#if val}
                            <span class="shrink-0 rounded bg-emerald-500/20 border border-emerald-500/30 px-1.5 py-0.5 text-[10px] font-bold text-emerald-300">
                                {isRu ? "будет заполнено" : "will fill"}
                            </span>
                        {/if}
                    </li>
                {/each}
            </ul>
        {/if}
    </div>

    {#if loadError}
        <p class="px-5 pb-3 text-xs text-rose-300" role="alert">
            {i18n.t.detail.fillMissingSourcesFailed}
        </p>
    {/if}

    <div class="flex gap-2 border-t border-white/[0.08] p-5">
        <button
            type="button"
            class="tap inline-flex flex-1 items-center justify-center gap-2 rounded-lg bg-[var(--color-accent)] px-4 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-accent-hover)] disabled:cursor-wait disabled:opacity-60 cursor-pointer"
            disabled={busy || options.length === 0}
            onclick={() => onFill(selectedValue)}
        >
            {#if busy}
                <LoaderCircle size={14} class="animate-spin" aria-hidden="true" />
                {i18n.t.detail.fillMissingRunning}
            {:else}
                {i18n.t.detail.fillMissing}
            {/if}
        </button>
        <button
            type="button"
            class="tap rounded-lg px-4 py-2.5 text-sm text-muted transition hover:text-white disabled:opacity-60 cursor-pointer"
            disabled={busy}
            onclick={onClose}
        >
            {i18n.t.common.cancel}
        </button>
    </div>
</Modal>