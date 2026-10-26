<script lang="ts">
  import {
    Check,
    GitBranch,
    Image as ImageIcon,
    Layers,
    LayoutGrid,
    Play,
    RefreshCw,
  } from "$shared/ui/Icons.svelte";
  import { errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
  import type { MediaItem } from "$shared/types";
  import RelationLoadButton from "$widgets/media-detail/RelationLoadButton.svelte";
  import {
    formatMediaDisplayType,
    relatedStatusClasses,
  } from "$widgets/media-detail/detailFormatters";
  import type {
    RelatedEntry,
    RelatedViewMode,
    RelationGroup,
    TimelineEntry,
  } from "$widgets/media-detail/detailTypes";

  interface Props {
    /** The detail shape carries `relatedSource`; the panel only reads that one extra field. */
    media: MediaItem & { relatedSource?: string | null };
    related?: readonly RelatedEntry[];
    loading?: boolean;
    error?: unknown;
    viewMode?: RelatedViewMode;
    groups?: readonly RelationGroup[];
    timeline?: readonly TimelineEntry[];
    onRetry: () => void;
    onSelectViewMode: (mode: RelatedViewMode) => void;
    /** Opens a local item or the preview modal for an external one. */
    onOpen: (entry: RelatedEntry) => void;
    /** `force` skips the 30-day cache; the source is the one the user picked in the dropdown. */
    onLoadFrom: (source: string, force?: boolean) => void;
  }

  let {
    media,
    related = [],
    loading = false,
    error = null,
    viewMode = "grouped",
    groups = [],
    timeline = [],
    onRetry,
    onSelectViewMode,
    onOpen,
    onLoadFrom,
  }: Props = $props();

  const VIEWS: ReadonlyArray<{
    mode: RelatedViewMode;
    title: string;
    icon: typeof GitBranch;
  }> = [
    { mode: "grouped", title: i18n.t.detail.viewGrouped, icon: Layers },
    { mode: "timeline", title: i18n.t.detail.viewTimeline, icon: GitBranch },
    { mode: "grid", title: i18n.t.detail.viewGrid, icon: LayoutGrid },
  ];

  function viewClass(mode: RelatedViewMode): string {
    return `grid h-8 w-8 place-items-center rounded-md transition cursor-pointer ${
      viewMode === mode
        ? "bg-accent text-white shadow"
        : "text-slate-400 hover:bg-white/5 hover:text-white"
    }`;
  }
</script>

<section class="space-y-6">
  <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
    <div class="min-w-0">
      <h2 class="text-sm font-bold tracking-wider text-slate-300 uppercase">
        {i18n.t.detail.relatedTitle}
      </h2>
      <p class="text-muted text-xs">{i18n.t.detail.relatedSubtitle}</p>
      <!-- Stays in the header after a successful load: the data on screen came from one
                 provider, and picking another has to overwrite it rather than need a clear first. -->
      {#if (related?.length ?? 0) > 0}
        <div class="mt-3">
          <RelationLoadButton
            {media}
            {loading}
            kind="related"
            currentSource={media.relatedSource ?? null}
            onLoad={onLoadFrom}
          />
        </div>
      {/if}
    </div>

    {#if (related?.length ?? 0) > 0}
      <div
        class="inline-flex items-center gap-1 self-start rounded-lg border border-white/[0.08] bg-[var(--color-track-alt)] p-1 sm:self-auto"
      >
        {#each VIEWS as view (view.mode)}
          <button
            type="button"
            class={viewClass(view.mode)}
            title={view.title}
            aria-label={view.title}
            onclick={() => onSelectViewMode(view.mode)}
          >
            <view.icon size={17} aria-hidden="true" />
          </button>
        {/each}
      </div>
    {/if}
  </div>

  {#if loading}
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
      {#each Array(5) as _, idx (idx)}
        <div class="space-y-2">
          <div
            class="aspect-[2/3] w-full animate-pulse rounded-xl bg-[var(--color-panel-line)]"
          ></div>
          <div class="h-3 w-3/4 animate-pulse rounded bg-[var(--color-panel-line)]"></div>
        </div>
      {/each}
    </div>
  {:else if error}
    <!-- Steam Deck greys: a failing provider should not splash a light-mode alert across a dark
             screen. The message says what went wrong and the button repeats the same request. -->
    <div
      class="flex flex-col items-start gap-3 rounded-xl border border-rose-400/20 bg-[#1c202b] p-5"
      role="alert"
    >
      <p class="text-sm text-rose-200">{errorMessage(error)}</p>
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-md border border-[var(--color-accent)]/40 bg-[var(--color-accent)]/10 px-3 py-1.5 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:bg-[var(--color-accent)]/20"
        onclick={onRetry}
      >
        <RefreshCw size={14} aria-hidden="true" />
        {i18n.current === "ru" ? "Попробовать снова" : "Try again"}
      </button>
    </div>
  {:else if (related?.length ?? 0) === 0}
    <div
      class="flex flex-col items-center justify-center gap-4 rounded-xl bg-[var(--color-panel-line)] p-8 text-center"
    >
      <div class="space-y-1">
        <p class="text-sm font-medium text-slate-300">{i18n.t.detail.relatedEmpty}</p>
        <p class="text-muted text-xs">
          {i18n.current === "ru"
            ? "Нажмите кнопку ниже, чтобы загрузить связанные произведения."
            : "Click the button below to load related titles."}
        </p>
      </div>
      <RelationLoadButton
        {media}
        {loading}
        kind="related"
        currentSource={media.relatedSource ?? null}
        onLoad={onLoadFrom}
      />
    </div>
  {:else if viewMode === "grouped"}
    <div class="space-y-8">
      {#each groups ?? [] as group, gIdx (group?.id ?? group?.title ?? gIdx)}
        <div class="space-y-3">
          <div class="flex items-center gap-2.5 border-b border-white/[0.08] pb-2.5">
            <h3 class="text-base font-bold tracking-tight text-white sm:text-lg">
              {group.title}
            </h3>
            <span class="text-muted rounded-full bg-white/10 px-2.5 py-0.5 text-xs font-bold">
              {group.items?.length ?? 0}
            </span>
          </div>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
            {#each group.items ?? [] as rel, rIdx (rel?.id ? `${rel.id}-${rIdx}` : `${gIdx}-${rIdx}`)}
              {@render relatedCard(rel)}
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {:else if viewMode === "timeline"}
    <div
      class="before:from-accent before:via-accent/40 relative space-y-4 pl-6 before:absolute before:top-3 before:bottom-3 before:left-[11px] before:w-0.5 before:bg-gradient-to-b before:to-transparent sm:pl-8 sm:before:left-[15px]"
    >
      {#each timeline ?? [] as item, tIdx (item?.id ? `${item.id}-${tIdx}` : tIdx)}
        {@render timelineRow(item)}
      {/each}
    </div>
  {:else}
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
      {#each related ?? [] as rel, rIdx (rel?.id ? `${rel.id}-${rIdx}` : rIdx)}
        {@render relatedCard(rel)}
      {/each}
    </div>
  {/if}
</section>

{#snippet relatedCard(rel: RelatedEntry)}
  <button
    type="button"
    class="group hover:border-accent/50 hover:shadow-accent/10 relative flex aspect-[2/3] w-full cursor-pointer flex-col overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-overlay-strong)] text-left transition duration-300 hover:shadow-xl"
    onclick={() => onOpen(rel)}
  >
    {#if rel.coverUrl}
      <img
        src={rel.coverUrl}
        alt={rel.title}
        class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
        loading="lazy"
        referrerpolicy="no-referrer"
      />
    {:else}
      <div class="text-muted grid h-full w-full place-items-center bg-[var(--color-field)]">
        <ImageIcon size={32} stroke-width={1.25} aria-hidden="true" />
      </div>
    {/if}

    {#if rel.localItem}
      <div class="absolute top-2.5 left-2.5 z-20 flex items-center">
        <!-- The one badge component the library grid already uses, so a related card and a
                     card on the home screen are visually identical instead of two hand-rolled dots. -->
        <MediaStatusBadge
          id={`related-status-${rel.id}`}
          status={rel.localItem.status}
          onSelect={() => onOpen(rel)}
        />

        {#if rel.localItem.score !== null && rel.localItem.score > 0}
          <div
            class="relative z-20 -ml-2 flex h-7 w-7 items-center justify-center rounded-full border-2 border-[color-mix(in_oklab,var(--color-accent-line)_80%,transparent)] bg-[var(--color-score-bg)] text-xs font-black text-white shadow-lg ring-2 ring-[color-mix(in_oklab,var(--color-accent-line)_30%,transparent)] select-none"
            title={`${i18n.t.createModal.fields.score}: ${rel.localItem.score}`}
          >
            {rel.localItem.score}
          </div>
        {/if}
      </div>
    {/if}

    <div
      class="pointer-events-none absolute inset-x-0 bottom-0 flex flex-col justify-end bg-gradient-to-t from-black/95 via-black/85 to-transparent p-3 pt-12"
    >
      <span
        class="group-hover:text-accent-soft line-clamp-2 text-sm leading-snug font-bold text-white drop-shadow-md transition"
      >
        {rel.title}
      </span>
      <div class="mt-1.5 flex items-center justify-between gap-1 text-xs">
        {#if rel.relationType}
          <span
            class="bg-accent/25 border-accent/40 text-accent-soft rounded border px-2 py-0.5 text-[11px] font-semibold backdrop-blur-sm"
          >
            {rel.relationType}
          </span>
        {:else}
          <span class="text-[11px] text-slate-300">{formatMediaDisplayType(rel)}</span>
        {/if}
        {#if rel.year}
          <span class="text-[11px] font-medium text-slate-300">
            {rel.year}
          </span>
        {/if}
      </div>
    </div>
  </button>
{/snippet}

{#snippet timelineRow(item: TimelineEntry)}
  <div class="group relative flex items-center gap-4">
    <div
      class={`absolute -left-6 flex h-6 w-6 items-center justify-center rounded-full border-2 transition-transform duration-300 group-hover:scale-[1.03] sm:-left-8 ${
        item.isCurrent
          ? "border-accent bg-accent shadow-accent/50 ring-accent/20 text-white shadow-lg ring-4"
          : item.localItem
            ? "border-emerald-500 bg-[var(--color-field)] text-emerald-400"
            : "border-white/[0.14] bg-[var(--color-field)] text-slate-400"
      }`}
    >
      {#if item.isCurrent}
        <div class="h-2 w-2 rounded-full bg-white"></div>
      {:else if item.localItem}
        <Check size={12} stroke-width={3} aria-hidden="true" />
      {:else}
        <div class="h-1.5 w-1.5 rounded-full bg-white/40"></div>
      {/if}
    </div>

    <button
      type="button"
      class={`flex flex-1 cursor-pointer items-center gap-3.5 rounded-xl border p-2.5 text-left transition ${
        item.isCurrent
          ? "border-accent/60 bg-accent/10 ring-accent/30 shadow-md ring-1"
          : "border-white/[0.06] bg-[var(--color-panel-line)] hover:border-white/[0.14] hover:bg-[var(--color-panel-raised)]"
      }`}
      onclick={() => {
        if (item.isCurrent || !item.rawItem) return;
        onOpen(item.rawItem);
      }}
    >
      <div
        class="relative aspect-[2/3] h-16 shrink-0 overflow-hidden rounded-lg bg-[var(--color-field)]"
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
            <ImageIcon size={18} aria-hidden="true" />
          </div>
        {/if}

        {#if item.localItem}
          <div class="absolute top-1 left-1 flex items-center">
            <div
              class={`flex h-4 w-4 items-center justify-center rounded-full ${relatedStatusClasses(item.localItem.status)}`}
            >
              {#if item.localItem.status === 2}
                <Check size={8} stroke-width={3} aria-hidden="true" />
              {/if}
            </div>
          </div>
        {/if}
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center gap-2">
          {#if item.year}
            <span class="text-accent-soft rounded bg-white/10 px-1.5 py-0.5 text-[11px] font-bold">
              {item.year}
            </span>
          {/if}
          <span
            class={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
              item.isCurrent
                ? "bg-accent text-white"
                : "border border-white/[0.08] bg-white/5 text-slate-300"
            }`}
          >
            {item.relationType}
          </span>
          <span class="text-muted text-[11px]">{item.formatDisplay}</span>
        </div>

        <h3
          class={`mt-1 truncate text-sm font-bold ${item.isCurrent ? "text-accent-soft" : "group-hover:text-accent-soft text-white"}`}
        >
          {item.title}
        </h3>
      </div>

      <div class="shrink-0 pr-2">
        {#if item.localItem?.score}
          <span
            class="rounded-full border border-[color-mix(in_oklab,var(--color-accent-line)_80%,transparent)] bg-[var(--color-score-bg)] px-2.5 py-0.5 text-xs font-black text-white"
          >
            {item.localItem.score}
          </span>
        {:else if !item.localItem && !item.isCurrent}
          <span
            class="group-hover:border-accent/40 group-hover:text-accent-soft rounded-md border border-white/[0.08] bg-white/5 px-2.5 py-1 text-xs font-medium text-slate-300"
          >
            {i18n.t.detail.overviewBadge}
          </span>
        {/if}
      </div>
    </button>
  </div>
{/snippet}
