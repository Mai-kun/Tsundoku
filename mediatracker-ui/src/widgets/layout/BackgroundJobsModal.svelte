<script module lang="ts">
  const CYRILLIC_RE = /[а-яА-ЯёЁ]/;
  const LATIN_LETTER_RE = /[a-zA-Z]/;
</script>

<script lang="ts">
  import Modal from "$shared/ui/Modal.svelte";
  import Placeholder404 from "$entities/media/ui/Placeholder404.svelte";
  import ExternalDetailModal from "$widgets/media-detail/ExternalDetailModal.svelte";
  import {
    Activity,
    AlertTriangle,
    Check,
    ChevronRight,
    Eye,
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
    getExternalDetails,
    resolveAllPendingMatchesByPriority,
    resolvePendingMatch,
    searchExternal,
    getSourcePriority,
  } from "$shared/api/api";
  import { parseMediaUrl } from "$shared/utils/urlMediaParser";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type {
    ExternalMedia,
    JobProgress,
    PendingMatchItemDto,
    SearchMediaType,
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
  let previewCandidate = $state<{ item: ExternalMedia; parentItem: PendingMatchItemDto } | null>(
    null,
  );
  let resolvingCandidates = $state<Record<string, boolean>>({});
  /** Master-detail: the row picked in the left list, or null while the list settles. */
  let selectedMatchId = $state<string | null>(null);
  let pendingQuery = $state("");

  const visiblePending = $derived.by(() => {
    const query = pendingQuery.trim().toLowerCase();
    if (!query) return jobsClient.pendingMatches;
    return jobsClient.pendingMatches.filter((item) =>
      [item.title, item.romajiTitle, item.originalTitle].some((title) =>
        title?.toLowerCase().includes(query),
      ),
    );
  });

  const selectedItem = $derived(
    visiblePending.find((item) => item.id === selectedMatchId) ?? visiblePending[0] ?? null,
  );
  const selectedIndex = $derived(
    selectedItem ? visiblePending.findIndex((item) => item.id === selectedItem.id) : -1,
  );

  function candidateType(cand: ExternalMedia, item: PendingMatchItemDto): SearchMediaType {
    if (cand.type === "anime" || item.isAnime) return "anime";
    if (cand.type) return cand.type as SearchMediaType;
    return (item.type as SearchMediaType) || "manga";
  }

  const defaultPriorities: Record<string, string[]> = {
    anime: ["anilist", "shikimori", "kitsu", "simkl", "sociallib"],
    manga: ["anilist", "mangadex", "shikimori", "mangaupdates", "kitsu", "sociallib"],
    movie: ["tmdb", "kinopoisk", "imdb", "simkl"],
    tvshow: ["tmdb", "kinopoisk", "imdb", "simkl"],
    book: ["sociallib", "shikimori", "anilist", "kitsu", "openlibrary"],
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
    // A candidate the user pinned by pasting a direct link is the exact answer, not a guess.
    if (cand.isDirectUrl) return 100;

    const cleanSuffix = (s: string | null | undefined) =>
      (s ?? "").replace(/\s*[\(\[](?:новелла|манхва|манга|сборник|ранобэ)[\)\]]/gi, "").trim();

    const norm = (s: string | null | undefined) =>
      cleanSuffix(s)
        .toLowerCase()
        .replace(/[^a-z0-9а-яё]/gi, "");

    const targets = [
      item.title,
      item.romajiTitle,
      item.originalTitle,
      extractRussian(item.title),
      extractLatin(item.title),
      ...(item.altTitles ?? []),
    ]
      .map(norm)
      .filter(Boolean);

    const candTitles = [cand.title, cand.originalTitle, cand.romajiTitle, ...(cand.synonyms ?? [])]
      .map(norm)
      .filter(Boolean);

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

    // Direct search result base score >= 40% (eliminates false 0% for API matches with shared query tokens)
    if (best === 0) {
      const itemTokens = targets.flatMap((t) => t.match(/[a-z0-9а-яё]{3,}/g) ?? []);
      const candTokens = candTitles.flatMap((c) => c.match(/[a-z0-9а-яё]{3,}/g) ?? []);
      const shared = itemTokens.filter((tok) => candTokens.includes(tok));
      if (
        shared.length > 0 &&
        shared.length / Math.min(itemTokens.length || 1, candTokens.length || 1) >= 0.3
      ) {
        best = 40;
      }
    }

    if (best === 0) return 0;

    let total = best;

    // 1. Release Year
    if (item.releaseYear && cand.releaseYear) {
      const diff = Math.abs(item.releaseYear - cand.releaseYear);
      if (diff <= 1) total += 20;
      else if (diff > 2) total -= 25;
    } else if (best >= 60) {
      total += 20;
    }

    // 2. Author / Studio
    const ia = norm(item.author);
    const ca = norm(cand.author) || norm(cand.studio);
    if (ia && ca) {
      if (ia === ca || ia.includes(ca) || ca.includes(ia)) {
        total += 15;
      } else {
        total -= 40;
      }
    } else if (best >= 60) {
      total += 15;
    }

    // 3. Chapter / Page / Episode Counts
    const ic = item.totalCount ?? 0;
    const cc = cand.totalCount ?? cand.chapters ?? 0;
    if (ic > 0 && cc > 0) {
      const minCount = Math.min(ic, cc);
      const maxCount = Math.max(ic, cc);
      const ratio = minCount / maxCount;
      if (ratio >= 0.8) {
        total += 10;
      } else if (ratio < 0.6) {
        total -= 30;
      }
    } else if (best >= 60) {
      total += 10;
    }

    // 4. Format / Country Mismatch (manhwa vs manga / KR vs JP)
    const resolveFormat = (
      mangaFmt?: string | null,
      fmt?: string | null,
      country?: string | null,
    ) => {
      const mf = (mangaFmt ?? "").toLowerCase().trim();
      if (mf === "manhwa" || mf === "manga" || mf === "manhua") return mf;
      const f = (fmt ?? "").toLowerCase().trim();
      if (f === "manhwa" || f === "manga" || f === "manhua") return f;
      const c = (country ?? "").toUpperCase().trim();
      if (c === "KR") return "manhwa";
      if (c === "JP") return "manga";
      if (c === "CN") return "manhua";
      return null;
    };

    const itemFmt = resolveFormat(item.mangaFormat, null, item.countryOfOrigin);
    const candFmt = resolveFormat(cand.mangaFormat, cand.format, cand.countryOfOrigin);
    let formatMismatch =
      (itemFmt === "manhwa" && candFmt === "manga") ||
      (itemFmt === "manga" && candFmt === "manhwa");

    if (!formatMismatch && item.countryOfOrigin && cand.countryOfOrigin) {
      const ic = item.countryOfOrigin.toUpperCase().trim();
      const cc = cand.countryOfOrigin.toUpperCase().trim();
      if ((ic === "KR" && cc === "JP") || (ic === "JP" && cc === "KR")) {
        formatMismatch = true;
      }
    }

    if (formatMismatch) {
      total -= 20;
    }

    return Math.min(100, Math.max(0, total));
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
    return { open: true, query: getPreferredSearchQuery(item), results: null, loading: false };
  }

  // Every selected row gets its own search draft; a row with no candidates searches itself once.
  $effect(() => {
    const item = selectedItem;
    if (!item || manualSearches[item.id]) return;
    manualSearches[item.id] = emptySearch(item);
    if (!item.candidates || item.candidates.length === 0) void runSearch(item);
  });

  async function runSearch(item: PendingMatchItemDto) {
    const search = manualSearches[item.id];
    if (!search || !search.query.trim() || search.loading) return;

    search.loading = true;
    try {
      // A pasted direct link skips the text search entirely: fetch the exact title and pin it
      // as the single 100% candidate.
      const parsedUrl = parseMediaUrl(search.query.trim());
      if (parsedUrl) {
        const details = await getExternalDetails(
          parsedUrl.type,
          parsedUrl.id,
          "",
          parsedUrl.source,
        );
        if (details) {
          if (!details.type) details.type = parsedUrl.type;
          if (!details.externalSource) details.externalSource = parsedUrl.source;
          if (!details.externalId) details.externalId = parsedUrl.id;
          details.isDirectUrl = true;
          search.results = [details];
        } else {
          search.results = [];
          showToast(i18n.t.searchModal.directLinkError, "error");
        }
        return;
      }

      const trimmedQuery = search.query.trim();
      if (trimmedQuery.startsWith("http://") || trimmedQuery.startsWith("https://")) {
        search.results = [];
        showToast(i18n.t.searchModal.unsupportedLinkError, "error");
        return;
      }

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

  function candidateCount(item: PendingMatchItemDto): number {
    return (manualSearches[item.id]?.results ?? item.candidates ?? []).length;
  }

  /**
   * Auto-advance: keep the cursor on the row after the removed one, falling back to the previous
   * row at the end of the list. Skips never call this — they only move the cursor.
   */
  function advanceSelection(itemId: string) {
    const list = visiblePending;
    const index = list.findIndex((item) => item.id === itemId);
    const next = list[index + 1] ?? list[index - 1] ?? null;
    selectedMatchId = next && next.id !== itemId ? next.id : null;
  }

  function skipCurrent() {
    if (visiblePending.length === 0) return;
    const index = visiblePending.findIndex((item) => item.id === selectedItem?.id);
    selectedMatchId = visiblePending[(index + 1) % visiblePending.length]?.id ?? null;
  }

  function resolve(item: PendingMatchItemDto, candidate: ExternalMedia) {
    const candKey = `${item.id}:${candidate.externalSource}:${candidate.externalId}`;
    resolvingCandidates[candKey] = true;
    advanceSelection(item.id);

    showToast(i18n.t.backgroundJobs.resolvedAsyncToast, "success");
    void resolvePendingMatch(item.id, {
      externalId: String(candidate.externalId),
      source: candidate.externalSource ?? "",
      type: candidate.type || item.type,
      title: candidate.title,
    })
      .catch((error) => showToast(errorMessage(error), "error"))
      .finally(() => {
        delete resolvingCandidates[candKey];
        onMediaChanged?.();
      });

    // The server already queued the highest-priority enrichment, so the row can leave the list now.
    jobsClient.dropPendingMatch(item.id);
  }

  async function keep(item: PendingMatchItemDto) {
    try {
      await dismissPendingMatch(item.id);
      advanceSelection(item.id);
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
    advanceSelection(id);
    jobsClient.dropPendingMatch(id);
    void deleteMedia(id)
      .then(() => showToast(i18n.t.backgroundJobs.deletedToast, "success"))
      .catch((error) => showToast(errorMessage(error), "error"))
      .finally(() => onMediaChanged?.());
  }

  function isTextEntry(target: EventTarget | null): boolean {
    const element = target as HTMLElement | null;
    if (!element) return false;
    return (
      element.tagName === "INPUT" ||
      element.tagName === "TEXTAREA" ||
      element.tagName === "SELECT" ||
      element.isContentEditable
    );
  }

  /** 1–4 pick a candidate, S/Space skips, Delete removes — never while the user is typing. */
  function handleHotkey(event: KeyboardEvent) {
    if (
      !jobsClient.isModalOpen ||
      jobsClient.modalTab !== "review" ||
      previewCandidate ||
      event.ctrlKey ||
      event.metaKey ||
      event.altKey ||
      isTextEntry(event.target) ||
      !selectedItem
    ) {
      return;
    }

    if (event.key >= "1" && event.key <= "4") {
      const candidate = candidatesFor(selectedItem)[Number(event.key) - 1];
      if (!candidate) return;
      event.preventDefault();
      resolve(selectedItem, candidate);
    } else if (event.key === "s" || event.key === "S" || event.key === " ") {
      event.preventDefault();
      skipCurrent();
    } else if (event.key === "Delete") {
      event.preventDefault();
      handleDeleteItem(selectedItem.id);
    }
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
    anilist: "bg-emerald-500/20 text-emerald-300 border border-emerald-500/30",
    shikimori: "bg-sky-500/20 text-sky-300 border border-sky-500/30",
    mangadex: "bg-rose-500/20 text-rose-300 border border-rose-500/30",
    tmdb: "bg-amber-500/20 text-amber-300 border border-amber-500/30",
    kinopoisk: "bg-orange-500/20 text-orange-300 border border-orange-500/30",
    imdb: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30",
    steam: "bg-blue-500/20 text-blue-300 border border-blue-500/30",
    rawg: "bg-purple-500/20 text-purple-300 border border-purple-500/30",
  };

  function sourceBadgeClass(source: string | null | undefined): string {
    return (source && sourceBadges[source.toLowerCase()]) || "bg-white/[0.07] text-slate-300";
  }
</script>

<svelte:window onkeydown={handleHotkey} />

<Modal isOpen={jobsClient.isModalOpen} onClose={() => jobsClient.closeModal()} size="jobs">
  <div class="flex h-full flex-col overflow-hidden">
    <header class="flex shrink-0 flex-col gap-3 border-b border-white/[0.08] px-5 py-4">
      <div class="flex items-center gap-3">
        <div
          class="bg-accent-bright/20 grid h-9 w-9 shrink-0 place-items-center rounded-lg text-[#8f7fff]"
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
            ? 'bg-accent-bright text-white'
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

    <div
      class={jobsClient.modalTab === "jobs"
        ? "thin-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain p-5"
        : "thin-scroll flex min-h-0 flex-1 flex-col overflow-hidden p-4 sm:p-5"}
    >
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
                          : "bg-accent-bright"
                    }`}
                    style={`transform: scaleX(${job.progressPercent / 100})`}
                  ></div>
                </div>

                {#if isBatchImport(job)}
                  <div
                    class="bg-accent-bright/10 mt-2 flex flex-wrap items-center gap-2 rounded-lg px-3 py-2 text-[11px] leading-relaxed text-[#a99cff]"
                  >
                    <p class="min-w-0 flex-1">
                      {i18n.t.backgroundJobs.throttleNotice}
                    </p>
                    {#if etaMinutes(job)}
                      <span
                        class="bg-accent-bright shrink-0 rounded-md px-2 py-0.5 text-[10px] font-bold text-white tabular-nums"
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
          <div class="flex min-h-0 flex-1 flex-col gap-4 md:flex-row">
            <!-- Master list: every unresolved title, filterable and keyboard-driven. -->
            <aside
              class="flex max-h-64 min-h-0 w-full shrink-0 flex-col overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.03] md:max-h-none md:w-80 md:border-r md:border-white/10"
            >
              <div class="shrink-0 space-y-2 border-b border-white/[0.08] p-3">
                <div class="relative">
                  <Search
                    size={14}
                    class="text-muted pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2"
                    aria-hidden="true"
                  />
                  <input
                    type="search"
                    bind:value={pendingQuery}
                    placeholder={i18n.t.backgroundJobs.listSearchPlaceholder}
                    class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 py-1.5 pr-3 pl-8 text-xs transition outline-none focus:ring-1"
                  />
                </div>
                <div
                  class="text-muted flex items-center justify-between text-[11px] font-medium tabular-nums"
                >
                  <span
                    >[ {selectedIndex >= 0 ? selectedIndex + 1 : 0} / {visiblePending.length} ]</span
                  >
                  <span>{i18n.t.backgroundJobs.pendingShort}</span>
                </div>
              </div>

              <ul
                class="thin-scroll min-h-0 flex-1 space-y-1 overflow-y-auto overscroll-contain p-2"
              >
                {#each visiblePending as item (item.id)}
                  {@const active = item.id === selectedItem?.id}
                  <li>
                    <button
                      type="button"
                      class={`w-full cursor-pointer rounded-xl border px-2.5 py-2 text-left transition ${
                        active
                          ? "border-accent/60 bg-accent/15 text-white shadow-sm"
                          : "border-transparent text-slate-300 hover:bg-white/[0.05]"
                      }`}
                      aria-current={active ? "true" : undefined}
                      onclick={() => (selectedMatchId = item.id)}
                    >
                      <span class="block truncate text-xs font-semibold">{item.title}</span>
                      <span class="mt-1 flex items-center gap-1.5 text-[10px]">
                        <span
                          class="bg-accent-bright/20 rounded px-1.5 py-0.5 font-semibold text-[#8f7fff]"
                        >
                          {item.type}{item.isAnime ? " · anime" : ""}
                        </span>
                        <span
                          class="text-muted rounded bg-white/[0.06] px-1.5 py-0.5 font-medium tabular-nums"
                          title={i18n.t.backgroundJobs.suggestions}
                        >
                          {candidateCount(item)}
                        </span>
                      </span>
                    </button>
                  </li>
                {:else}
                  <li class="text-muted p-3 text-xs">
                    {i18n.t.backgroundJobs.noListResults}
                  </li>
                {/each}
              </ul>

              <div class="shrink-0 border-t border-white/[0.08] p-2">
                <p class="text-muted px-1 pb-2 text-center text-[10px] leading-relaxed">
                  {i18n.t.backgroundJobs.hotkeysHint}
                </p>
                <button
                  type="button"
                  class="bg-field hover:bg-elevated inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 transition hover:text-white"
                  onclick={skipCurrent}
                >
                  <ChevronRight size={14} aria-hidden="true" />
                  {i18n.t.backgroundJobs.skipNext}
                </button>
              </div>
            </aside>

            <!-- Detail: the selected title and its candidate grid. -->
            <section
              class="thin-scroll min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain rounded-2xl border border-white/[0.08] bg-white/[0.02]"
            >
              {#if selectedItem}
                {@const item = selectedItem}
                {@const search = manualSearches[item.id] ?? emptySearch(item)}
                {@const candidates = candidatesFor(item)}
                <div
                  class="sticky top-0 z-10 border-b border-white/[0.08] bg-[#151a26] px-4 py-2.5"
                >
                  <!-- Row 1: identity + quick actions -->
                  <div class="flex items-center justify-between gap-2">
                    <div class="flex min-w-0 items-center gap-2">
                      <span
                        class="bg-accent-bright/20 shrink-0 rounded-md px-2 py-0.5 text-[10px] font-semibold text-[#8f7fff]"
                      >
                        {item.type}{item.isAnime ? " · anime" : ""}
                      </span>
                      <h3 class="text-ink min-w-0 truncate text-sm font-bold" title={item.title}>
                        {item.title}
                        {#if item.originalTitle || (item.romajiTitle && item.romajiTitle !== item.title)}
                          <span class="text-muted ml-1 text-xs font-normal">
                            ({item.originalTitle ?? item.romajiTitle})
                          </span>
                        {/if}
                      </h3>
                      {#if item.currentProgress !== null && item.currentProgress !== undefined}
                        <span
                          class="text-muted shrink-0 rounded-md bg-white/[0.06] px-2 py-0.5 text-[10px] font-medium tabular-nums"
                        >
                          {item.currentProgress}{item.totalCount ? ` / ${item.totalCount}` : ""}
                          {item.isAnime || item.type === "tvshow" || item.type === "anime"
                            ? " эп."
                            : " гл."}
                        </span>
                      {/if}
                    </div>

                    <div class="flex shrink-0 items-center gap-1.5">
                      <button
                        type="button"
                        class="bg-field hover:bg-elevated inline-flex size-8 cursor-pointer items-center justify-center rounded-lg border border-white/10 text-slate-300 transition hover:text-white"
                        title="Оставить как есть (без привязки)"
                        aria-label={i18n.t.backgroundJobs.keepAsIs}
                        onclick={() => void keep(item)}
                      >
                        <X size={15} aria-hidden="true" />
                      </button>
                      <button
                        type="button"
                        class="inline-flex size-8 cursor-pointer items-center justify-center rounded-lg border border-rose-500/20 bg-rose-500/10 text-rose-400 transition hover:border-rose-500/40 hover:bg-rose-500/20"
                        title="Удалить тайтл из библиотеки"
                        aria-label={i18n.t.backgroundJobs.delete}
                        onclick={() => handleDeleteItem(item.id)}
                      >
                        <Trash2 size={15} aria-hidden="true" />
                      </button>
                    </div>
                  </div>

                  <!-- Row 2: search field with in-field language toggles -->
                  <div class="mt-2 flex items-center gap-2">
                    <div
                      class="bg-field focus-within:border-accent-soft focus-within:ring-accent-soft flex min-w-0 flex-1 items-center rounded-lg border border-white/10 transition focus-within:ring-1"
                    >
                      <input
                        type="search"
                        bind:value={search.query}
                        placeholder={i18n.t.backgroundJobs.searchPlaceholder}
                        class="text-ink min-w-0 flex-1 bg-transparent px-3 py-1.5 text-sm outline-none placeholder:text-zinc-500"
                        onkeydown={(event) => {
                          if (event.key === "Enter") void runSearch(item);
                        }}
                      />
                      <div class="flex shrink-0 items-center gap-1 pr-2">
                        <button
                          type="button"
                          class="cursor-pointer rounded-md border px-1.5 py-0.5 text-[10px] font-bold transition {search.query ===
                          extractRussian(item.title)
                            ? 'border-accent bg-accent text-white'
                            : 'text-muted border-white/10 bg-white/[0.04] hover:text-white'}"
                          title="Искать по русскому названию"
                          onclick={() => {
                            search.query = extractRussian(item.title);
                            void runSearch(item);
                          }}
                        >
                          RU
                        </button>
                        <button
                          type="button"
                          class="cursor-pointer rounded-md border px-1.5 py-0.5 text-[10px] font-bold transition {search.query ===
                          getPreferredSearchQuery(item)
                            ? 'border-accent bg-accent text-white'
                            : 'text-muted border-white/10 bg-white/[0.04] hover:text-white'}"
                          title="Искать по латинице / Romaji"
                          onclick={() => {
                            search.query = getPreferredSearchQuery(item);
                            void runSearch(item);
                          }}
                        >
                          EN
                        </button>
                      </div>
                    </div>
                    <button
                      type="button"
                      disabled={search.loading}
                      class="bg-accent hover:bg-accent-hover inline-flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-lg text-white transition disabled:cursor-wait disabled:opacity-60"
                      title={i18n.t.backgroundJobs.findManually}
                      aria-label={i18n.t.backgroundJobs.findManually}
                      onclick={() => void runSearch(item)}
                    >
                      {#if search.loading}
                        <LoaderCircle size={15} class="animate-spin" />
                      {:else}
                        <Search size={15} aria-hidden="true" />
                      {/if}
                    </button>
                  </div>
                </div>

                <div class="space-y-3 p-4">
                  <div class="flex items-center gap-2">
                    <div class="min-w-0 flex-1">
                      <input
                        type="search"
                        bind:value={search.query}
                        placeholder={i18n.t.backgroundJobs.searchPlaceholder}
                        class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
                        onkeydown={(event) => {
                          if (event.key === "Enter") void runSearch(item);
                        }}
                      />
                    </div>
                    <button
                      type="button"
                      disabled={search.loading}
                      class="bg-accent hover:bg-accent-hover inline-flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-lg text-white transition disabled:cursor-wait disabled:opacity-60"
                      title={i18n.t.backgroundJobs.findManually}
                      aria-label={i18n.t.backgroundJobs.findManually}
                      onclick={() => void runSearch(item)}
                    >
                      {#if search.loading}
                        <LoaderCircle size={15} class="animate-spin" />
                      {:else}
                        <Search size={15} aria-hidden="true" />
                      {/if}
                    </button>
                  </div>

                  {#if candidates.length === 0}
                    <p class="text-muted text-xs leading-relaxed">
                      {i18n.t.backgroundJobs.noCandidates}
                    </p>
                  {:else}
                    <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
                      {#each candidates as candidate, index (candidate.externalSource + candidate.externalId)}
                        {@const key = candidate.externalSource + candidate.externalId}
                        {@const candKey = `${item.id}:${candidate.externalSource}:${candidate.externalId}`}
                        {@const isResolving = Boolean(resolvingCandidates[candKey])}
                        {@const match = scoreCandidate(item, candidate)}
                        <div
                          class="relative flex gap-4 rounded-2xl border border-white/[0.08] bg-white/[0.03] p-3.5 shadow-sm transition hover:border-white/20 hover:bg-white/[0.06] sm:p-4"
                        >
                          <button
                            type="button"
                            class="group/poster relative aspect-[2/3] w-24 shrink-0 cursor-pointer overflow-hidden rounded-xl shadow-md ring-1 ring-white/10 transition hover:ring-white/25 active:scale-[0.98] sm:w-28"
                            title="Нажмите для подробного просмотра"
                            onclick={() =>
                              (previewCandidate = { item: candidate, parentItem: item })}
                          >
                            {#if candidate.coverUrl && !candidateImgErrors[key]}
                              <img
                                src={candidate.coverUrl}
                                alt={candidate.title}
                                referrerpolicy="no-referrer"
                                class="bg-canvas h-full w-full object-cover transition-transform duration-300 group-hover/poster:scale-105"
                                loading="lazy"
                                decoding="async"
                                onerror={() => (candidateImgErrors[key] = true)}
                              />
                            {:else}
                              <div class="h-full w-full">
                                <Placeholder404 />
                              </div>
                            {/if}
                            <div
                              class="absolute inset-0 grid place-items-center bg-black/40 opacity-0 backdrop-blur-[1px] transition-opacity duration-200 group-hover/poster:opacity-100"
                            >
                              <Eye size={20} class="text-white drop-shadow-md" />
                            </div>
                          </button>

                          <div class="flex min-w-0 flex-1 flex-col">
                            <div class="flex items-start gap-1.5">
                              {#if index < 4}
                                <span
                                  class="bg-accent-bright mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-md text-[10px] font-bold text-white"
                                >
                                  {index + 1}
                                </span>
                              {/if}
                              <p
                                class="line-clamp-2 text-sm leading-snug font-bold tracking-tight text-white sm:text-base"
                                title={candidate.title}
                              >
                                {candidate.title}
                              </p>
                            </div>
                            {#if candidate.originalTitle || candidate.romajiTitle}
                              <p class="text-muted mt-0.5 truncate text-xs">
                                {candidate.originalTitle ?? candidate.romajiTitle}
                              </p>
                            {/if}

                            <div
                              class="mt-2 flex flex-wrap items-center gap-1.5 text-[10px] sm:text-[11px]"
                            >
                              {#if candidate.externalSource}
                                <span
                                  class="rounded-md px-2 py-0.5 font-bold tracking-wide {sourceBadgeClass(
                                    candidate.externalSource,
                                  )}"
                                >
                                  {candidate.externalSource}
                                </span>
                              {/if}
                              {#if candidate.releaseYear}
                                <span
                                  class="text-muted rounded-md bg-white/[0.07] px-2 py-0.5 font-medium tabular-nums"
                                >
                                  {candidate.releaseYear}
                                </span>
                              {/if}
                              {#if (candidate.totalCount ?? candidate.chapters) !== null && (candidate.totalCount ?? candidate.chapters) !== undefined}
                                <span
                                  class="text-muted rounded-md bg-white/[0.07] px-2 py-0.5 font-medium tabular-nums"
                                >
                                  {candidate.totalCount ?? candidate.chapters}
                                  {candidate.type === "anime" || item.isAnime ? "эп." : "гл."}
                                </span>
                              {/if}
                              {#if candidate.author || candidate.studio}
                                <span
                                  class="text-muted max-w-[140px] truncate rounded-md bg-white/[0.07] px-2 py-0.5 font-medium"
                                  title={candidate.author ?? candidate.studio}
                                >
                                  {candidate.author ?? candidate.studio}
                                </span>
                              {/if}
                              <span
                                class="rounded-md border border-emerald-500/30 bg-emerald-500/15 px-2 py-0.5 font-bold text-emerald-300 tabular-nums"
                                title={i18n.t.backgroundJobs.matchScore(match)}
                              >
                                {i18n.t.backgroundJobs.matchScore(match)}
                              </span>
                            </div>

                            <div class="mt-auto flex gap-2 pt-3">
                              <button
                                type="button"
                                disabled={isResolving}
                                class="bg-accent hover:bg-accent-hover inline-flex min-w-0 flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-xs font-bold text-white shadow-sm transition active:scale-95 disabled:cursor-wait"
                                title="Выбрать этот вариант"
                                onclick={() => resolve(item, candidate)}
                              >
                                {#if isResolving}
                                  <LoaderCircle size={14} class="animate-spin" />
                                {:else}
                                  <Check size={14} stroke-width={2.5} />
                                {/if}
                                <span class="truncate">{i18n.t.backgroundJobs.choose}</span>
                              </button>
                              <button
                                type="button"
                                class="bg-field hover:bg-elevated inline-flex shrink-0 cursor-pointer items-center justify-center gap-1.5 rounded-lg border border-white/10 px-3 py-2 text-xs font-medium text-slate-300 transition hover:text-white"
                                title="Подробнее"
                                aria-label="Подробнее"
                                onclick={() =>
                                  (previewCandidate = { item: candidate, parentItem: item })}
                              >
                                <Eye size={14} aria-hidden="true" />
                                <span>{i18n.t.common.details}</span>
                              </button>
                            </div>
                          </div>
                        </div>
                      {/each}
                    </div>
                  {/if}
                </div>
              {/if}
            </section>
          </div>
        {/if}
      {/if}
    </div>
  </div>
</Modal>

{#if previewCandidate}
  <ExternalDetailModal
    item={previewCandidate.item}
    type={candidateType(previewCandidate.item, previewCandidate.parentItem)}
    onClose={() => (previewCandidate = null)}
  >
    {#snippet actions()}
      <button
        type="button"
        class="inline-flex cursor-pointer items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-xs font-bold text-white shadow-md transition hover:bg-emerald-500 active:scale-95"
        onclick={() => {
          const pc = previewCandidate;
          previewCandidate = null;
          if (pc) {
            resolve(pc.parentItem, pc.item);
          }
        }}
      >
        <Check size={16} stroke-width={2.5} />
        <span>{i18n.t.backgroundJobs.choose}</span>
      </button>
    {/snippet}
  </ExternalDetailModal>
{/if}
