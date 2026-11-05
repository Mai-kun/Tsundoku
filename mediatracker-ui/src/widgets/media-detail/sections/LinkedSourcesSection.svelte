<script lang="ts">
  import { onMount } from "svelte";
  import { apiFetch, errorMessage } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { buildSourceUrl } from "$shared/utils/sourceUrlHelper";
  import { Check, ExternalLink, Link2, Plus, Trash2, Crown } from "$shared/ui/Icons";

  interface LinkedSource {
    source: string;
    externalId: string;
    url: string | null;
    isPrimary: boolean;
    title: string | null;
    details: string | null;
  }

  interface Props {
    mediaId: string;
    mediaType: string;
    /** Fired after any successful mutation so the parent can refresh the card. */
    onChanged?: () => void;
    /** Opens the full relink modal (re-pointing the primary source). */
    onOpenRelink?: () => void;
  }

  let { mediaId, mediaType, onChanged, onOpenRelink }: Props = $props();

  let sources = $state<LinkedSource[]>([]);
  let loading = $state(true);
  let loadError = $state<unknown>(null);
  let busy = $state("");
  let addOpen = $state(false);
  let addSource = $state("mangalib");
  let addId = $state("");

  const sourceOptions = [
    { value: "mangalib", label: "MangaLib" },
    { value: "ranobelib", label: "RanobeLib" },
    { value: "animelib", label: "AnimeLib" },
    { value: "anilist", label: "AniList" },
    { value: "shikimori", label: "Shikimori" },
    { value: "mangadex", label: "MangaDex" },
    { value: "tmdb", label: "TMDb" },
    { value: "kinopoisk", label: "Кинопоиск" },
    { value: "steam", label: "Steam" },
    { value: "rawg", label: "RAWG" },
    { value: "imdb", label: "IMDb" },
  ];

  /** Brand colors for the source badge. */
  function badgeClass(source: string): string {
    const key = source.toLowerCase();
    if (key.includes("mangalib")) return "bg-violet-500/20 text-violet-300 border-violet-500/30";
    if (key.includes("ranobelib")) return "bg-sky-500/20 text-sky-300 border-sky-500/30";
    if (key.includes("animelib")) return "bg-rose-500/20 text-rose-300 border-rose-500/30";
    if (key.includes("anilist")) return "bg-indigo-500/20 text-indigo-300 border-indigo-500/30";
    if (key.includes("shikimori")) return "bg-blue-500/20 text-blue-300 border-blue-500/30";
    if (key.includes("mangadex")) return "bg-pink-500/20 text-pink-300 border-pink-500/30";
    if (key.includes("tmdb")) return "bg-emerald-500/20 text-emerald-300 border-emerald-500/30";
    if (key.includes("kinopoisk")) return "bg-orange-500/20 text-orange-300 border-orange-500/30";
    if (key.includes("steam")) return "bg-slate-500/20 text-slate-300 border-slate-500/30";
    return "bg-white/10 text-slate-300 border-white/10";
  }

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

  async function mutate(action: () => Promise<Response>, successMessage: string) {
    try {
      const response = await action();
      if (!response.ok) throw new Error(await response.text());
      sources = await response.json();
      showToast(successMessage, "success");
      onChanged?.();
    } catch (error) {
      showToast(errorMessage(error), "error");
    }
  }

  function add() {
    const externalId = addId.trim();
    if (!externalId || busy) return;
    const payload = JSON.stringify({ source: addSource, externalId });
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
  });
</script>

<div
  class="rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
