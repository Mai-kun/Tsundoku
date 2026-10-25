<script lang="ts">
    import Modal from "$shared/ui/Modal.svelte";
    import Placeholder404 from "$entities/media/ui/Placeholder404.svelte";
    import {
        Activity,
        AlertTriangle,
        Check,
        LoaderCircle,
        Search,
        Trash2,
        X,
    } from "$shared/ui/Icons.svelte";
    import { jobsClient } from "$shared/api/jobsClient.svelte";
    import {
        deleteMedia,
        dismissAllPendingMatches,
        dismissPendingMatch,
        errorMessage,
        resolveAllPendingMatchesByPriority,
        resolvePendingMatch,
        searchExternal,
    } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type {
        ExternalMedia,
        JobProgress,
        PendingMatchItemDto,
    } from "$shared/types";

    interface Props {
        onMediaChanged?: () => void;
    }

    let { onMediaChanged }: Props = $props();

    /** Manual-search panel state per review card. `results` stays null until the user searches. */
    interface ManualSearch {
        open: boolean;
        query: string;
        results: ExternalMedia[] | null;
        loading: boolean;
    }

    let manualSearches = $state<Record<string, ManualSearch>>({});
    let dismissingAll = $state(false);
    let resolvingAll = $state(false);
    /** A candidate cover that failed once shows the 404-tan instead of a broken image icon. */
    let candidateImgErrors = $state<Record<string, boolean>>({});

    // The review tab only exists while there is something to review; a list emptied elsewhere
    // (job finished, all resolved) must not strand the modal on an empty tab.
    $effect(() => {
        if (jobsClient.modalTab === "review" && jobsClient.pendingCount === 0) {
            jobsClient.modalTab = "jobs";
        }
    });

    function emptySearch(title: string): ManualSearch {
        return { open: false, query: title, results: null, loading: false };
    }

    function toggleSearch(item: PendingMatchItemDto) {
        const existing = manualSearches[item.id];
        if (existing) {
            existing.open = !existing.open;
            return;
        }
        manualSearches[item.id] = { ...emptySearch(item.title), open: true };
    }

    async function runSearch(item: PendingMatchItemDto) {
        const search = manualSearches[item.id];
        if (!search || !search.query.trim() || search.loading) return;

        search.loading = true;
        try {
            const results = await searchExternal(
                item.type as Parameters<typeof searchExternal>[0],
                search.query,
            );
            search.results = results;
        } catch (error) {
            showToast(errorMessage(error), "error");
        } finally {
            search.loading = false;
        }
    }

    function candidatesFor(item: PendingMatchItemDto): ExternalMedia[] {
        const search = manualSearches[item.id];
        return search?.results ?? item.candidates ?? [];
    }

    function resolve(
        item: PendingMatchItemDto,
        candidate: ExternalMedia,
    ) {
        // Optimistic: the card vanishes at once. The server only records the choice (~2 ms) and
        // downloads covers/ratings through the background job, so no spinner and no 429 risk.
        jobsClient.dropPendingMatch(item.id);
        showToast(i18n.t.backgroundJobs.resolvedAsyncToast, "success");
        void resolvePendingMatch(item.id, {
            externalId: String(candidate.externalId),
            source: candidate.externalSource ?? "",
            type: candidate.type || item.type,
            title: candidate.title,
        })
            .catch((error) => showToast(errorMessage(error), "error"))
            .finally(() => onMediaChanged?.());
    }

    async function keep(item: PendingMatchItemDto) {
        try {
            await dismissPendingMatch(item.id);
            jobsClient.dropPendingMatch(item.id);
            onMediaChanged?.();
        } catch (error) {
            showToast(errorMessage(error), "error");
        }
    }

    async function keepAll() {
        if (dismissingAll) return;
        dismissingAll = true;
        const count = jobsClient.pendingCount;
        try {
            await dismissAllPendingMatches();
            jobsClient.pendingMatches = [];
            if (count > 0) showToast(i18n.t.backgroundJobs.keptToast(count));
            onMediaChanged?.();
        } catch (error) {
            showToast(errorMessage(error), "error");
        } finally {
            dismissingAll = false;
        }
    }

    async function resolveAllByPriority() {
        if (jobsClient.pendingCount === 0 || resolvingAll) return;
        resolvingAll = true;
        jobsClient.modalTab = "jobs";
        try {
            const result = await resolveAllPendingMatchesByPriority();
            showToast(
                i18n.t.backgroundJobs.resolvedByPriorityToast(
                    result.resolvedCount,
                    result.skippedCount,
                ),
                "success",
            );
            // Weak rows stay in review on purpose: reread so they appear back in the list.
            await jobsClient.refreshPendingMatches();
        } catch (error) {
            showToast(errorMessage(error), "error");
        } finally {
            resolvingAll = false;
            onMediaChanged?.();
        }
    }

    /** The row is a junk import, no candidates or a manual search will save it: remove it entirely. */
    function handleDeleteItem(id: string) {
        jobsClient.dropPendingMatch(id);
        void deleteMedia(id)
            .then(() => showToast(i18n.t.backgroundJobs.deletedToast, "success"))
            .catch((error) => showToast(errorMessage(error), "error"))
            .finally(() => onMediaChanged?.());
    }

    function statusLabel(job: JobProgress): string {
        switch (job.status) {
            case "Queued":
                return i18n.t.activity.queued;
            case "Completed":
                return i18n.t.activity.completed;
            case "Failed":
                return i18n.t.activity.failed;
            case "Cancelled":
                return i18n.t.activity.cancelled;
            default:
                return job.currentStep;
        }
    }

    function isCancellable(job: JobProgress): boolean {
        return job.status === "Queued" || job.status === "Running";
    }

    /** Batch-import steps look like «[12/377] Title (авто: …)». */
    function stepCounts(step: string | null): { current: number; total: number } | null {
        const match = step?.match(/\[(\d+)\s*\/\s*(\d+)\]/);
        if (!match) return null;
        return { current: Number(match[1]), total: Number(match[2]) };
    }

    function isBatchImport(job: JobProgress): boolean {
        return (
            job.status === "Running" &&
            (job.title.toLowerCase().includes("импорт") || stepCounts(job.currentStep) !== null)
        );
    }

    /** The queue walks one title every 2.5 s (the provider rate-limit pause), so the rest is linear. */
    function etaMinutes(job: JobProgress): number | null {
        const counts = stepCounts(job.currentStep);
        if (!counts || counts.total <= counts.current) return null;
        return Math.ceil(((counts.total - counts.current) * 2.5) / 60);
    }

    const sourceBadges: Record<string, string> = {
        anilist: "bg-emerald-500/15 text-emerald-300",
        mangadex: "bg-rose-500/15 text-rose-300",
        shikimori: "bg-sky-500/15 text-sky-300",
    };

    function sourceBadgeClass(source: string | null | undefined): string {
        return (source && sourceBadges[source.toLowerCase()]) || "bg-white/[0.07] text-slate-300";
    }
