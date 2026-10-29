<script module lang="ts">
  const CYRILLIC_RE = /[а-яА-ЯёЁ]/;
  const LATIN_LETTER_RE = /[a-zA-Z]/;
</script>

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
  } from "$shared/ui/Icons";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import {
    deleteMedia,
    dismissAllPendingMatches,
    dismissPendingMatch,
    errorMessage,
    resolveAllPendingMatchesByPriority,
    resolvePendingMatch,
    searchExternal,
    getSourcePriority,
  } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { ExternalMedia, JobProgress, PendingMatchItemDto } from "$shared/types";

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

  const defaultPriorities: Record<string, string[]> = {
    anime: ["anilist", "shikimori", "kitsu", "simkl"],
    manga: ["anilist", "mangadex", "shikimori", "mangaupdates", "kitsu"],
    movie: ["tmdb", "kinopoisk", "imdb", "simkl"],
    tvshow: ["tmdb", "kinopoisk", "imdb", "simkl"],
    book: ["openlibrary"],
    game: ["steam", "rawg"],
  };

  let sourcePriorities = $state<Record<string, string[]>>({});

  $effect(() => {
    void getSourcePriority()
      .then((p) => {
        if (p) sourcePriorities = p;
      })
      .catch(() => {});
  });

  // The review tab only exists while there is something to review; a list emptied elsewhere
  // (job finished, all resolved) must not strand the modal on an empty tab.
  $effect(() => {
    if (jobsClient.modalTab === "review" && jobsClient.pendingCount === 0) {
      jobsClient.modalTab = "jobs";
    }
  });

  function extractLatin(title: string): string | null {
    if (!title) return null;
    const match = title.match(/\(([^)]*[a-zA-Z]{2,}[^)]*)\)/);
    if (match) return match[1].trim();
    const isLatin = !CYRILLIC_RE.test(title) && LATIN_LETTER_RE.test(title);
    if (isLatin) return title.trim();
    return null;
  }

  function extractRussian(title: string): string {
    if (!title) return "";
    const match = title.match(/^([^\(]+)\s*\([^)]*[a-zA-Z][^)]*\)/);
    if (match && CYRILLIC_RE.test(match[1])) return match[1].trim();
    return title.trim();
  }

  function scoreCandidate(item: PendingMatchItemDto, cand: ExternalMedia): number {
    const norm = (s: string | null | undefined) =>
      (s ?? "").toLowerCase().replace(/[^a-z0-9а-яё]/gi, "");

    const targets = [item.title, item.romajiTitle].map(norm).filter(Boolean);
    const candTitles = [cand.title, cand.originalTitle, cand.romajiTitle].map(norm).filter(Boolean);
    let best = 0;
    for (const t of targets) {
      for (const c of candTitles) {
        if (t === c) {
          best = Math.max(best, 60);
        } else if (t.length >= 5 && (t.includes(c) || c.includes(t))) {
          best = Math.max(best, 40);
        }
      }
    }
    if (
      item.releaseYear &&
      cand.releaseYear &&
      Math.abs(item.releaseYear - cand.releaseYear) <= 1
    ) {
      best += 20;
    }
    return best;
  }

  function sortCandidates(list: ExternalMedia[], item: PendingMatchItemDto): ExternalMedia[] {
    const priorities = (
      sourcePriorities[item.type]?.length
        ? sourcePriorities[item.type]
        : defaultPriorities[item.type] || []
    ).map((s) => s.toLowerCase());

    const getRank = (source: string | null | undefined) => {
      if (!source) return 999;
      const idx = priorities.indexOf(source.toLowerCase());
      return idx >= 0 ? idx : 999;
    };

    return [...list].sort((a, b) => {
      const rankA = getRank(a.externalSource);
      const rankB = getRank(b.externalSource);
      if (rankA !== rankB) return rankA - rankB;
      return scoreCandidate(item, b) - scoreCandidate(item, a);
    });
  }

  function getPreferredSearchQuery(item: PendingMatchItemDto): string {
    return item.romajiTitle || item.title;
  }

  function emptySearch(item: PendingMatchItemDto): ManualSearch {
    return { open: false, query: getPreferredSearchQuery(item), results: null, loading: false };
  }

  function toggleSearch(item: PendingMatchItemDto) {
    const existing = manualSearches[item.id];
    if (existing) {
      existing.open = !existing.open;
      return;
    }
    manualSearches[item.id] = { ...emptySearch(item), open: true };
  }

  // When an item has 0 candidates, automatically open manual search with its preferred Latin/Romaji query
  $effect(() => {
    for (const item of jobsClient.pendingMatches) {
      if ((!item.candidates || item.candidates.length === 0) && !manualSearches[item.id]) {
        manualSearches[item.id] = {
          open: true,
          query: getPreferredSearchQuery(item),
          results: null,
          loading: false,
        };
        void runSearch(item);
      }
    }
  });

  async function runSearch(item: PendingMatchItemDto) {
    const search = manualSearches[item.id];
    if (!search || !search.query.trim() || search.loading) return;

    search.loading = true;
    try {
      const priorities = sourcePriorities[item.type]?.length
        ? sourcePriorities[item.type]
        : defaultPriorities[item.type] || [];

      const activeSources = priorities.slice(0, 3);
      const latin = extractLatin(search.query);
      const russian = extractRussian(search.query);

      if (activeSources.length > 0) {
        const searchPromises = activeSources.map((source) => {
          let q = search.query;
          if ((source === "anilist" || source === "mangadex") && (latin || item.romajiTitle)) {
            q = latin || item.romajiTitle || search.query;
          } else if (
            (source === "shikimori" || source === "kinopoisk") &&
            (russian || item.title)
          ) {
            q = russian || item.title || search.query;
          }
          return searchExternal(
            item.type as Parameters<typeof searchExternal>[0],
            q,
            undefined,
            source,
          ).catch(() => [] as ExternalMedia[]);
        });

        const perSourceResults = await Promise.all(searchPromises);
        const collected: ExternalMedia[] = [];
        const seen = new Set<string>();
        for (const list of perSourceResults) {
          for (const cand of list.slice(0, 4)) {
            const key = `${cand.externalSource}:${cand.externalId}`;
            if (!seen.has(key)) {
              seen.add(key);
              collected.push(cand);
            }
          }
        }
        search.results = sortCandidates(collected, item);
      } else {
        const results = await searchExternal(
          item.type as Parameters<typeof searchExternal>[0],
          search.query,
        );
        search.results = sortCandidates(results.slice(0, 4), item);
      }
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      search.loading = false;
    }
  }

  function candidatesFor(item: PendingMatchItemDto): ExternalMedia[] {
    const search = manualSearches[item.id];
    const raw = search?.results ?? item.candidates ?? [];
    return sortCandidates(raw, item);
  }

  function resolve(item: PendingMatchItemDto, candidate: ExternalMedia) {
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
    try {
      const result = await resolveAllPendingMatchesByPriority();
      showToast(
        i18n.t.backgroundJobs.resolvedByPriorityToast(result.resolvedCount, result.skippedCount),
        "success",
      );
      // Weak rows stay in review on purpose: reread so they appear back in the list.
      await jobsClient.refreshPendingMatches();
      if (jobsClient.pendingCount === 0) {
        jobsClient.modalTab = "jobs";
      }
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

<Modal isOpen={jobsClient.isModalOpen} onClose={() => jobsClient.closeModal()} size="xl">
  <div class="flex h-full flex-col overflow-hidden">
    <header class="flex shrink-0 flex-col gap-3 border-b border-white/[0.08] px-5 py-4">
      <div class="flex items-center gap-3">
        <div
          class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#5844e0]/20 text-[#8f7fff]"
        >
          <Activity size={19} aria-hidden="true" />
        </div>
        <h2 class="text-ink text-base font-bold">
          {i18n.t.activity.label}
        </h2>
        <button
          type="button"
          class="text-muted ml-auto grid h-8 w-8 cursor-pointer place-items-center rounded-lg transition hover:bg-white/10 hover:text-white"
          aria-label={i18n.t.common.close}
          onclick={() => jobsClient.closeModal()}
        >
          <X size={18} aria-hidden="true" />
        </button>
      </div>

      <div class="flex gap-1.5 self-start rounded-lg bg-black/25 p-1" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={jobsClient.modalTab === "jobs"}
          class="inline-flex cursor-pointer items-center gap-2 rounded-md px-3.5 py-1.5 text-xs font-semibold transition {jobsClient.modalTab ===
          'jobs'
            ? 'bg-[#5844e0] text-white'
            : 'text-muted hover:text-ink'}"
          onclick={() => (jobsClient.modalTab = "jobs")}
        >
          {i18n.t.backgroundJobs.tabQueue}
          {#if jobsClient.activeCount > 0}
            <span
              class="min-w-4 rounded-full bg-white/20 px-1 text-[10px] leading-4 font-bold tabular-nums"
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
            'review'
              ? 'bg-amber-500 text-black'
              : 'text-muted hover:text-ink'}"
            onclick={() => (jobsClient.modalTab = "review")}
          >
            {i18n.t.backgroundJobs.tabReview}
            <span
              class="min-w-4 rounded-full bg-amber-500 px-1 text-[10px] leading-4 font-bold text-black tabular-nums"
            >
              {jobsClient.pendingCount}
            </span>
          </button>
        {/if}
      </div>
    </header>

    <div class="thin-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain p-5">
      {#if jobsClient.modalTab === "jobs"}
        {#if jobsClient.pendingCount > 0}
          <div
            class="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3"
          >
            <AlertTriangle size={18} class="shrink-0 text-amber-400" aria-hidden="true" />
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
          <div class="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center">
            <div class="text-muted grid h-12 w-12 place-items-center rounded-full bg-white/[0.04]">
              <Activity size={24} aria-hidden="true" />
            </div>
            <p class="text-ink text-sm font-semibold">
              {i18n.t.activity.empty}
            </p>
            <p class="text-muted max-w-sm text-xs">
              {i18n.t.activity.emptyHint}
            </p>
          </div>
        {:else}
          <ul class="space-y-3">
            {#each jobsClient.jobs as job (job.jobId)}
              <li class="rounded-xl border border-white/[0.06] bg-white/[0.03] p-4">
                <div class="flex items-center gap-3">
                  <p
                    class="text-ink min-w-0 flex-1 truncate text-sm font-semibold"
                    title={job.title}
                  >
                    {job.title}
                  </p>
                  <span class="shrink-0 text-xs font-medium text-slate-400 tabular-nums">
                    {job.status === "Failed"
                      ? `${i18n.t.activity.failed} · `
                      : ""}{job.progressPercent}%
                  </span>
                  {#if isCancellable(job)}
                    <button
                      type="button"
                      class="bg-field text-muted shrink-0 cursor-pointer rounded-lg border border-white/[0.08] px-2.5 py-1 text-[11px] font-medium transition hover:border-rose-500/40 hover:bg-rose-500/15 hover:text-rose-300"
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
                        {i18n.t.backgroundJobs.remainingMin(etaMinutes(job)!)}
                      </span>
                    {/if}
                  </div>
                {/if}

                <p
                  class={`mt-2 truncate text-xs ${
                    job.status === "Failed" ? "text-rose-300" : "text-muted"
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
          <p class="text-muted min-w-0 flex-1 text-xs leading-relaxed">
            {i18n.t.backgroundJobs.reviewIntro}
          </p>
          <button
            type="button"
            disabled={resolvingAll || jobsClient.pendingCount === 0}
            class="border-accent/40 bg-accent/20 text-accent-soft hover:bg-accent inline-flex h-9 cursor-pointer items-center justify-center gap-1.5 rounded-lg border px-3.5 text-xs font-semibold whitespace-nowrap shadow-sm transition hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
            title="Автоматически привязать кандидатов с надежным совпадением (балл ≥ 50)"
            onclick={() => void resolveAllByPriority()}
          >
            {#if resolvingAll}
              <LoaderCircle size={14} class="animate-spin" />
            {/if}
            <span>⚡ {i18n.t.backgroundJobs.resolveAllPriority}</span>
          </button>
          <button
            type="button"
            disabled={dismissingAll || jobsClient.pendingCount === 0}
            class="bg-field inline-flex h-9 cursor-pointer items-center justify-center gap-1.5 rounded-lg border border-white/10 px-3.5 text-xs font-medium whitespace-nowrap text-slate-300 transition hover:bg-white/10 hover:text-white disabled:cursor-wait disabled:opacity-50"
            title="Оставить все как есть (без привязки)"
            onclick={() => void keepAll()}
          >
            {#if dismissingAll}
              <LoaderCircle size={14} class="mr-1 inline animate-spin" />
            {/if}
            <span>{i18n.t.backgroundJobs.keepAll}</span>
          </button>
        </div>

        {#if jobsClient.pendingMatches.length === 0}
          <div class="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center">
            <div
              class="grid h-12 w-12 place-items-center rounded-full bg-amber-500/10 text-amber-400"
            >
              <AlertTriangle size={24} aria-hidden="true" />
            </div>
            <p class="text-ink text-sm font-semibold">
              {i18n.t.activity.empty}
            </p>
            <p class="text-muted max-w-sm text-xs">
              {i18n.t.activity.emptyHint}
            </p>
          </div>
        {:else}
          <ul class="space-y-4">
            {#each jobsClient.pendingMatches as item (item.id)}
              {@const search = manualSearches[item.id] ?? emptySearch(item)}
              {@const candidates = candidatesFor(item)}
              <li class="bg-card/60 rounded-xl border border-white/[0.08] p-4">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="text-xs font-bold tracking-wider text-slate-300 uppercase">
                      {i18n.t.backgroundJobs.yourEntryPrompt}
                    </p>
                    <h3 class="text-ink mt-0.5 truncate text-sm font-bold">
                      {item.title}
                      {#if item.romajiTitle && item.romajiTitle !== item.title}
                        <span class="text-muted ml-1.5 text-xs font-normal">
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
                          class="text-muted rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium tabular-nums"
                        >
                          {item.releaseYear}
                        </span>
                      {/if}
                      {#if item.author}
                        <span
                          class="text-muted truncate rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium"
                        >
                          {item.author}
                        </span>
                      {/if}
                      {#if item.currentProgress !== null && item.currentProgress !== undefined}
                        <span
                          class="text-muted rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium tabular-nums"
                        >
                          {item.currentProgress}{item.totalCount ? ` / ${item.totalCount}` : ""}
                        </span>
                      {/if}
                    </div>
                  </div>
                  <div class="flex shrink-0 items-center gap-1.5">
                    <button
                      type="button"
                      class="bg-field hover:bg-elevated inline-flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/10 text-slate-300 transition hover:text-white sm:size-9 {search.open
                        ? 'border-accent-soft text-accent-soft'
                        : ''}"
                      title="Искать вручную"
                      aria-label={i18n.t.backgroundJobs.findManually}
                      onclick={() => toggleSearch(item)}
                    >
                      <Search size={15} aria-hidden="true" />
                    </button>
                    <button
                      type="button"
                      class="bg-field hover:bg-elevated inline-flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/10 text-slate-300 transition hover:text-white sm:size-9"
                      title="Оставить как есть (без привязки)"
                      aria-label={i18n.t.backgroundJobs.keepAsIs}
                      onclick={() => void keep(item)}
                    >
                      <X size={15} aria-hidden="true" />
                    </button>
                    <button
                      type="button"
                      class="inline-flex size-8 cursor-pointer items-center justify-center rounded-lg border border-rose-500/20 bg-rose-500/10 text-rose-400 transition hover:border-rose-500/40 hover:bg-rose-500/20 sm:size-9"
                      title="Удалить из библиотеки"
                      aria-label={i18n.t.backgroundJobs.delete}
                      onclick={() => handleDeleteItem(item.id)}
                    >
                      <Trash2 size={15} aria-hidden="true" />
                    </button>
                  </div>
                </div>

                {#if search.open}
                  <div class="mt-3 flex items-center gap-2">
                    <div class="relative flex min-w-0 flex-1 items-center">
                      <input
                        type="search"
                        bind:value={search.query}
                        placeholder={i18n.t.backgroundJobs.searchPlaceholder}
                        class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 pr-20 text-sm transition outline-none focus:ring-1"
                        onkeydown={(event) => {
                          if (event.key === "Enter") void runSearch(item);
                        }}
                      />
                      {#if item.romajiTitle || extractLatin(item.title)}
                        <div class="absolute right-2 flex items-center gap-1">
                          <button
                            type="button"
                            class="cursor-pointer rounded px-1.5 py-0.5 text-[10px] font-semibold transition {search.query ===
                            (item.romajiTitle || item.title)
                              ? 'bg-accent text-white'
                              : 'text-muted bg-white/10 hover:text-white'}"
                            title="Искать по латинице / Romaji"
                            onclick={() => {
                              search.query = item.romajiTitle || item.title;
                              void runSearch(item);
                            }}
                          >
                            EN
                          </button>
                          <button
                            type="button"
                            class="cursor-pointer rounded px-1.5 py-0.5 text-[10px] font-semibold transition {search.query ===
                            extractRussian(item.title)
                              ? 'bg-accent text-white'
                              : 'text-muted bg-white/10 hover:text-white'}"
                            title="Искать по русскому названию"
                            onclick={() => {
                              search.query = extractRussian(item.title);
                              void runSearch(item);
                            }}
                          >
                            RU
                          </button>
                        </div>
                      {/if}
                    </div>
                    <button
                      type="button"
                      disabled={search.loading}
                      class="bg-accent hover:bg-accent-hover inline-flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-lg text-white transition disabled:cursor-wait disabled:opacity-60"
                      onclick={() => void runSearch(item)}
                    >
                      {#if search.loading}
                        <LoaderCircle size={15} class="animate-spin" />
                      {:else}
                        <Search size={15} aria-hidden="true" />
                      {/if}
                    </button>
                  </div>
                  {#if search.results}
                    <p class="text-muted mt-3 text-[10px] font-bold tracking-wider uppercase">
                      {i18n.t.backgroundJobs.suggestions}
                    </p>
                  {/if}
                {/if}

                {#if candidates.length === 0}
                  <p class="text-muted mt-3 text-xs leading-relaxed">
                    {i18n.t.backgroundJobs.noCandidates}
                  </p>
                {:else}
                  <div
                    class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2 {candidates.length > 4
                      ? 'max-h-[420px] overflow-y-auto [overscroll-behavior:auto] overscroll-auto pr-1.5'
                      : ''}"
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
                            class="bg-canvas h-20 w-14 shrink-0 rounded-lg object-cover ring-1 ring-white/10"
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
                            class="line-clamp-2 text-xs leading-snug font-bold text-white sm:text-sm"
                            title={candidate.title}
                          >
                            {candidate.title}
                          </p>
                          {#if candidate.originalTitle || candidate.romajiTitle}
                            <p class="text-muted truncate text-[11px]">
                              {candidate.originalTitle ?? candidate.romajiTitle}
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
                                class="text-muted rounded bg-white/[0.07] px-1.5 py-0.5 tabular-nums"
                              >
                                {candidate.releaseYear}
                              </span>
                            {/if}
                            {#if (candidate.totalCount ?? candidate.chapters) !== null && (candidate.totalCount ?? candidate.chapters) !== undefined}
                              <span
                                class="text-muted rounded bg-white/[0.07] px-1.5 py-0.5 tabular-nums"
                              >
                                {candidate.totalCount ?? candidate.chapters}
                              </span>
                            {/if}
                            {#if candidate.author || candidate.studio}
                              <span
                                class="text-muted truncate rounded bg-white/[0.07] px-1.5 py-0.5"
                              >
                                {candidate.author ?? candidate.studio}
                              </span>
                            {/if}
                          </div>
                        </div>
                        <button
                          type="button"
                          class="bg-accent hover:bg-accent-hover grid size-10 shrink-0 cursor-pointer place-items-center rounded-xl text-white shadow-md transition active:scale-95"
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
