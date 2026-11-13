<script lang="ts">
  import { slide } from "svelte/transition";
  import { onMount } from "svelte";
  import { apiFetch, errorMessage, getSources } from "$shared/api/api";
  import type { SourceInfo } from "$shared/types";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import Select from "$shared/ui/Select.svelte";
  import { buildSourceUrl } from "$shared/utils/sourceUrlHelper";
  import { parseMediaUrl } from "$shared/utils/urlMediaParser";
  import { ChevronDown, Crown, ExternalLink, Link2, Pencil, Plus, Trash2 } from "$shared/ui/Icons";

  interface LinkedSource {
    source: string;
    externalId: string;
    url: string | null;
    isPrimary: boolean;
    title: string | null;
    providedFields: string[] | null;
  }

  interface Props {
    mediaId: string;
    mediaType: string;
    /** The parent's media object; a new identity means the card was refetched (e.g. the
     * enrichment job just committed) and the bound-source list must reload without F5. */
    media?: unknown;
    /** Fired after any successful mutation so the parent can refresh the card. */
    onChanged?: () => void;
    /** Opens the full relink modal (re-pointing the primary source). */
    onOpenRelink?: () => void;
  }

  let { mediaId, mediaType, media, onChanged, onOpenRelink }: Props = $props();

  interface SourceOption {
    value: string;
    label: string;
  }

  let sources = $state<LinkedSource[]>([]);
  let loading = $state(true);
  let loadError = $state<unknown>(null);
  let busy = $state("");
  let addOpen = $state(false);
  let addSource = $state("");
  let addId = $state("");
  let sourceOptions = $state<SourceOption[]>([]);
  // "Taken data" chips stay folded behind an "N fields" button by default; a row with 10-14
  // chips buried the title/id above them. Expanded state is tracked per source.
  let expandedFields = $state<Record<string, boolean>>({});

  function toggleFields(source: string) {
    expandedFields = { ...expandedFields, [source]: !expandedFields[source] };
  }

  /** Used when the settings source list has not loaded (or failed): the type's usual suspects. */
  function fallbackOptions(): Record<string, SourceOption[]> {
    const kinopoisk = { value: "kinopoisk", label: i18n.t.detail.linkedSourcesKinopoisk };
    return {
      anime: [
        { value: "anilist", label: "AniList" },
        { value: "shikimori", label: "Shikimori" },
        { value: "animelib", label: "AnimeLib" },
        { value: "kitsu", label: "Kitsu" },
      ],
      manga: [
        { value: "mangalib", label: "MangaLib" },
        { value: "mangadex", label: "MangaDex" },
        { value: "shikimori", label: "Shikimori" },
        { value: "anilist", label: "AniList" },
      ],
      book: [
        { value: "ranobelib", label: "RanobeLib" },
        { value: "openlibrary", label: "OpenLibrary" },
      ],
      movie: [{ value: "tmdb", label: "TMDb" }, kinopoisk, { value: "imdb", label: "IMDb" }],
      tvshow: [
        { value: "tmdb", label: "TMDb" },
        kinopoisk,
        { value: "imdb", label: "IMDb" },
        { value: "tvdb", label: "TVDB" },
      ],
      game: [
        { value: "steam", label: "Steam" },
        { value: "rawg", label: "RAWG" },
      ],
    };
  }

  /**
   * The add form offers only what fits this title: sources enabled in settings that declare the
   * media type, minus the ones already linked. The SocialLib umbrella is offered as the concrete
   * site it fronts (AnimeLib / MangaLib / RanobeLib), matching the per-site names enrichment binds.
   */
  function toOption(info: SourceInfo): SourceOption | null {
    if (!info.isEnabled || !info.mediaTypes?.includes(mediaType)) return null;
    const id = info.id.toLowerCase();
    if (id === "sociallib") {
      if (mediaType === "anime") return { value: "animelib", label: "AnimeLib" };
      if (mediaType === "manga") return { value: "mangalib", label: "MangaLib" };
      if (mediaType === "book") return { value: "ranobelib", label: "RanobeLib" };
      return null;
    }
    return { value: id, label: info.name };
  }

  const normalizeKey = (source: string) => source.trim().toLowerCase();

  const availableOptions = $derived(
    sourceOptions.filter((option) => !sources.some((s) => normalizeKey(s.source) === option.value)),
  );

  function siteUrl(source: LinkedSource): string | null {
    return source.url ?? buildSourceUrl(source.source, source.externalId, mediaType);
  }

  async function load() {
    loading = true;
    loadError = null;
    try {
      const response = await apiFetch(`/api/media/${mediaId}/linked-sources`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      sources = await response.json();
    } catch (error) {
      loadError = error;
    } finally {
      loading = false;
    }
  }

  async function loadSourceOptions() {
    try {
      const infos = await getSources();
      sourceOptions = infos
        .map(toOption)
        .filter((option): option is SourceOption => option !== null);
    } catch {
      sourceOptions = fallbackOptions()[mediaType] ?? [];
    }
    if (!sourceOptions.some((option) => option.value === addSource)) {
      addSource = sourceOptions[0]?.value ?? "";
    }
  }

  async function mutate(action: () => Promise<Response>, successMessage: string) {
    try {
      const response = await action();
      if (!response.ok) throw new Error(await response.text());
      sources = await response.json();
      showToast({ title: successMessage, description: i18n.t.toast.descUpdated });
      onChanged?.();
    } catch (error) {
      showToast({ title: i18n.t.toast.actionFailed, description: errorMessage(error), type: "error" });
    }
  }

  function add() {
    const raw = addId.trim();
    if (!raw || !addSource || busy) return;

    // A pasted link ("https://mangadex.org/title/<uuid>/...") is resolved to the bare id, and the
    // target source follows the link's site when that source is still addable — typing the URL
    // into the id field used to bind the whole URL as the external id.
    let externalId = raw;
    let sourceKey = addSource;
    const parsed = /^https?:\/\//i.test(raw) ? parseMediaUrl(raw) : null;
    if (parsed) {
      externalId = parsed.id;
      const linkIsAddable =
        !sources.some((s) => normalizeKey(s.source) === parsed.source) &&
        sourceOptions.some((o) => o.value === parsed.source);
      if (linkIsAddable) sourceKey = parsed.source;
    }

    const payload = JSON.stringify({ source: sourceKey, externalId });
    busy = "add";
    void mutate(
      () =>
        apiFetch(`/api/media/${mediaId}/linked-sources`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: payload,
        }),
      i18n.t.detail.linkedSourcesAdded,
    ).finally(() => {
      busy = "";
      addOpen = false;
      addId = "";
    });
  }

  function makePrimary(source: LinkedSource) {
    if (busy) return;
    busy = `primary:${source.source}`;
    void mutate(
      () =>
        apiFetch(
          `/api/media/${mediaId}/linked-sources/${encodeURIComponent(source.source)}/primary`,
          { method: "PUT" },
        ),
      i18n.t.detail.linkedSourcesUpdated,
    ).finally(() => (busy = ""));
  }

  function remove(source: LinkedSource) {
    if (busy) return;
    busy = `remove:${source.source}`;
    void mutate(
      () =>
        apiFetch(`/api/media/${mediaId}/linked-sources/${encodeURIComponent(source.source)}`, {
          method: "DELETE",
        }),
      i18n.t.detail.linkedSourcesUpdated,
    ).finally(() => (busy = ""));
  }

  onMount(() => {
    void load();
    void loadSourceOptions();
  });

  // The binding table lives in the DB row and grows while the enrichment job runs: after
  // add-by-link the card refetches (media identity flips), and the panel must follow —
  // otherwise the new sources only appear after a manual F5.
  $effect(() => {
    void media;
    if (mediaId) void load();
  });
