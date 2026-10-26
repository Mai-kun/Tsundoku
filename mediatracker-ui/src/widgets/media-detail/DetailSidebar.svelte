<script lang="ts">
  import {
    Ban,
    CalendarDays,
    ChevronDown,
    ExternalLink,
    Image as ImageIcon,
    Link2,
    Pencil,
    RefreshCw,
    Sparkles,
    Star,
    Trash2,
  } from "$shared/ui/Icons.svelte";
  import ListPicker from "$features/lists/ListPicker.svelte";
  import MediaActivityModal from "./MediaActivityModal.svelte";
  import { errorMessage, triggerAutoRefresh } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { fullSizeCoverUrl } from "$entities/media/model/coverUrl";
  import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";
  import ImageLightbox from "$shared/ui/ImageLightbox.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, type AppView, type MediaDetail, type MediaStatus } from "$shared/types";
  import { statusLabel } from "$entities/media/model/mediaLabels";
  import { getDropReasonLabel } from "$entities/media/model/dropReasons";
  import { dropPromptState } from "$features/drop-reason/dropReasonPrompt.svelte";
  import {
    getCriteriaAxes,
    parseDetailedScore,
    serializeDetailedScore,
    computeDetailedAverage,
    type DetailedScoreMap,
  } from "$entities/media/model/detailedScore";

  export interface SpecRow {
    label: string;
    value: string;
    /** Absolute URL when the value is a link; the sidebar renders an anchor instead of plain text. */
    href?: string;
    badges?: readonly string[];
    importSource?: string;
  }

  interface Props {
    media: MediaDetail;
    statusOptions: readonly MediaStatus[];
    statusBusy: boolean;
    onChangeStatus: (status: MediaStatus) => Promise<void>;
    statusError: unknown;
    scoreValue: number | null;
    ratingOpen: boolean;
    onRatingOpen: () => void;
    onRatingClose: () => void;
    onRatingHide: () => void;
    onSetScore: (score: number) => Promise<void>;
    onClearScore: () => void;
    onSaveDetailedScore?: (detailedJson: string | null, newScore?: number | null) => Promise<void>;
    formatDate: (value: string | null) => string;
    historyProgressText: () => string;
    watchedOnInput: string;
    watchedOnOptions: readonly string[];
    onWatchedOnInput: (value: string) => void;
    onWatchedOnDirty: () => void;
    onSaveWatchedOn: () => Promise<void>;
    platformOptions: readonly string[];
    onSelectPlatform: (platform: string) => Promise<void>;
    refreshBusy: boolean;
    refreshError: unknown;
    onRefreshMetadata: () => Promise<void>;
    fillMissingBusy: boolean;
    onFillMissing: () => void;
    onRelink: () => void;
    onStartEdit: () => void;
    deleteBusy: boolean;
    deleteError: unknown;
    onDelete: () => Promise<void>;
    onNavigate: (view: AppView) => void;
    specRows: readonly SpecRow[];
    /** Background enrichment is still running: only the poster waits, the rest of the page does not. */
    syncing?: boolean;
    /** Called with the fresh row after the user runs a one-click auto-check from the sidebar. */
    onAutoRefreshed?: (media: MediaDetail) => void;
  }

  let {
    media,
    statusOptions,
    statusBusy,
    onChangeStatus,
    statusError,
    scoreValue,
    ratingOpen,
    onRatingOpen,
    onRatingClose,
    onRatingHide,
    onSetScore,
    onClearScore,
    onSaveDetailedScore,
    formatDate,
    historyProgressText,
    watchedOnInput,
    watchedOnOptions,
    onWatchedOnInput,
    onWatchedOnDirty,
    onSaveWatchedOn,
    platformOptions,
    onSelectPlatform,
    refreshBusy,
    refreshError,
    onRefreshMetadata,
    fillMissingBusy,
    onFillMissing,
    onRelink,
    onStartEdit,
    deleteBusy,
    deleteError,
    onDelete,
    onNavigate,
    specRows,
    syncing = false,
    onAutoRefreshed,
  }: Props = $props();

  let isActivityOpen = $state(false);
  let detailedExpanded = $state(false);
  let detailedDraft = $state<DetailedScoreMap>({});
  let lastMediaJson = $state<string | null | undefined>(undefined);
  let imgError = $state(false);

  $effect(() => {
    void media.coverUrl;
    imgError = false;
  });

  $effect(() => {
    if (media.detailedScoreJson !== lastMediaJson) {
      lastMediaJson = media.detailedScoreJson;
      detailedDraft = parseDetailedScore(media.detailedScoreJson);
    }
  });

  const axes = $derived(getCriteriaAxes(media));
  const savedDetailedMap = $derived(parseDetailedScore(media.detailedScoreJson));
  const savedSummary = $derived(computeDetailedAverage(savedDetailedMap));
  const draftSummary = $derived(computeDetailedAverage(detailedDraft));

  const statusMenuItems = $derived(
    statusOptions.map((value) => ({ value, label: statusLabel(value) })),
  );

  const platformMenuItems = $derived(platformOptions.map((value) => ({ value, label: value })));

  const watchedOnMenuItems = $derived(watchedOnOptions.map((value) => ({ value, label: value })));

  const finishedRelease = $derived(media.releaseStatus?.toUpperCase() === "FINISHED");
  // Games and books are never polled server-side; the button only makes sense for active ongoings.
  const isOngoing = $derived(
    !finishedRelease &&
      (media.type === "manga" || media.type === "tvshow" || !!media.nextAutoRefreshAt),
  );

  let autoRefreshBusy = $state(false);
  let activeLightboxUrl = $state<string | null>(null);

  async function handleAutoRefresh() {
    if (autoRefreshBusy) return;
    autoRefreshBusy = true;
    try {
      const updated = await triggerAutoRefresh(media.id);
      onAutoRefreshed?.(updated);
      showToast(i18n.t.detail.autoRefreshDone, "success");
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      autoRefreshBusy = false;
    }
  }
