<script lang="ts">
  import { FileText, Image as ImageIcon, Layers, Quote, RotateCcw, Tag, X } from "$shared/ui/Icons";
  import {
    createMedia,
    errorMessage,
    updateMedia,
  } from "$shared/api/api";
  import { fullSizeCoverUrl, isValidCoverUrl } from "$entities/media/model/coverUrl";
  import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { loadMediaDetail } from "$features/prefetch-details/mediaDetailPrefetch";
  import BaseMediaModule from "./modules/BaseMediaModule.svelte";
  import NotesModule from "./modules/NotesModule.svelte";
  import QuotesModule from "./modules/QuotesModule.svelte";
  import AltTitlesModule from "./modules/AltTitlesModule.svelte";
  import CategoryFieldsModule from "./modules/CategoryFieldsModule.svelte";
  import ImagesModule from "./modules/ImagesModule.svelte";
  import WorkspaceWindow from "./WorkspaceWindow.svelte";
  import {
    COVER_SIZE,
    WORKSPACE_WINDOW_IDS,
    clampPoint,
    clampWindowRect,
    defaultLayout,
    loadLayout,
    minWindowSize,
    saveLayout,
    type WorkspaceLayout,
    type WorkspaceRect,
    type WorkspaceWindowId,
  } from "./workspaceLayout";
  import { ThreadSpring, nearestFaceAnchors, type Rect } from "./workspaceThreads";
  import {
    MEDIA_STATUS,
    type CreateMediaPayload,
    type CreateSeasonPayload,
    type MediaCoverItem,
    type MediaDetail,
    type MediaItem,
    type MediaStatus,
    type MediaQuote,
    type MediaType,
    type UpdateMediaPayload,
  } from "$shared/types";

  interface Props {
    isOpen: boolean;
    onClose: () => void;
    onCreated: (media: MediaItem) => void;
    editingItem?: MediaItem;
  }

  let { isOpen, onClose, onCreated, editingItem }: Props = $props();

  type CreateType = MediaType;

  // ---------------------------------------------------------------------------
  // Editor draft state. The spatial canvas is pure presentation; every field
  // lives here and flows down into the reusable modules through $bindable props.
  // ---------------------------------------------------------------------------
  let type = $state<CreateType>("game");
  let title = $state("");
  let coverUrl = $state("");
  let notes = $state("");
  let score = $state("");
  let startedAt = $state("");
  let finishedAt = $state("");
  let status = $state<MediaStatus>(MEDIA_STATUS.planned);
  let altTitles = $state<string[]>([]);
  let quotes = $state<MediaQuote[]>([]);
  let covers = $state<MediaCoverItem[]>([]);
  let category = $state(emptyCategoryDraft());
  let submitting = $state(false);
  let submitError = $state<unknown>(null);
  let validationError = $state("");
  let editingInitialized = $state(false);

  function emptyCategoryDraft() {
    return {
      platform: "",
      hoursPlayed: "",
      author: "",
      bookFormat: "book",
      totalPages: "",
      totalChapters: "",
      bookTotalVolumes: "",
      currentVolume: "",
      durationMinutes: "",
      isAnime: false,
      studio: "",
      network: "",
      seasons: [] as { seasonNumber: string; title: string; totalEpisodes: string }[],
    };
  }

  $effect(() => {
    if (!isOpen || !editingItem || editingInitialized) return;

    applyEditableFields(editingItem);
    editingInitialized = true;

    const id = editingItem.id;
    void loadMediaDetail(id)
      .then((detail) => {
        if (!isOpen || editingItem?.id !== id) return;
        applyEditableFields(detail);
      })
      .catch(() => {});
  });

  $effect(() => {
    const dialog = dialogElement;
    if (!dialog) return;
    if (isOpen && !dialog.open) {
      dialog.showModal();
      editingInitialized = false;
      submitError = null;
      validationError = "";
    } else if (!isOpen && dialog.open) {
      dialog.close();
    }
  });

  function handleCancel(event: Event) {
    event.preventDefault();
    close();
  }

  function close() {
    if (submitting) return;
    onClose();
  }

  function applyEditableFields(item: MediaItem | MediaDetail) {
    type = item.type;
    title = item.title;
    coverUrl = item.coverUrl ?? "";
    notes = "notes" in item ? (item.notes ?? "") : "";
    score = item.score?.toString() ?? "";
    startedAt = item.startedAt?.slice(0, 16) ?? "";
    finishedAt = item.finishedAt?.slice(0, 16) ?? "";
    status = item.status;

    // The type-specific fields live in one bundle, so it has to be reset on every apply:
    // switching an edited row from a game to a book would otherwise keep the game's platform.
    category = emptyCategoryDraft();
    // Only the detail payload carries alt titles, quotes and covers; a list-shaped row has none.
    altTitles = ("altTitles" in item ? (item.altTitles ?? []) : []).slice();
    quotes = parseQuotes("quotesJson" in item ? item.quotesJson : null);
    covers = "covers" in item ? (item.covers ?? []) : [];

    if (item.type === "game") {
      category.platform = item.platform ?? "";
      category.hoursPlayed = item.hoursPlayed?.toString() ?? "";
    } else if (item.type === "book") {
      const book = item as {
        author?: string;
        format?: string | null;
        totalPages?: number;
        totalChapters?: number | null;
        totalVolumes?: number | null;
      };
      category.author = book.author ?? "";
      category.bookFormat = book.format || "book";
      category.totalPages = book.totalPages?.toString() ?? "";
      category.totalChapters = book.totalChapters?.toString() ?? "";
      category.bookTotalVolumes = book.totalVolumes?.toString() ?? "";
    } else if (item.type === "manga") {
      category.author = item.author ?? "";
      category.totalChapters = item.totalChapters?.toString() ?? "";
      category.currentVolume = item.currentVolume?.toString() ?? "";
      category.totalPages = item.totalVolumes?.toString() ?? "";
    } else if (item.type === "movie") {
      category.durationMinutes = item.durationMinutes?.toString() ?? "";
      category.isAnime = item.isAnime ?? false;
      category.studio = item.studio ?? "";
    } else if (item.type === "tvshow") {
      category.isAnime = item.isAnime ?? false;
      category.studio = item.studio ?? "";
      category.network = item.network ?? "";
      category.seasons = ("seasons" in item ? (item.seasons ?? []) : []).map((season) => ({
        seasonNumber: season.seasonNumber?.toString() ?? "",
        title: season.title ?? "",
        totalEpisodes: season.totalEpisodes?.toString() ?? "",
      }));
    }
  }

  function parseQuotes(json?: string | null): MediaQuote[] {
    if (!json) return [];
    try {
      const parsed: unknown = JSON.parse(json);
      return Array.isArray(parsed) ? (parsed as MediaQuote[]) : [];
    } catch {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Spatial canvas: viewport tracking, layout persistence and z-stacking.
  // ---------------------------------------------------------------------------
  let dialogElement = $state<HTMLDialogElement | null>(null);
  let isDesktop = $state(false);

  function trackDesktop(media: MediaQueryList | MediaQueryListEvent) {
    isDesktop = media.matches;
  }

  $effect(() => {
    const query = window.matchMedia("(min-width: 1024px)");
    trackDesktop(query);
    query.addEventListener("change", trackDesktop);
    return () => query.removeEventListener("change", trackDesktop);
  });

  let layout = $state<WorkspaceLayout>(defaultLayout(1600, 900));
  let zMap = $state<Record<string, number>>({ cover: 1, main: 2, alt: 2, notes: 2, quotes: 2, images: 2 });
  let topZ = $state(10);
  let hoveredId = $state<string | null>(null);
  let draggingId = $state<string | null>(null);

  function bringToFront(id: string) {
    if (zMap[id] === topZ) return;
    topZ += 1;
    zMap[id] = topZ;
  }  function persist() {
    saveLayout($state.snapshot(layout) as WorkspaceLayout);
  }

  function resetLayout() {
    layout = defaultLayout(window.innerWidth, window.innerHeight);
    zMap = { cover: 1, main: 2, alt: 2, notes: 2, quotes: 2, images: 2 };
    topZ = 10;
    persist();
  }

  // Load (or re-clamp) the remembered arrangement every time the editor opens.
  $effect(() => {
    if (!isOpen || !isDesktop) return;
    layout = loadLayout(window.innerWidth, window.innerHeight);
  });

  // A viewport resize must not strand windows off-screen.
  $effect(() => {
    if (!isOpen) return;
    const onResize = () => {
      layout.cover = clampPoint(layout.cover, window.innerWidth, window.innerHeight);
      for (const id of WORKSPACE_WINDOW_IDS) {
        layout.windows[id] = clampWindowRect(layout.windows[id], id, window.innerWidth, window.innerHeight);
      }
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  });

  // ---------------------------------------------------------------------------
  // Living threads: one rAF loop springs every cable toward its freshly-computed
  // anchor pair and writes the path `d` directly to the DOM — no reactive churn
  // per frame, so 144 Hz stays smooth. No SVG filters, ever.
  // ---------------------------------------------------------------------------
  type ThreadKey = "cover-main" | "cover-notes" | "cover-quotes" | "cover-images" | "main-alt";
  const THREADS: { key: ThreadKey; from: string; to: string }[] = [
    { key: "cover-main", from: "cover", to: "main" },
    { key: "cover-notes", from: "cover", to: "notes" },
    { key: "cover-quotes", from: "cover", to: "quotes" },
    { key: "cover-images", from: "cover", to: "images" },
    { key: "main-alt", from: "main", to: "alt" },
  ];

  let threadPaths: Record<ThreadKey, SVGPathElement | null> = $state({
    "cover-main": null,
    "cover-notes": null,
    "cover-quotes": null,
    "cover-images": null,
    "main-alt": null,
  });

  function nodeRect(id: string): Rect {
    if (id === "cover") {
      return { x: layout.cover.x, y: layout.cover.y, w: COVER_SIZE.w, h: COVER_SIZE.h };
    }
    return layout.windows[id as WorkspaceWindowId];
  }

  $effect(() => {
    if (!isOpen || !isDesktop) return;
    const springs = new Map<ThreadKey, ThreadSpring>();
    const firstTargets = new Map<ThreadKey, ReturnType<typeof nearestFaceAnchors>>();
    for (const thread of THREADS) {
      const target = nearestFaceAnchors(nodeRect(thread.from), nodeRect(thread.to));
      firstTargets.set(thread.key, target);
      springs.set(thread.key, new ThreadSpring(target));
    }
    // Seed paths immediately so the cables appear in place instead of flying from (0,0).
    for (const [key, spring] of springs) {
      const target = firstTargets.get(key);
      if (target) spring.step(target, 1);
    }

    let rafId = requestAnimationFrame(tick);
    function tick() {
      for (const thread of THREADS) {
        const spring = springs.get(thread.key);
        const path = threadPaths[thread.key];
        if (!spring || !path) continue;
        const target = nearestFaceAnchors(nodeRect(thread.from), nodeRect(thread.to));
        // Dragging cables get a stiffer spring: they hug the moving window closely.
        const active = draggingId === thread.from || draggingId === thread.to;
        const { d } = spring.step(target, active ? 0.35 : 0.16);
        path.setAttribute("d", d);
      }
      rafId = requestAnimationFrame(tick);
    }

    return () => cancelAnimationFrame(rafId);
  });

  function isThreadActive(thread: { from: string; to: string }): boolean {
    const focus = draggingId ?? hoveredId;
    if (!focus) return false;
    return thread.from === focus || thread.to === focus;
  }

  // ---------------------------------------------------------------------------
  // Cover node dragging (same rAF coalescing, simpler shape: position only).
  // ---------------------------------------------------------------------------
  let coverDrag: null | { pointerId: number; startX: number; startY: number; x: number; y: number } = null;
  let coverPending: { x: number; y: number } | null = null;
  let coverRaf = 0;

  function startCoverDrag(event: PointerEvent) {
    bringToFront("cover");
    draggingId = "cover";
    const node = event.currentTarget as HTMLElement;
    node.setPointerCapture(event.pointerId);
    coverDrag = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      x: layout.cover.x,
      y: layout.cover.y,
    };
  }

  function moveCoverDrag(event: PointerEvent) {
    if (!coverDrag || event.pointerId !== coverDrag.pointerId) return;
    coverPending = {
      x: coverDrag.x + (event.clientX - coverDrag.startX),
      y: coverDrag.y + (event.clientY - coverDrag.startY),
    };
    if (!coverRaf) {
      coverRaf = requestAnimationFrame(() => {
        coverRaf = 0;
        if (!coverPending) return;
        layout.cover = clampPoint(coverPending, window.innerWidth, window.innerHeight);
        coverPending = null;
      });
    }
  }

  function endCoverDrag(event: PointerEvent) {
    if (!coverDrag || event.pointerId !== coverDrag.pointerId) return;
    coverDrag = null;
    draggingId = null;
    if (coverRaf) {
      cancelAnimationFrame(coverRaf);
      coverRaf = 0;
    }
    if (coverPending) {
      layout.cover = clampPoint(coverPending, window.innerWidth, window.innerHeight);
      coverPending = null;
    }
    persist();
  }

  // ---------------------------------------------------------------------------
  // Submission: identical contracts to the plain modal — the workspace is just
  // another front-end over the same payloads.
  // ---------------------------------------------------------------------------
  function numberOrNull(value: string | number): number | null {
    const text = typeof value === "number" ? String(value) : value;
    const parsed = Number(text);
    return text.trim() !== "" && Number.isFinite(parsed) ? parsed : null;
  }

  function optionalText(value: string): string | null {
    return value.trim() || null;
  }

  function buildSeasons(): CreateSeasonPayload[] {
    return category.seasons
      .filter((season) => season.title.trim() || season.totalEpisodes.trim())
      .map((season, index) => ({
        seasonNumber: numberOrNull(season.seasonNumber) ?? index + 1,
        title: season.title.trim() || `${i18n.t.createModal.fields.season} ${index + 1}`,
        totalEpisodes: Math.max(numberOrNull(season.totalEpisodes) ?? 0, 0),
        status: MEDIA_STATUS.planned,
      }));
  }

  function buildPayload(): CreateMediaPayload {
    const altTitleList = altTitles.map((value) => value.trim()).filter(Boolean);

    const common = {
      title: title.trim(),
      status: MEDIA_STATUS.planned,
      altTitles: altTitleList.length > 0 ? altTitleList : undefined,
      coverUrl: optionalText(coverUrl),
      notes: optionalText(notes),
    };

    switch (type) {
      case "game":
        return {
          ...common,
          type: "game",
          platform: category.platform.trim(),
          hoursPlayed: numberOrNull(category.hoursPlayed),
        };
      case "book": {
        const isNovel = category.bookFormat === "light_novel" || category.bookFormat === "web_novel";
        return {
          ...common,
          type: "book",
          author: category.author.trim(),
          format: category.bookFormat || "book",
          totalPages: isNovel ? undefined : numberOrNull(category.totalPages),
          totalChapters: isNovel ? numberOrNull(category.totalChapters) : undefined,
          totalVolumes: isNovel ? numberOrNull(category.bookTotalVolumes) : undefined,
        };
      }
      case "manga":
        return {
          ...common,
          type: "manga",
          author: category.author.trim() || undefined,
          totalChapters: numberOrNull(category.totalChapters),
          currentVolume: numberOrNull(category.currentVolume) ?? 1,
          totalVolumes: numberOrNull(category.totalPages) ?? 1,
        };
      case "movie":
        return {
          ...common,
          type: "movie",
          durationMinutes: numberOrNull(category.durationMinutes),
          isAnime: category.isAnime,
          studio: optionalText(category.studio),
        };
      case "tvshow":
        return {
          ...common,
          type: "tvshow",
          isAnime: category.isAnime,
          studio: optionalText(category.studio),
          network: optionalText(category.network),
          seasons: buildSeasons(),
        };
    }
  }

  async function submit() {
    validationError = "";
    submitError = null;

    if (!title.trim()) {
      validationError = i18n.t.createModal.validation.titleRequired;
      document.getElementById("create-title")?.focus();
      return;
    }

    if (!isValidCoverUrl(coverUrl)) {
      validationError = i18n.t.createModal.validation.coverUrlInvalid;
      return;
    }

    submitting = true;

    try {
      const isNovel = category.bookFormat === "light_novel" || category.bookFormat === "web_novel";
      const saved = editingItem
        ? await updateMedia(editingItem.id, {
            title: title.trim(),
            // An explicit list (even empty) is the intent: the backend applies it as-is.
            altTitles: altTitles.map((value) => value.trim()).filter(Boolean),
            score: numberOrNull(score),
            // Empty strings mean "cleared"; nulls would keep the stored value.
            notes: notes.trim() || "",
            quotesJson: JSON.stringify(quotes),
            coverUrl: coverUrl.trim() || "",
            startedAt: startedAt ? new Date(startedAt).toISOString() : null,
            finishedAt: finishedAt ? new Date(finishedAt).toISOString() : null,
            status,
            platform: type === "game" ? category.platform.trim() : undefined,
            format: type === "book" ? category.bookFormat || "book" : undefined,
            author: type === "book" || type === "manga" ? category.author.trim() : undefined,
            totalPages:
              type === "book" ? (isNovel ? undefined : numberOrNull(category.totalPages)) : undefined,
            totalChapters:
              type === "book"
                ? isNovel
                  ? numberOrNull(category.totalChapters)
                  : undefined
                : type === "manga"
                  ? numberOrNull(category.totalChapters)
                  : undefined,
            totalVolumes:
              type === "book"
                ? isNovel
                  ? numberOrNull(category.bookTotalVolumes)
                  : undefined
                : type === "manga"
                  ? numberOrNull(category.totalPages)
                  : undefined,
          } satisfies UpdateMediaPayload)
        : await createMedia(buildPayload());
      onCreated(saved);
      onClose();
    } catch (error) {
      submitError = error;
    } finally {
      submitting = false;
    }
  }

  function clearSubmitError() {
    submitError = null;
  }

  function handleCoversChange(updated: MediaDetail) {
    covers = updated.covers ?? [];
  }

  const windowIcons = {
    main: Layers,
    alt: Tag,
    notes: FileText,
    quotes: Quote,
    images: ImageIcon,
  } as const;

  function windowTitle(id: WorkspaceWindowId): string {
    if (id === "main") return i18n.t.createModal.modules.main;
    if (id === "alt") return i18n.t.createModal.modules.altTitles;
    return i18n.t.createModal.modules[id];
  }

  function windowCount(id: WorkspaceWindowId): number | undefined {
    if (id === "alt") return altTitles.length;
    if (id === "quotes") return quotes.length;
    if (id === "images") return editingItem ? covers.length : undefined;
    return undefined;
  }

  // Windows render in a fixed DOM order; stacking is handled purely by z-index, so a
  // bringToFront during a drag never re-orders (and would otherwise detach) DOM nodes.
  const renderedWindowIds = WORKSPACE_WINDOW_IDS;
</script>

<dialog
  bind:this={dialogElement}
  aria-labelledby="edit-workspace-title"
  class="m-0 h-dvh max-h-none w-screen max-w-none overflow-visible border-0 bg-transparent p-0 text-ink backdrop:bg-[#0d0f14]/80 backdrop:backdrop-blur-md"
  style="contain: layout style;"
  oncancel={handleCancel}
>
  <!-- Thread layer: fixed to the viewport, always behind the windows. -->
  <svg
    class="pointer-events-none absolute inset-0 hidden size-full lg:block"
    aria-hidden="true"
  >
    {#each THREADS as thread (thread.key)}
      <path
        bind:this={threadPaths[thread.key]}
        fill="none"
        stroke={isThreadActive(thread) ? "rgba(139, 124, 246, 0.6)" : "rgba(255, 255, 255, 0.12)"}
        stroke-width="1.5"
      />
    {/each}
  </svg>

  <!-- Floating control bar -->
  <div class="absolute top-4 left-1/2 z-[9000] -translate-x-1/2">
    <div
      class="flex items-center gap-2 rounded-full border border-white/[0.08] bg-[#12151c]/95 px-4 py-2 shadow-xl shadow-black/40"
    >
      <p id="edit-workspace-title" class="text-ink mr-1 text-xs font-bold tracking-[0.16em] uppercase">
        {editingItem ? i18n.t.createModal.editTitle : i18n.t.createModal.title}
      </p>
      {#if isDesktop}
        <button
          type="button"
          class="text-muted hover:text-ink tap flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-semibold transition hover:bg-white/[0.06]"
          onclick={resetLayout}
          title={i18n.t.editWorkspace.resetLayout}
        >
          <RotateCcw size={13} aria-hidden="true" />
          {i18n.t.editWorkspace.resetLayout}
        </button>
        <span class="mx-1 h-5 w-px bg-white/10"></span>
      {/if}
      <button
        type="button"
        class="text-muted hover:text-ink tap rounded-full px-2.5 py-1.5 text-xs font-semibold transition hover:bg-white/[0.06]"
        onclick={close}>{i18n.t.common.cancel}</button
      >
      <button
        type="button"
        class="tap bg-accent hover:bg-accent-hover rounded-full px-4 py-1.5 text-xs font-semibold text-white transition disabled:cursor-wait disabled:opacity-70"
        disabled={submitting}
        onclick={() => void submit()}
      >
        {submitting ? i18n.t.common.saving : editingItem ? i18n.t.common.save : i18n.t.common.add}
      </button>
      {#if !isDesktop}
        <button
          type="button"
          class="text-muted hover:text-ink grid size-7 place-items-center rounded-full transition hover:bg-white/[0.06]"
          aria-label={i18n.t.common.close}
          onclick={close}
        >
          <X size={15} aria-hidden="true" />
        </button>
      {/if}
    </div>
    {#if validationError || submitError}
      <div class="mt-2 flex flex-col items-center gap-1">
        {#if validationError}
          <p class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-1.5 text-xs text-rose-200" role="alert">
            {validationError}
          </p>
        {/if}
        {#if submitError}
          <button
            type="button"
            class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-1.5 text-xs text-rose-200 transition hover:bg-rose-400/20"
            onclick={clearSubmitError}
          >
            {errorMessage(submitError)}
          </button>
        {/if}
      </div>
    {/if}
  </div>

  {#if isDesktop}
    <!-- Central cover node -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="absolute top-0 left-0 touch-none will-change-transform {draggingId === 'cover'
        ? 'cursor-grabbing'
        : 'cursor-grab'}"
      style:transform={`translate3d(${layout.cover.x}px, ${layout.cover.y}px, 0)`}
      style:width={`${COVER_SIZE.w}px`}
      style:z-index={zMap.cover ?? 1}
      onpointerdown={startCoverDrag}
      onpointermove={moveCoverDrag}
      onpointerup={endCoverDrag}
      onpointercancel={endCoverDrag}
      onpointerenter={() => (hoveredId = "cover")}
      onpointerleave={() => (draggingId === "cover" ? null : (hoveredId = null))}
    >
      <figure
        class="aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.1] bg-[#12151c] shadow-2xl shadow-black/50"
      >
        {#if coverUrl}
          <img
            src={fullSizeCoverUrl(coverUrl)}
            alt={title}
            class="h-full w-full object-cover"
            referrerpolicy="no-referrer"
          />
        {:else}
          <MediaCoverPlaceholder label={i18n.t.activity.coverMissing} />
        {/if}
      </figure>
    </div>

    {#each renderedWindowIds as winId (winId)}
      <WorkspaceWindow
        id={winId}
        title={windowTitle(winId)}
        icon={windowIcons[winId]}
        count={windowCount(winId)}
        rect={layout.windows[winId]}
        z={zMap[winId] ?? 2}
        highlighted={hoveredId === winId || draggingId === winId}
        onFront={() => bringToFront(winId)}
        onHoverChange={(hovered) => (hoveredId = hovered ? winId : null)}
        onDragStateChange={(dragging) => (draggingId = dragging ? winId : null)}
        onSettled={persist}
      >
        {#if winId === "main"}
          <div class="space-y-3">
            <BaseMediaModule
              idPrefix="create"
              bind:type
              bind:title
              bind:score
              bind:status
              bind:startedAt
              bind:finishedAt
            />
            <CategoryFieldsModule {type} bind:category isEditing={Boolean(editingItem)} />
          </div>
        {:else if winId === "alt"}
          <AltTitlesModule bind:altTitles />
        {:else if winId === "notes"}
          <NotesModule bind:notes />
        {:else if winId === "quotes"}
          <QuotesModule bind:quotes />
        {:else}
          <ImagesModule
            mediaId={editingItem?.id ?? null}
            bind:coverUrl
            {title}
            {covers}
            onCoversChange={handleCoversChange}
          />
        {/if}
      </WorkspaceWindow>
    {/each}
  {:else}
    <!-- Mobile: plain scrollable stack over the blurred backdrop. -->
    <div class="thin-scroll absolute inset-0 overflow-y-auto px-4 pt-16 pb-6">
      <div class="mx-auto flex w-32 flex-col items-center gap-3">
        <figure class="aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.1] bg-[#12151c]">
          {#if coverUrl}
            <img
              src={fullSizeCoverUrl(coverUrl)}
              alt={title}
              class="h-full w-full object-cover"
              referrerpolicy="no-referrer"
            />
          {:else}
            <MediaCoverPlaceholder label={i18n.t.activity.coverMissing} />
          {/if}
        </figure>
      </div>
      <div class="mx-auto mt-4 flex w-full max-w-xl flex-col gap-4">
        <section class="rounded-xl border border-white/[0.06] bg-[#12151c]/95 p-4">
          <div class="space-y-3">
            <BaseMediaModule
              idPrefix="create"
              bind:type
              bind:title
              bind:score
              bind:status
              bind:startedAt
              bind:finishedAt
            />
            <CategoryFieldsModule {type} bind:category isEditing={Boolean(editingItem)} />
          </div>
        </section>
        <section class="rounded-xl border border-white/[0.06] bg-[#12151c]/95 p-4">
          <AltTitlesModule bind:altTitles />
        </section>
        <section class="rounded-xl border border-white/[0.06] bg-[#12151c]/95 p-4">
          <NotesModule bind:notes />
        </section>
        <section class="rounded-xl border border-white/[0.06] bg-[#12151c]/95 p-4">
          <QuotesModule bind:quotes />
        </section>
        <section class="rounded-xl border border-white/[0.06] bg-[#12151c]/95 p-4">
          <ImagesModule
            mediaId={editingItem?.id ?? null}
            bind:coverUrl
            {title}
            {covers}
            onCoversChange={handleCoversChange}
          />
        </section>
      </div>
    </div>
  {/if}
</dialog>