</script>

<Modal
    isOpen={jobsClient.isModalOpen}
    onClose={() => jobsClient.closeModal()}
    size="xl"
>
    <div class="flex h-full flex-col overflow-hidden">
        <header
            class="flex shrink-0 flex-col gap-3 border-b border-white/[0.08] px-5 py-4"
        >
            <div class="flex items-center gap-3">
                <div
                    class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#5844e0]/20 text-[#8f7fff]"
                >
                    <Activity size={19} aria-hidden="true" />
                </div>
                <h2 class="text-base font-bold text-ink">
                    {i18n.t.activity.label}
                </h2>
                <button
                    type="button"
                    class="ml-auto grid h-8 w-8 cursor-pointer place-items-center rounded-lg text-muted transition hover:bg-white/10 hover:text-white"
                    aria-label={i18n.t.common.close}
                    onclick={() => jobsClient.closeModal()}
                >
                    <X size={18} aria-hidden="true" />
                </button>
            </div>

            <div
                class="flex gap-1.5 self-start rounded-lg bg-black/25 p-1"
                role="tablist"
            >
                <button
                    type="button"
                    role="tab"
                    aria-selected={jobsClient.modalTab === "jobs"}
                    class="inline-flex cursor-pointer items-center gap-2 rounded-md px-3.5 py-1.5 text-xs font-semibold transition {jobsClient.modalTab ===
                    "jobs"
                        ? "bg-[#5844e0] text-white"
                        : "text-muted hover:text-ink"}"
                    onclick={() => (jobsClient.modalTab = "jobs")}
                >
                    {i18n.t.backgroundJobs.tabQueue}
                    {#if jobsClient.activeCount > 0}
                        <span
                            class="min-w-4 rounded-full bg-white/20 px-1 text-[10px] font-bold leading-4 tabular-nums"
                        >
                            {jobsClient.activeCount}
                        </span>
                    {/if}
                </button>
                {#if jobsClient.pendingCount > 0}
                    <button
                        type="button"
                        role="tab"
                        aria-selected={jobsClient.modalTab === "review"}
                        class="inline-flex cursor-pointer items-center gap-2 rounded-md px-3.5 py-1.5 text-xs font-semibold transition {jobsClient.modalTab ===
                        "review"
                            ? "bg-amber-500 text-black"
                            : "text-muted hover:text-ink"}"
                        onclick={() => (jobsClient.modalTab = "review")}
                    >
                        {i18n.t.backgroundJobs.tabReview}
                        <span
                            class="min-w-4 rounded-full bg-amber-500 px-1 text-[10px] font-bold leading-4 text-black tabular-nums"
                        >
                            {jobsClient.pendingCount}
                        </span>
                    </button>
                {/if}
            </div>
        </header>

        <div class="thin-scroll min-h-0 flex-1 overflow-y-auto p-5">
            {#if jobsClient.modalTab === "jobs"}
                {#if jobsClient.pendingCount > 0}
                    <div
                        class="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3"
                    >
                        <AlertTriangle
                            size={18}
                            class="shrink-0 text-amber-400"
                            aria-hidden="true"
                        />
                        <p class="min-w-0 flex-1 text-sm font-medium text-amber-200">
                            {i18n.t.backgroundJobs.banner(jobsClient.pendingCount)}
                        </p>
                        <button
                            type="button"
                            class="cursor-pointer rounded-lg bg-amber-500 px-3.5 py-1.5 text-xs font-bold text-black transition hover:bg-amber-400"
                            onclick={() => (jobsClient.modalTab = "review")}
                        >
                            {i18n.t.backgroundJobs.gotoReview}
                        </button>
                    </div>
                {/if}

                {#if jobsClient.jobs.length === 0}
                    <div
                        class="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center"
                    >
                        <div
                            class="grid h-12 w-12 place-items-center rounded-full bg-white/[0.04] text-muted"
                        >
                            <Activity size={24} aria-hidden="true" />
                        </div>
                        <p class="text-sm font-semibold text-ink">
                            {i18n.t.activity.empty}
                        </p>
                        <p class="max-w-sm text-xs text-muted">
                            {i18n.t.activity.emptyHint}
                        </p>
                    </div>
                {:else}
                    <ul class="space-y-3">
                        {#each jobsClient.jobs as job (job.jobId)}
                            <li
                                class="rounded-xl border border-white/[0.06] bg-white/[0.03] p-4"
                            >
                                <div class="flex items-center gap-3">
                                    <p
                                        class="min-w-0 flex-1 truncate text-sm font-semibold text-ink"
                                        title={job.title}
                                    >
                                        {job.title}
                                    </p>
                                    <span
                                        class="shrink-0 text-xs font-medium text-slate-400 tabular-nums"
                                    >
                                        {job.status === "Failed"
                                            ? `${i18n.t.activity.failed} · `
                                            : ""}{job.progressPercent}%
                                    </span>
                                    {#if isCancellable(job)}
                                        <button
                                            type="button"
                                            class="shrink-0 cursor-pointer rounded-lg border border-white/[0.08] bg-field px-2.5 py-1 text-[11px] font-medium text-muted transition hover:border-rose-500/40 hover:bg-rose-500/15 hover:text-rose-300"
                                            title={i18n.t.activity.cancel}
                                            aria-label={i18n.t.activity.cancelAria(job.title)}
                                            onclick={() => void jobsClient.cancel(job.jobId)}
                                        >
                                            {i18n.t.activity.cancel}
                                        </button>
                                    {/if}
                                </div>

                                <div
                                    class="mt-3 h-2 overflow-hidden rounded-full bg-white/[0.08]"
                                    role="progressbar"
                                    aria-label={job.title}
                                    aria-valuenow={job.progressPercent}
                                    aria-valuemin="0"
                                    aria-valuemax="100"
                                >
                                    <div
                                        class={`h-full w-full origin-left rounded-full transition-transform duration-500 ease-out ${
                                            job.status === "Failed"
                                                ? "bg-rose-500"
                                                : job.status === "Completed"
                                                  ? "bg-emerald-500"
                                                  : "bg-[#5844e0]"
                                        }`}
                                        style={`transform: scaleX(${job.progressPercent / 100})`}
                                    ></div>
                                </div>

                                {#if isBatchImport(job)}
                                    <div
                                        class="mt-2 flex flex-wrap items-center gap-2 rounded-lg bg-[#5844e0]/10 px-3 py-2 text-[11px] leading-relaxed text-[#a99cff]"
                                    >
                                        <p class="min-w-0 flex-1">
                                            {i18n.t.backgroundJobs.throttleNotice}
                                        </p>
                                        {#if etaMinutes(job)}
                                            <span
                                                class="shrink-0 rounded-md bg-[#5844e0] px-2 py-0.5 text-[10px] font-bold text-white tabular-nums"
                                            >
                                                {i18n.t.backgroundJobs
                                                    .remainingMin(etaMinutes(job)!)}
                                            </span>
                                        {/if}
                                    </div>
                                {/if}

                                <p
                                    class={`mt-2 truncate text-xs ${
                                        job.status === "Failed"
                                            ? "text-rose-300"
                                            : "text-muted"
                                    }`}
                                >
                                    {job.errorMessage ?? statusLabel(job)}
                                </p>
                            </li>
                        {/each}
                    </ul>
                {/if}
            {:else if jobsClient.pendingCount > 0}
                <div
                    class="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-white/[0.08] bg-white/[0.03] px-4 py-3"
                >
                    <p class="min-w-0 flex-1 text-xs leading-relaxed text-muted">
                        {i18n.t.backgroundJobs.reviewIntro}
                    </p>
                    <button
                        type="button"
                        class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-accent/40 bg-accent/20 px-3.5 py-1.5 text-xs font-semibold text-accent-soft shadow-sm transition hover:bg-accent hover:text-white"
                        onclick={() => void resolveAllByPriority()}
                    >
                        {i18n.t.backgroundJobs.resolveAllPriority}
                    </button>
                    <button
                        type="button"
                        disabled={dismissingAll || jobsClient.pendingCount === 0}
                        class="shrink-0 cursor-pointer rounded-lg border border-white/10 bg-field px-3.5 py-1.5 text-xs font-medium text-ink transition hover:bg-elevated hover:text-white disabled:cursor-wait disabled:opacity-50"
                        onclick={() => void keepAll()}
                    >
                        {#if dismissingAll}
                            <LoaderCircle size={14} class="mr-1 inline animate-spin" />
                        {/if}
                        {i18n.t.backgroundJobs.keepAll}
                    </button>
                </div>

                {#if jobsClient.pendingMatches.length === 0}
                    <div
                        class="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center"
                    >
                        <div
                            class="grid h-12 w-12 place-items-center rounded-full bg-amber-500/10 text-amber-400"
                        >
                            <AlertTriangle size={24} aria-hidden="true" />
                        </div>
                        <p class="text-sm font-semibold text-ink">
                            {i18n.t.activity.empty}
                        </p>
                        <p class="max-w-sm text-xs text-muted">
                            {i18n.t.activity.emptyHint}
                        </p>
                    </div>
                {:else}
                    <ul class="space-y-4">
                        {#each jobsClient.pendingMatches as item (item.id)}
                            {@const search = manualSearches[item.id] ?? emptySearch(item.title)}
                            {@const candidates = candidatesFor(item)}
                            <li class="rounded-xl border border-white/[0.08] bg-card/60 p-4">
                                <div
                                    class="flex flex-wrap items-start justify-between gap-3"
                                >
                                    <div class="min-w-0">
                                        <p
                                            class="text-xs font-bold uppercase tracking-wider text-slate-300"
                                        >
                                            {i18n.t.backgroundJobs.yourEntryPrompt}
                                        </p>
                                        <h3 class="mt-0.5 truncate text-sm font-bold text-ink">
                                            {item.title}
                                            {#if item.romajiTitle && item.romajiTitle !== item.title}
                                                <span class="ml-1.5 text-xs font-normal text-muted">
                                                    ({item.romajiTitle})
                                                </span>
                                            {/if}
                                        </h3>
                                        <div class="mt-1.5 flex flex-wrap items-center gap-1.5">
                                            <span
                                                class="rounded-md bg-[#5844e0]/20 px-2 py-0.5 text-[10px] font-semibold text-[#8f7fff]"
                                            >
                                                {item.type}{item.isAnime ? " · anime" : ""}
                                            </span>
                                            {#if item.releaseYear}
                                                <span
                                                    class="rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium text-muted tabular-nums"
                                                >
                                                    {item.releaseYear}
                                                </span>
                                            {/if}
                                            {#if item.author}
                                                <span
                                                    class="truncate rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium text-muted"
                                                >
                                                    {item.author}
                                                </span>
                                            {/if}
                                            {#if item.currentProgress !== null && item.currentProgress !== undefined}
                                                <span
                                                    class="rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium text-muted tabular-nums"
                                                >
                                                    {item.currentProgress}{item.totalCount
                                                        ? ` / ${item.totalCount}`
                                                        : ""}
                                                </span>
                                            {/if}
                                        </div>
                                    </div>
                                    <div class="flex shrink-0 gap-2">
                                        <button
                                            type="button"
                                            class="inline-flex items-center gap-1.5 rounded-lg border border-rose-500/25 bg-rose-500/10 px-2.5 py-1.5 text-xs font-medium text-rose-300 transition hover:border-rose-500/40 hover:bg-rose-500/20 cursor-pointer"
                                            title="Удалить этот тайтл из библиотеки навсегда"
                                            onclick={() => handleDeleteItem(item.id)}
                                        >
                                            <Trash2 size={13} aria-hidden="true" />
                                            <span>{i18n.t.backgroundJobs.delete}</span>
                                        </button>
                                        <button
                                            type="button"
                                            class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-white/10 bg-field px-3 py-1.5 text-xs font-medium text-ink transition hover:bg-elevated hover:text-white"
                                            onclick={() => toggleSearch(item)}
                                        >
                                            <Search size={13} aria-hidden="true" />
                                            {i18n.t.backgroundJobs.findManually}
                                        </button>
                                        <button
                                            type="button"
                                            class="cursor-pointer rounded-lg border border-white/10 px-3 py-1.5 text-xs text-muted transition hover:bg-white/5 hover:text-ink"
                                            onclick={() => void keep(item)}
                                        >
                                            {i18n.t.backgroundJobs.keepAsIs}
                                        </button>
                                    </div>
                                </div>

                                {#if search.open}
                                    <div class="mt-3 flex gap-2">
                                        <input
                                            type="search"
                                            bind:value={search.query}
                                            placeholder={i18n.t.backgroundJobs.searchPlaceholder}
                                            class="min-w-0 flex-1 rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                            onkeydown={(event) => {
                                                if (event.key === "Enter")
                                                    void runSearch(item);
                                            }}
                                        />
                                        <button
                                            type="button"
                                            disabled={search.loading}
                                            class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-accent px-3.5 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover disabled:cursor-wait disabled:opacity-60"
                                            onclick={() => void runSearch(item)}
                                        >
                                            {#if search.loading}
                                                <LoaderCircle
                                                    size={15}
                                                    class="animate-spin"
                                                />
                                            {:else}
                                                <Search size={15} aria-hidden="true" />
                                            {/if}
                                        </button>
                                    </div>
                                    {#if search.results}
                                        <p class="mt-3 text-[10px] font-bold uppercase tracking-wider text-muted">
                                            {i18n.t.backgroundJobs.suggestions}
                                        </p>
                                    {/if}
                                {/if}

                                {#if candidates.length === 0}
                                    <p class="mt-3 text-xs leading-relaxed text-muted">
                                        {i18n.t.backgroundJobs.noCandidates}
                                    </p>
                                {:else}
                                    <div
                                        class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2"
                                    >
                                        {#each candidates as candidate (candidate.externalSource + candidate.externalId)}
                                            {@const key = candidate.externalSource + candidate.externalId}
                                            <div
                                                class="flex items-center justify-between gap-3.5 rounded-xl border border-white/[0.06] bg-white/[0.03] p-3 transition hover:border-white/15 hover:bg-white/[0.06]"
                                            >
                                                {#if candidate.coverUrl && !candidateImgErrors[key]}
                                                    <img
                                                        src={candidate.coverUrl}
                                                        alt={candidate.title}
                                                        referrerpolicy="no-referrer"
                                                        class="h-20 w-14 shrink-0 rounded-lg bg-canvas object-cover ring-1 ring-white/10"
                                                        loading="lazy"
                                                        decoding="async"
                                                        onerror={() => (candidateImgErrors[key] = true)}
                                                    />
                                                {:else}
                                                    <div
                                                        class="h-20 w-14 shrink-0 overflow-hidden rounded-lg ring-1 ring-white/10"
                                                    >
                                                        <Placeholder404 />
                                                    </div>
                                                {/if}
                                                <div class="min-w-0 flex-1 space-y-1">
                                                    <p
                                                        class="line-clamp-2 text-xs font-bold leading-snug text-white sm:text-sm"
                                                        title={candidate.title}
                                                    >
                                                        {candidate.title}
                                                    </p>
                                                    {#if candidate.originalTitle || candidate.romajiTitle}
                                                        <p
                                                            class="truncate text-[11px] text-muted"
                                                        >
                                                            {candidate.originalTitle ??
                                                                candidate.romajiTitle}
                                                        </p>
                                                    {/if}
                                                    <div class="flex flex-wrap gap-1 text-[10px]">
                                                        {#if candidate.externalSource}
                                                            <span
                                                                class="rounded px-1.5 py-0.5 font-semibold {sourceBadgeClass(
                                                                    candidate.externalSource,
                                                                )}"
                                                            >
                                                                {candidate.externalSource}
                                                            </span>
                                                        {/if}
                                                        {#if candidate.releaseYear}
                                                            <span
                                                                class="rounded bg-white/[0.07] px-1.5 py-0.5 text-muted tabular-nums"
                                                            >
                                                                {candidate.releaseYear}
                                                            </span>
                                                        {/if}
                                                        {#if (candidate.totalCount ?? candidate.chapters) !== null && (candidate.totalCount ?? candidate.chapters) !== undefined}
                                                            <span
                                                                class="rounded bg-white/[0.07] px-1.5 py-0.5 text-muted tabular-nums"
                                                            >
                                                                {candidate.totalCount ??
                                                                    candidate.chapters}
                                                            </span>
                                                        {/if}
                                                        {#if candidate.author || candidate.studio}
                                                            <span
                                                                class="truncate rounded bg-white/[0.07] px-1.5 py-0.5 text-muted"
                                                            >
                                                                {candidate.author ??
                                                                    candidate.studio}
                                                            </span>
                                                        {/if}
                                                    </div>
                                                </div>
                                                <button
                                                    type="button"
                                                    class="grid size-10 shrink-0 cursor-pointer place-items-center rounded-xl bg-accent text-white shadow-md transition hover:bg-accent-hover active:scale-95"
                                                    title="Выбрать этот вариант"
                                                    aria-label={i18n.t.backgroundJobs.choose}
                                                    onclick={() => resolve(item, candidate)}
                                                >
                                                    <Check size={18} stroke-width={2.5} />
                                                </button>
                                            </div>
                                        {/each}
                                    </div>
                                {/if}
                            </li>
                        {/each}
                    </ul>
                {/if}
            {/if}
        </div>
    </div>
</Modal>