</script>

<!-- Без lg:sticky: сайдбар выше окна (~1400px), и пересчёт sticky-нижней границы
     при изменении высоты правой колонки дёргал постер вверх-вниз. -->
<aside class="w-full space-y-6 lg:w-80 lg:shrink-0 lg:self-start" data-widget="detail-sidebar">
  <div
    class="aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] shadow-lg"
  >
    {#if syncing && !media.coverUrl}
      <div
        class="flex h-full animate-pulse flex-col items-center justify-center gap-2 bg-white/[0.04]"
      >
        <ImageIcon size={32} stroke-width={1.25} class="text-muted" aria-hidden="true" />
        <p class="text-muted px-3 text-center text-xs">
          {i18n.t.activity.loadingCover}
        </p>
      </div>
    {:else if media.coverUrl && !imgError}
      <button
        type="button"
        class="block h-full w-full cursor-pointer border-0 bg-transparent p-0 text-left"
        onclick={() => {
          const cover = media.coverUrl;
          if (cover) activeLightboxUrl = fullSizeCoverUrl(cover);
        }}
        title="Увеличить постер"
        aria-label="Увеличить постер"
      >
        <img
          src={fullSizeCoverUrl(media.coverUrl)}
          alt={media.title}
          referrerpolicy="no-referrer"
          class="h-full w-full object-cover object-top"
          onerror={() => (imgError = true)}
        />
      </button>
    {:else}
      <MediaCoverPlaceholder />
    {/if}
  </div>

  <!-- Status selector and User Rating in a unified row -->
  <div class="flex items-center gap-2">
    <div class="relative flex-1">
      <PopoverMenu
        id={`detail-status-${media.id}`}
        options={statusMenuItems}
        selected={media.status}
        onSelect={(value) => onChangeStatus(value as MediaStatus)}
        label={i18n.t.status.label}
        matchTriggerWidth
        placement="bottom-end"
        class="min-w-40"
        optionClass="hover:bg-[var(--color-panel-raised)]"
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            disabled={statusBusy}
            class="tap has-[:popover-open]:ring-accent-soft flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-panel-line)] px-3.5 text-sm font-medium text-white transition hover:bg-[var(--color-panel-raised)] disabled:cursor-not-allowed disabled:opacity-70 has-[:popover-open]:ring-2"
            aria-haspopup="listbox"
          >
            <span class="truncate">{statusLabel(media.status)}</span>
            <ChevronDown
              size={15}
              class="shrink-0 transition group-[:popover-open]:rotate-180 has-[:popover-open]:rotate-180"
              aria-hidden="true"
            />
          </button>
        {/snippet}
      </PopoverMenu>
    </div>
    <!-- Icon-only rating button, same height as the status block; opens on hover. -->
    <div
      class="relative shrink-0"
      data-rating-popover
      role="presentation"
      onpointerenter={onRatingOpen}
      onpointerleave={onRatingClose}
    >
      <button
        type="button"
        class={`tap grid h-10 w-10 place-items-center rounded-lg border transition ${
          scoreValue !== null && scoreValue > 0
            ? "border-amber-400/40 bg-amber-400/10 text-amber-300"
            : "border-white/[0.08] bg-[var(--color-panel-line)] text-white/80 hover:bg-[var(--color-panel-raised)] hover:text-white"
        }`}
        onclick={onRatingOpen}
        title={i18n.t.detail.yourRating}
        aria-label={scoreValue !== null && scoreValue > 0
          ? `${i18n.t.detail.yourRating}: ${scoreValue}`
          : i18n.t.detail.yourRating}
        aria-expanded={ratingOpen}
      >
        {#if scoreValue !== null && scoreValue > 0}
          <span
            class="text-[17px] font-black tracking-tight text-amber-300 tabular-nums select-none"
            >{scoreValue}</span
          >
        {:else}
          <Star size={18} class="text-white/80" aria-hidden="true" />
        {/if}
      </button>

      {#if ratingOpen}
        <div
          class={`absolute top-full right-0 z-30 mt-2 rounded-xl border border-white/[0.12] bg-[var(--color-overlay)] p-3 shadow-2xl shadow-black/90 transition ${
            detailedExpanded ? "w-72 sm:w-80" : "w-48"
          }`}
        >
          <div class="mb-2 text-center text-xs font-semibold text-slate-300">
            {#if scoreValue !== null}
              <span class="font-bold text-amber-300 tabular-nums">{scoreValue}</span>
              {i18n.t.detail.yourRating}
            {:else}
              {i18n.t.detail.rateButton}
            {/if}
          </div>
          <div class="grid grid-cols-5 gap-1.5">
            {#each Array(10) as _, index}
              {@const val = index + 1}
              <button
                type="button"
                class={`flex h-7 w-7 cursor-pointer items-center justify-center rounded-md text-xs font-bold transition ${
                  val === scoreValue
                    ? "bg-[#3b82f6] text-white shadow-md"
                    : "bg-white/5 text-slate-300 hover:bg-white/15 hover:text-white"
                }`}
                onclick={() => {
                  void onSetScore(val);
                  onRatingHide();
                }}
              >
                {val}
              </button>
            {/each}
          </div>

          <div class="mt-2.5 border-t border-white/[0.08] pt-2">
            <button
              type="button"
              class="flex w-full cursor-pointer items-center justify-between rounded-lg px-2 py-1.5 text-xs font-medium text-slate-300 transition hover:bg-white/[0.06] hover:text-white"
              onclick={() => (detailedExpanded = !detailedExpanded)}
            >
              <span class="flex items-center gap-1.5">
                <span>{i18n.t.detail.byCriteria}</span>
                {#if savedSummary}
                  <span
                    class="rounded bg-amber-400/20 px-1.5 py-0.5 text-[10px] font-bold text-amber-300 tabular-nums"
                  >
                    ★ {savedSummary.exact}
                  </span>
                {/if}
              </span>
              <ChevronDown
                size={14}
                class={`shrink-0 transition-transform duration-200 ${detailedExpanded ? "rotate-180" : ""}`}
                aria-hidden="true"
              />
            </button>
          </div>

          {#if detailedExpanded}
            <div class="mt-2 space-y-2.5 border-t border-white/[0.08] pt-2.5">
              <div class="space-y-2">
                {#each axes as axis}
                  {@const val = detailedDraft[axis.key]}
                  <div class="space-y-1">
                    <div class="flex items-center justify-between text-xs">
                      <span class="truncate font-medium text-slate-300">
                        {axis.label[i18n.current]}
                      </span>
                      <div class="flex items-center gap-1">
                        <span
                          class={`font-bold tabular-nums ${val !== undefined ? "text-amber-300" : "text-muted"}`}
                        >
                          {val ?? "—"}
                        </span>
                        {#if val !== undefined}
                          <button
                            type="button"
                            class="text-muted ml-0.5 cursor-pointer text-[10px] transition hover:text-rose-400"
                            title="Очистить"
                            aria-label={`Очистить ${axis.label[i18n.current]}`}
                            onclick={() => {
                              const next = { ...detailedDraft };
                              delete next[axis.key];
                              detailedDraft = next;
                            }}
                          >
                            ✕
                          </button>
                        {/if}
                      </div>
                    </div>
                    <div class="relative flex items-center">
                      <input
                        type="range"
                        min="1"
                        max="10"
                        step="1"
                        value={val ?? 5}
                        class={`h-1.5 w-full cursor-pointer appearance-none rounded-lg bg-white/10 accent-amber-400 transition-opacity ${
                          val === undefined ? "opacity-50 hover:opacity-80" : "opacity-100"
                        }`}
                        oninput={(e) => {
                          const num = Number(e.currentTarget.value);
                          detailedDraft = {
                            ...detailedDraft,
                            [axis.key]: num,
                          };
                        }}
                      />
                    </div>
                  </div>
                {/each}
              </div>

              {#if draftSummary !== null}
                <div class="space-y-2 border-t border-white/[0.08] pt-2">
                  <div class="flex items-center justify-between text-xs font-semibold">
                    <span class="text-slate-300">{i18n.t.detail.detailedAverage}:</span>
                    <span class="font-bold text-amber-300 tabular-nums">★ {draftSummary.exact}</span
                    >
                  </div>
                  <div class="flex flex-col gap-1.5">
                    <button
                      type="button"
                      class="flex w-full cursor-pointer items-center justify-center rounded-lg bg-amber-400/20 px-3 py-1.5 text-xs font-bold text-amber-300 transition hover:bg-amber-400/30"
                      onclick={async () => {
                        const json = serializeDetailedScore(detailedDraft);
                        if (onSaveDetailedScore) {
                          await onSaveDetailedScore(json, draftSummary.rounded);
                        } else {
                          await onSetScore(draftSummary.rounded);
                        }
                        onRatingHide();
                      }}
                    >
                      {i18n.t.detail.saveDetailedScore(draftSummary.rounded)}
                    </button>
                    {#if onSaveDetailedScore && (scoreValue === null || scoreValue !== draftSummary.rounded)}
                      <button
                        type="button"
                        class="flex w-full cursor-pointer items-center justify-center rounded-lg bg-white/5 px-2 py-1 text-[11px] text-slate-300 transition hover:bg-white/10 hover:text-white"
                        onclick={async () => {
                          const json = serializeDetailedScore(detailedDraft);
                          await onSaveDetailedScore(json);
                          onRatingHide();
                        }}
                      >
                        {i18n.t.detail.saveCriteriaOnly}
                      </button>
                    {/if}
                  </div>
                </div>
              {/if}
            </div>
          {/if}

          {#if scoreValue !== null || savedSummary !== null}
            <div class="mt-2.5 border-t border-white/[0.08] pt-2 text-center">
              <button
                type="button"
                class="cursor-pointer text-xs font-semibold text-rose-400 transition hover:text-rose-300"
                onclick={() => {
                  onClearScore();
                  detailedDraft = {};
                  onRatingHide();
                }}
              >
                {i18n.t.detail.clearRating}
              </button>
            </div>
          {/if}
        </div>
      {/if}
    </div>
  </div>
  {#if statusError}<p class="text-xs text-rose-300" role="alert">
      {errorMessage(statusError)}
    </p>{/if}

  {#if media.status === MEDIA_STATUS.dropped}
    <button
      type="button"
      class="tap group flex w-full cursor-pointer items-center justify-between gap-2 rounded-lg border border-rose-500/25 bg-rose-500/10 px-3 py-2 text-xs font-medium text-rose-300 transition hover:border-rose-500/40 hover:bg-rose-500/20"
      onclick={() => {
        dropPromptState.open({
          id: media.id,
          title: media.title,
          type: media.type,
          isAnime: (media as { isAnime?: boolean }).isAnime,
          dropReason: media.dropReason,
          dropNotes: media.dropNotes,
          onSaved: (reason, notes) => {
            media.dropReason = reason;
            media.dropNotes = notes;
          },
        });
      }}
      title={media.dropNotes
        ? `${getDropReasonLabel(media.dropReason ?? "unspecified", i18n.current)}: ${media.dropNotes}`
        : i18n.t.dropReason.changeReason}
    >
      <div class="flex min-w-0 items-center gap-1.5">
        <Ban size={13} class="shrink-0 text-rose-400" aria-hidden="true" />
        <span class="truncate">
          <span class="text-rose-400/80">{i18n.t.dropReason.badgePrefix}</span>{getDropReasonLabel(
            media.dropReason ?? "unspecified",
            i18n.current,
          )}
        </span>
        {#if media.dropNotes}
          <span class="max-w-[130px] truncate text-[11px] text-rose-300/60"
            >({media.dropNotes})</span
          >
        {/if}
      </div>
      <Pencil
        size={12}
        class="shrink-0 text-rose-400 opacity-0 transition group-hover:opacity-100"
        aria-hidden="true"
      />
    </button>
  {/if}

  {#if savedSummary !== null}
    <button
      type="button"
      class="group w-full cursor-pointer space-y-2 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-3 text-left transition hover:border-white/[0.12] hover:bg-[var(--color-panel-raised)]"
      onclick={() => {
        detailedDraft = parseDetailedScore(media.detailedScoreJson);
        detailedExpanded = true;
        onRatingOpen();
      }}
      aria-label={i18n.t.detail.detailedScoreTitle}
    >
      <div class="flex items-center justify-between">
        <span class="text-xs font-semibold text-slate-300 transition group-hover:text-white">
          {i18n.t.detail.detailedScoreTitle}
        </span>
        <span class="inline-flex items-center gap-1 text-xs font-bold text-amber-400 tabular-nums">
          ★ {savedSummary.exact}
        </span>
      </div>
      <div class="space-y-1.5 pt-0.5">
        {#each axes as axis}
          {@const val = savedDetailedMap[axis.key]}
          {#if val !== undefined}
            <div class="flex items-center gap-2 text-xs">
              <span class="text-muted w-24 truncate text-[11px]">
                {axis.label[i18n.current]}
              </span>
              <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-white/[0.08]">
                <div
                  class="h-full origin-left rounded-full bg-gradient-to-r from-amber-500/80 to-amber-400 transition duration-300"
                  style="width: {val * 10}%"
                ></div>
              </div>
              <span
                class="w-4 text-right font-mono text-[11px] font-bold text-slate-200 tabular-nums"
              >
                {val}
              </span>
            </div>
          {/if}
        {/each}
      </div>
    </button>
  {/if}
  <!-- Panel 1: Your History -->
  <div>
    <h2 class="mb-2 text-xs font-bold tracking-wider text-slate-200 uppercase">
      {i18n.t.detail.historyTitle}
    </h2>
    <div class="panel">
      <!-- Every row gets the same padding so the list reads as one even
                 rhythm; the first/last rows align with the panel's own padding
                 instead of adding 12px on only one side. -->
      <dl class="divide-y divide-white/[0.06] text-sm [&>*:first-child]:pt-0 [&>*:last-child]:pb-0">
        <!-- Movies are watched as a single sitting: a start date and a raw
                     "current / total" counter say nothing there that the progress stepper
                     does not, so only the completion is kept. Every other type still needs
                     both rows — a series or a manga is started, then tracked over time. -->
        {#if media.type !== "movie"}
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted text-xs">
              {i18n.t.detail.startedLabel}
            </dt>
            <dd class="text-xs font-medium text-white">
              {formatDate(media.startedAt)}
            </dd>
          </div>
        {/if}
        <div class="flex items-center justify-between gap-3 py-2.5">
          <dt class="text-muted text-xs">
            {i18n.t.detail.endedLabel}
          </dt>
          <dd class="text-xs font-medium text-white">
            {formatDate(media.finishedAt)}
          </dd>
        </div>
        {#if media.type !== "movie"}
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted text-xs">
              {i18n.t.detail.progressShort}
            </dt>
            <dd class="text-xs font-medium text-white tabular-nums">
              {historyProgressText()}
            </dd>
          </div>
        {/if}
        {#if media.nextAutoRefreshAt && !finishedRelease}
          <!-- When the next background check runs, and at what cadence. -->
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted text-xs">
              {i18n.t.detail.autoRefreshTitle}
            </dt>
            <dd
              class="cursor-help text-xs font-medium text-white underline decoration-white/25 decoration-dotted"
              title={formatDate(media.nextAutoRefreshAt)}
            >
              {#if media.releaseStatus?.toUpperCase() === "HIATUS"}
                {i18n.t.detail.autoRefreshHiatus}
              {:else if media.autoRefreshIntervalDays}
                {i18n.t.detail.autoRefreshInterval(media.autoRefreshIntervalDays)}
              {/if}
            </dd>
          </div>
        {/if}
        {#if media.type === "movie" || media.type === "tvshow"}
          <!-- Pick a known site or type your own; saved on change/blur. The sites come from
                         our PopoverMenu rather than a native <datalist>: the browser popup ignores the
                         app palette and renders its own arrow, which is what the datalist arrow
                         pointed at. -->
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted text-xs">
              {i18n.t.detail.watchedOnLabel}
            </dt>
            <dd class="flex min-w-0 flex-1 items-center justify-end gap-1.5">
              <input
                id="watched-on-input"
                class="bg-elevated focus:border-accent focus:ring-accent/30 h-8 w-full max-w-[12rem] min-w-0 rounded-lg border border-white/10 px-2 text-right text-xs text-white outline-none focus:ring-2"
                placeholder={i18n.t.detail.watchedOnPlaceholder}
                value={watchedOnInput}
                oninput={(e) => {
                  onWatchedOnInput(e.currentTarget.value);
                  onWatchedOnDirty();
                }}
                onchange={() => void onSaveWatchedOn()}
                onblur={() => void onSaveWatchedOn()}
              />
              <PopoverMenu
                id={`watched-on-${media.id}`}
                options={watchedOnMenuItems}
                selected={watchedOnInput}
                onSelect={(value) => {
                  onWatchedOnInput(String(value));
                  void onSaveWatchedOn();
                }}
                label={i18n.t.detail.watchedOnLabel}
                placement="bottom-end"
                matchTriggerWidth={false}
                class="max-h-64 min-w-[180px] overflow-y-auto"
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
                    class="tap flex h-8 shrink-0 items-center justify-center gap-1 rounded-lg border border-white/[0.08] bg-[var(--color-field)] px-2 text-xs text-white transition hover:bg-[var(--color-track-faint)] has-[:popover-open]:ring-1 has-[:popover-open]:ring-[var(--color-accent)]"
                    aria-label={i18n.t.detail.watchedOnLabel}
                    aria-haspopup="listbox"
                  >
                    <ChevronDown
                      size={13}
                      class="text-muted transition duration-200 has-[:popover-open]:rotate-180 has-[:popover-open]:text-white"
                      aria-hidden="true"
                    />
                  </button>
                {/snippet}
              </PopoverMenu>
            </dd>
          </div>
        {/if}
        {#if media.type === "game"}
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted text-xs">
              {i18n.t.detailModal.platform}
            </dt>
            <dd class="relative text-xs font-medium text-white">
              {#if platformOptions.length > 0}
                <PopoverMenu
                  id={`platform-${media.id}`}
                  options={platformMenuItems}
                  selected={media.userPlatform ?? ""}
                  onSelect={(value) => onSelectPlatform(String(value))}
                  label={i18n.t.detailModal.platform}
                  placement="bottom-end"
                  class="max-h-56 min-w-[150px] overflow-y-auto"
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
                      class="tap flex max-w-[155px] items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-field)] px-2.5 py-1.5 text-xs text-white transition hover:border-[color-mix(in_oklab,var(--color-accent)_50%,transparent)] hover:bg-[var(--color-track-faint)] has-[:popover-open]:ring-1 has-[:popover-open]:ring-[var(--color-accent)]"
                      aria-haspopup="listbox"
                    >
                      <span class="truncate"
                        >{media.userPlatform || i18n.t.detail.platformNotSelected}</span
                      >
                      <ChevronDown
                        size={13}
                        class="text-muted shrink-0 transition duration-200 has-[:popover-open]:rotate-180 has-[:popover-open]:text-white"
                        aria-hidden="true"
                      />
                    </button>
                  {/snippet}
                </PopoverMenu>
              {:else}
                <span class="text-muted text-xs">—</span>
              {/if}
            </dd>
          </div>
        {/if}
      </dl>
    </div>
  </div>
  <!-- Panel 2: Actions -->
  <div>
    <h2 class="mb-2 text-xs font-bold tracking-wider text-slate-200 uppercase">
      {i18n.t.detail.actionsTitle}
    </h2>
    <div class="panel space-y-2">
      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
        disabled={refreshBusy}
        onclick={() => void onRefreshMetadata()}
      >
        <RefreshCw
          size={15}
          class={`text-[var(--color-success-line)] ${refreshBusy ? "animate-spin" : ""}`}
          aria-hidden="true"
        />
        {i18n.t.detail.updateMetadata}
      </button>
      {#if refreshError}<p class="text-xs text-rose-300" role="alert">
          {errorMessage(refreshError)}
        </p>{/if}

      {#if isOngoing}
        <button
          type="button"
          class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
          disabled={autoRefreshBusy}
          onclick={() => void handleAutoRefresh()}
        >
          <RefreshCw
            size={15}
            class={`text-[var(--color-accent-soft)] ${autoRefreshBusy ? "animate-spin" : ""}`}
            aria-hidden="true"
          />
          {autoRefreshBusy ? i18n.t.views.calendarChecking : i18n.t.detail.autoRefreshCheckNow}
        </button>
      {/if}

      <!-- Same gap-fill rules as the safe-merge branch of the refresh dialog, but the user
                 names the provider. Fills only empty fields, so it can never cost them data. -->
      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
        disabled={fillMissingBusy || refreshBusy}
        onclick={onFillMissing}
      >
        <Sparkles
          size={15}
          class={`text-[var(--color-accent-soft)] ${fillMissingBusy ? "animate-pulse" : ""}`}
          aria-hidden="true"
        />
        {fillMissingBusy ? i18n.t.detail.fillMissingRunning : i18n.t.detail.fillMissing}
      </button>

      <!-- Refresh re-reads the id already stored; this is for when that id belongs to the wrong
                 provider's match, so the user can point the row at a better one. -->
      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
        onclick={onRelink}
      >
        <Link2 size={15} class="text-[var(--color-accent-soft)]" aria-hidden="true" />
        {i18n.t.detail.changeSource}
      </button>

      <ListPicker mediaId={media.id} />

      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
        onclick={() => (isActivityOpen = true)}
      >
        <CalendarDays size={15} class="text-[var(--color-star)]" aria-hidden="true" />
        {i18n.t.detail.activity}
      </button>

      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
        onclick={onStartEdit}
      >
        <Pencil size={15} class="text-[var(--color-info-soft)]" aria-hidden="true" />
        {i18n.t.detailModal.edit}
      </button>

      <button
        type="button"
        class="tap bg-surface/50 flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-xs font-medium text-rose-300 transition hover:bg-[var(--color-panel-raised)] disabled:cursor-not-allowed disabled:opacity-70"
        disabled={deleteBusy}
        onclick={() => void onDelete()}
      >
        <Trash2 size={15} class="text-rose-400" aria-hidden="true" />
        {i18n.t.detailModal.delete}
      </button>
      {#if deleteError}<p class="text-xs text-rose-300" role="alert">
          {errorMessage(deleteError)}
        </p>{/if}
    </div>
  </div>
  <!-- Panel 3: Details -->
  <div>
    <h2 class="mb-2 text-xs font-bold tracking-wider text-slate-200 uppercase">
      {i18n.t.detail.detailsTitle}
    </h2>
    <div class="panel">
      <dl class="divide-y divide-white/5 text-sm">
        {#each specRows as row, idx (`${row.label}-${idx}`)}
          <div class="flex items-start justify-between gap-3 py-3 first:pt-0 last:pb-0">
            <dt class="text-muted shrink-0 text-xs font-medium">
              {row.label}
            </dt>
            <dd class="text-right text-xs font-medium text-white">
              {#if row.href}
                {#if row.importSource}
                  <span class="text-zinc-400">{row.importSource} · </span>
                {/if}
                <a
                  href={row.href}
                  target="_blank"
                  rel="noreferrer"
                  class="text-accent-soft inline-flex items-center gap-1 hover:underline"
                >
                  {row.value}
                  <ExternalLink size={11} aria-hidden="true" />
                </a>
              {:else if row.badges && row.badges.length > 0}
                <div class="flex flex-wrap justify-end gap-1">
                  {#each row.badges as badge}
                    <span
                      class="inline-block rounded border border-white/10 bg-white/5 px-1.5 py-0.5 text-xs text-zinc-300"
                    >
                      {badge}
                    </span>
                  {/each}
                </div>
              {:else}
                {#if row.importSource}
                  <span class="text-zinc-400">{row.importSource} · </span>
                {/if}
                {row.value}
              {/if}
            </dd>
          </div>
        {/each}
      </dl>
    </div>
  </div>
</aside>

<MediaActivityModal
  isOpen={isActivityOpen}
  mediaId={media.id}
  title={media.title}
  onClose={() => (isActivityOpen = false)}
/>

<ImageLightbox url={activeLightboxUrl} onclose={() => (activeLightboxUrl = null)} />