</script>

<section
  class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
>
  <!-- Section header -->
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-2">
      <Link2 size={16} class="text-accent-soft shrink-0" aria-hidden="true" />
      <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
        {i18n.t.detail.linkedSourcesTitle}
      </h2>
      {#if sources.length > 0}
        <span class="rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-bold text-slate-300">
          {sources.length}
        </span>
      {/if}
    </div>

    <button
      type="button"
      class="tap hover:border-accent hover:bg-accent/20 grid size-8 cursor-pointer place-items-center rounded-lg border border-white/10 bg-white/5 text-slate-300 transition hover:text-white"
      onclick={() => (addOpen = !addOpen)}
      title={i18n.t.detail.linkedSourcesAdd}
      aria-label={i18n.t.detail.linkedSourcesAdd}
    >
      <Plus size={16} />
    </button>
  </div>

  {#if addOpen}
    <form
      class="mt-3 mb-4 flex flex-wrap items-end gap-2 rounded-xl border border-white/5 bg-white/[0.02] p-3.5"
      onsubmit={(event) => {
        event.preventDefault();
        add();
      }}
    >
      <label class="block min-w-36 flex-1 space-y-1 text-xs font-medium text-white">
        {i18n.t.detail.linkedSourcesSourceLabel}
        <Select
          id="linked-source-select"
          options={availableOptions}
          value={addSource}
          onChange={(value) => (addSource = value)}
          disabled={availableOptions.length === 0}
          placeholder={availableOptions.length === 0 ? "—" : ""}
          class="h-9 w-full text-xs"
          label={i18n.t.detail.linkedSourcesSourceLabel}
        />
      </label>
      <label class="block min-w-40 flex-[2] space-y-1 text-xs font-medium text-white">
        {i18n.t.detail.linkedSourcesIdLabel}
        <input
          type="text"
          bind:value={addId}
          placeholder="35160--slug"
          class="bg-canvas focus:border-accent h-9 w-full rounded-lg border border-white/10 px-2.5 text-xs outline-none"
        />
      </label>
      <button
        type="submit"
        disabled={!addId.trim() || !addSource || busy === "add"}
        class="bg-accent hover:bg-accent-hover h-9 rounded-lg px-3.5 text-xs font-semibold text-white transition disabled:opacity-50"
      >
        {i18n.t.detail.linkedSourcesLink}
      </button>
    </form>
  {/if}

  {#if loading}
    <div class="h-16 animate-pulse rounded-xl bg-white/[0.03]"></div>
  {:else if loadError}
    <p class="text-muted text-xs">{i18n.t.detail.linkedSourcesLoadError}</p>
  {:else if sources.length === 0}
    <p class="text-muted text-xs">{i18n.t.detail.linkedSourcesEmpty}</p>
  {:else}
    <!-- Ultra-minimal source rows: the collapsed line carries only the service name and the
         field counter; the title and provenance chips unfold underneath via slide. -->
    <div class="space-y-1.5 pt-1">
      {#each sources as item (item.source + item.externalId)}
        <div
          class="rounded-lg border border-white/5 bg-white/[0.02] px-3 py-2 transition-colors hover:border-white/10"
        >
          <div class="flex items-center gap-2">
            <span
              class="min-w-0 flex-1 truncate text-sm font-bold tracking-tight text-white"
              title={item.source}
            >
              {item.source}
            </span>

            {#if !(item.providedFields && item.providedFields.length > 0)}
              <!-- No field counter to expand: the bound title stays on the line. -->
              {#if siteUrl(item)}
                <a
                  href={siteUrl(item) ?? "#"}
                  target="_blank"
                  rel="noreferrer"
                  class="text-accent-soft min-w-0 truncate text-xs font-medium transition-colors duration-150 hover:underline"
                  title={item.title || item.externalId || item.source}
                >
                  {item.title || item.externalId || item.source}
                </a>
              {:else}
                <span
                  class="text-muted min-w-0 truncate text-xs font-medium"
                  title={item.title || item.externalId || item.source}
                >
                  {item.title || item.externalId || item.source}
                </span>
              {/if}
            {/if}

            <div class="flex shrink-0 items-center gap-0.5">
              {#if item.providedFields && item.providedFields.length > 0}
                <!-- Bare field counter: just the number and a flipping chevron. -->
                <button
                  type="button"
                  class="flex cursor-pointer items-center gap-1 px-1 py-1 text-xs font-medium text-white/50 transition-colors hover:text-white"
                  title={i18n.t.detail.linkedSourcesFieldsCount(item.providedFields.length)}
                  aria-label={i18n.t.detail.linkedSourcesFieldsCount(item.providedFields.length)}
                  aria-expanded={!!expandedFields[item.source]}
                  onclick={() => toggleFields(item.source)}
                >
                  {item.providedFields.length}
                  <ChevronDown
                    size={12}
                    class={`transition-transform duration-200 ${expandedFields[item.source] ? "rotate-180" : ""}`}
                    aria-hidden="true"
                  />
                </button>
              {/if}

              {#if siteUrl(item)}
                <a
                  href={siteUrl(item) ?? "#"}
                  target="_blank"
                  rel="noreferrer"
                  class="flex h-7 w-7 items-center justify-center text-white/40 transition-colors hover:text-white"
                  title={i18n.t.detail.linkedSourcesOpen}
                  aria-label={i18n.t.detail.linkedSourcesOpen}
                >
                  <ExternalLink size={14} aria-hidden="true" />
                </a>
              {:else}
                <span class="h-7 w-7" aria-hidden="true"></span>
              {/if}

              {#if item.isPrimary}
                <span
                  class="grid h-7 w-7 place-items-center text-amber-400 transition-colors duration-200"
                  title={i18n.t.detail.linkedSourcesPrimarySource}
                  aria-label={i18n.t.detail.linkedSourcesPrimarySource}
                >
                  <Crown size={15} class="fill-amber-400/25" aria-hidden="true" />
                </span>
              {:else}
                <button
                  type="button"
                  class="grid h-7 w-7 cursor-pointer place-items-center text-white/25 transition-colors duration-200 hover:text-amber-400 disabled:cursor-not-allowed disabled:opacity-50"
                  title={i18n.t.detail.linkedSourcesMakePrimary}
                  aria-label={i18n.t.detail.linkedSourcesMakePrimary}
                  disabled={busy === `primary:${item.source}`}
                  onclick={() => makePrimary(item)}
                >
                  <Crown size={15} aria-hidden="true" />
                </button>
              {/if}

              <button
                type="button"
                class="flex h-7 w-7 cursor-pointer items-center justify-center text-white/40 transition-colors hover:text-white"
                title={i18n.t.detail.linkedSourcesRelink}
                aria-label={i18n.t.detail.linkedSourcesRelink}
                onclick={() => onOpenRelink?.()}
              >
                <Pencil size={14} aria-hidden="true" />
              </button>

              {#if !item.isPrimary}
                <button
                  type="button"
                  class="flex h-7 w-7 cursor-pointer items-center justify-center text-white/30 transition-colors hover:text-rose-400 disabled:cursor-not-allowed disabled:opacity-50"
                  title={i18n.t.detail.linkedSourcesRemove}
                  aria-label={i18n.t.detail.linkedSourcesRemove}
                  disabled={busy === `remove:${item.source}`}
                  onclick={() => remove(item)}
                >
                  <Trash2 size={14} aria-hidden="true" />
                </button>
              {:else}
                <!-- Invisible spacer: keeps every icon column aligned across the list. -->
                <span class="h-7 w-7 invisible pointer-events-none" aria-hidden="true"></span>
              {/if}
            </div>
          </div>

          {#if item.providedFields && item.providedFields.length > 0 && expandedFields[item.source]}
            <div transition:slide={{ duration: 180 }} class="space-y-1.5 pt-2">
              <div class="flex items-center gap-2 text-xs">
                <span class="text-muted shrink-0">{item.source}:</span>
                {#if siteUrl(item)}
                  <a
                    href={siteUrl(item) ?? "#"}
                    target="_blank"
                    rel="noreferrer"
                    class="text-accent-soft inline-flex min-w-0 items-center gap-1 font-medium transition-colors duration-150 hover:underline"
                    title={item.title || item.externalId || item.source}
                  >
                    <span class="truncate">{item.title || item.externalId || item.source}</span>
                    <ExternalLink size={11} class="shrink-0" aria-hidden="true" />
                  </a>
                {:else}
                  <span class="text-muted min-w-0 truncate">
                    {item.title || item.externalId || item.source}
                  </span>
                {/if}
              </div>
              <div class="flex flex-wrap items-center gap-1">
                <span class="mr-1 text-[11px] text-slate-500"
                  >{i18n.t.detail.linkedSourcesTakenLabel}</span
                >
                {#each item.providedFields as field (field)}
                  <span
                    class="rounded border border-white/5 bg-white/[0.04] px-1.5 py-0.5 text-[10px] text-slate-300"
                  >
                    {field}
                  </span>
                {/each}
                <button
                  type="button"
                  class="text-muted ml-1 inline-flex h-5 w-5 cursor-pointer items-center justify-center rounded transition-colors hover:text-white"
                  title={i18n.t.detail.altTitlesLess}
                  aria-label={i18n.t.detail.altTitlesLess}
                  onclick={() => toggleFields(item.source)}
                >
                  <ChevronDown size={11} class="rotate-180" aria-hidden="true" />
                </button>
              </div>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</section>