>
  <div class="flex flex-wrap items-center justify-between gap-2">
    <h3 class="flex items-center gap-2 text-xs font-bold tracking-wider text-slate-300 uppercase">
      <Link2 size={14} aria-hidden="true" />
      {i18n.t.detail.linkedSourcesTitle}
    </h3>
    <button
      type="button"
      class="inline-flex cursor-pointer items-center gap-1 rounded-lg border border-white/10 bg-white/[0.04] px-2.5 py-1 text-xs font-medium text-slate-300 transition hover:border-indigo-500/40 hover:text-white"
      onclick={() => (addOpen = !addOpen)}
    >
      <Plus size={13} aria-hidden="true" />
      {i18n.t.detail.linkedSourcesAdd}
    </button>
  </div>

  {#if addOpen}
    <form
      class="mt-3 flex flex-wrap items-end gap-2"
      onsubmit={(event) => {
        event.preventDefault();
        add();
      }}
    >
      <label class="block min-w-32 flex-1 space-y-1 text-xs font-medium text-white">
        {i18n.t.detail.linkedSourcesSourceLabel}
        <select
          bind:value={addSource}
          class="bg-canvas focus:border-accent w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        >
          {#each sourceOptions as option (option.value)}
            <option value={option.value}>{option.label}</option>
          {/each}
        </select>
      </label>
      <label class="block min-w-40 flex-[2] space-y-1 text-xs font-medium text-white">
        {i18n.t.detail.linkedSourcesIdLabel}
        <input
          type="text"
          bind:value={addId}
          placeholder="35160--slug"
          class="bg-canvas focus:border-accent w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        />
      </label>
      <button
        type="submit"
        disabled={!addId.trim() || busy === "add"}
        class="bg-accent hover:bg-accent-hover rounded-lg px-3 py-1.5 text-xs font-semibold text-white transition disabled:opacity-50"
      >
        OK
      </button>
    </form>
  {/if}

  {#if loading}
    <div class="mt-3 h-16 animate-pulse rounded-lg bg-white/[0.03]"></div>
  {:else if loadError}
    <p class="text-muted mt-3 text-xs">{i18n.t.detail.linkedSourcesLoadError}</p>
  {:else if sources.length === 0}
    <p class="text-muted mt-3 text-xs">{i18n.t.detail.linkedSourcesEmpty}</p>
  {:else}
    <ul class="mt-3 space-y-2">
      {#each sources as source (source.source)}
        <li
          class="rounded-lg border border-white/[0.06] bg-white/[0.03] p-2.5 transition hover:border-white/[0.12]"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase {badgeClass(
                source.source,
              )}"
            >
              {source.source}
            </span>
            {#if source.isPrimary}
              <span
                class="inline-flex items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/15 px-2 py-0.5 text-[10px] font-semibold text-amber-300"
              >
                <Crown size={11} aria-hidden="true" />
                {i18n.t.detail.linkedSourcesPrimary}
              </span>
            {/if}
            <span class="text-muted min-w-0 flex-1 truncate text-[11px]" title={source.externalId}>
              {source.title || source.externalId}
            </span>
          </div>

          <div class="mt-2 flex flex-wrap items-center gap-1.5">
            {#if siteUrl(source)}
              <a
                href={siteUrl(source) ?? "#"}
                target="_blank"
                rel="noreferrer"
                class="inline-flex items-center gap-1 rounded-md border border-white/10 bg-white/[0.04] px-2 py-1 text-[11px] font-medium text-slate-300 transition hover:border-indigo-500/40 hover:text-white"
              >
                <ExternalLink size={12} aria-hidden="true" />
                {i18n.t.detail.linkedSourcesOpen}
              </a>
            {/if}
            {#if !source.isPrimary}
              <button
                type="button"
                disabled={busy === `primary:${source.source}`}
                class="inline-flex cursor-pointer items-center gap-1 rounded-md border border-white/10 bg-white/[0.04] px-2 py-1 text-[11px] font-medium text-slate-300 transition hover:border-amber-500/40 hover:text-amber-200 disabled:opacity-50"
                title={i18n.t.detail.linkedSourcesMakePrimary}
                onclick={() => makePrimary(source)}
              >
                <Check size={12} aria-hidden="true" />
                {i18n.t.detail.linkedSourcesMakePrimary}
              </button>
              <button
                type="button"
                class="inline-flex cursor-pointer items-center gap-1 rounded-md border border-white/10 bg-white/[0.04] px-2 py-1 text-[11px] font-medium text-slate-300 transition hover:border-indigo-500/40 hover:text-white"
                onclick={() => onOpenRelink?.()}
              >
                {i18n.t.detail.linkedSourcesRelink}
              </button>
            {/if}
            <button
              type="button"
              disabled={busy === `remove:${source.source}`}
              class="text-muted inline-flex cursor-pointer items-center gap-1 rounded-md border border-white/10 bg-white/[0.04] px-2 py-1 text-[11px] font-medium transition hover:border-rose-500/40 hover:text-rose-300 disabled:opacity-50"
              title={i18n.t.detail.linkedSourcesRemove}
              aria-label={i18n.t.detail.linkedSourcesRemove}
              onclick={() => remove(source)}
            >
              <Trash2 size={12} aria-hidden="true" />
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</div>
