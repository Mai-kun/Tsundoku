<script lang="ts">
  import {
    Ban,
    CalendarDays,
    Check,
    ChevronDown,
    Ellipsis,
    ExternalLink,
    Image as ImageIcon,
    Link2,
    List,
    Pencil,
    RefreshCw,
    Sparkles,
    Star,
    Trash2,
  } from "$shared/ui/Icons";
  import ListPicker from "$features/lists/ListPicker.svelte";
  import { slide } from "svelte/transition";
  import { errorMessage, triggerAutoRefresh } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { fullSizeCoverUrl, proxiedExternalCoverUrl } from "$entities/media/model/coverUrl";
  import { genreLabel } from "$entities/media/model/genreLabel";
  import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";
  import { openLightbox } from "$shared/ui/lightbox.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, type AppView, type MediaDetail, type MediaStatus } from "$shared/types";
  import { statusLabel } from "$entities/media/model/mediaLabels";
  import { getDropReasonLabel } from "$entities/media/model/dropReasons";
  import { dropPromptState } from "$features/drop-reason/dropReasonPrompt.svelte";
  import { uiSettings, type VoiceOptionScope } from "$shared/utils/uiSettings.svelte";
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
    watchedOnInput: string;
    onWatchedOnInput: (value: string) => void;
    onWatchedOnDirty: () => void;
    onSaveWatchedOn: () => Promise<void>;
    platformOptions: readonly string[];
    onSelectPlatform: (platform: string) => Promise<void>;
    refreshBusy: boolean;
    syncStep?: string | null;
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
    onMediaUpdated?: (media: MediaDetail) => void;
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
    watchedOnInput,
    onWatchedOnInput,
    onWatchedOnDirty,
    onSaveWatchedOn,
    platformOptions,
    onSelectPlatform,
    refreshBusy,
    syncStep = null,
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
    onMediaUpdated,
  }: Props = $props();

  let isCoverManagerOpen = $state(false);
  let isActivityOpen = $state(false);
  let isListPickerOpen = $state(false);
  let detailedExpanded = $state(false);
  let detailedDraft = $state<DetailedScoreMap>({});
  let lastMediaJson = $state<string | null | undefined>(undefined);
  let imgError = $state(false);
  let showAllAltTitles = $state(false);
  let showAllGenres = $state(false);

  // Stored alt titles can arrive as one slash/comma-joined blob (legacy offline imports), so
  // every entry is split, case-insensitively deduped and stripped of the display title.
  const splitAltTitles = $derived.by(() => {
    const seen = new Set<string>();
    const titleKey = media.title.trim().toLowerCase();
    const result: string[] = [];
    for (const raw of media.altTitles ?? []) {
      for (const part of raw.split(/\s*[/,]\s*/)) {
        const value = part.trim();
        const key = value.toLowerCase();
        if (!value || key === titleKey || seen.has(key)) continue;
        seen.add(key);
        result.push(value);
      }
    }
    return result;
  });
  // The romaji row is noise when the romanized title just repeats the display title or one
  // of the alternatives; the genres and alt-title rows move out of the dl into full-width
  // blocks below the table.
  const filteredSpecRows = $derived(
    specRows.filter((row) => {
      if (row.label === i18n.t.detail.genresLabel) return false;
      if (row.label !== i18n.t.detail.romajiTitle) return true;
      const value = row.value.trim().toLowerCase();
      if (!value || value === media.title.trim().toLowerCase()) return false;
      return !splitAltTitles.some((alt) => alt.toLowerCase() === value);
    }),
  );

  const genreChips = $derived.by(() => {
    const list = Array.isArray(media.genres) ? media.genres : (media.genres ?? "").split(/[,;]\s*/);
    const seen = new Set<string>();
    const result: string[] = [];
    for (const part of list) {
      const value = part.trim();
      const key = value.toLowerCase();
      if (!value || seen.has(key)) continue;
      seen.add(key);
      result.push(value);
    }
    return result;
  });

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

  // Rare actions hide behind the compact "…" menu next to the section title; only the frequent
  // ones stay on the panel face.
  type MoreAction = "covers" | "lists" | "relink" | "activity";
  const moreActionItems = $derived(
    [
      { value: "covers", label: i18n.t.coversModal.openCovers, icon: ImageIcon },
      { value: "lists", label: i18n.t.views.listAddTo, icon: List },
      { value: "relink", label: i18n.t.detail.changeSource, icon: Link2 },
      { value: "activity", label: i18n.t.detail.activity, icon: CalendarDays },
    ] satisfies Array<{ value: MoreAction; label: string; icon: typeof ImageIcon }>,
  );

  function runMoreAction(value: MoreAction) {
    switch (value) {
      case "covers":
        isCoverManagerOpen = true;
        break;
      case "lists":
        isListPickerOpen = true;
        break;
      case "relink":
        onRelink();
        break;
      case "activity":
        isActivityOpen = true;
        break;
    }
  }

  const moreActionIcon = (value: string) =>
    moreActionItems.find((item) => item.value === value)?.icon;

  // One combobox replaces the old input + list-button pair. Its scope follows the media type:
  // watching types get voice studios / streaming sites, books get reading formats, manga and
  // games have no such field at all.
  const comboScope = $derived<VoiceOptionScope | null>(
    media.type === "book"
      ? "read"
      : media.type === "movie" || media.type === "tvshow"
        ? "watch"
        : null,
  );
  const isAnimeMedia = $derived((media as { isAnime?: boolean }).isAnime === true);
  const comboLabel = $derived(
    comboScope === "read" ? i18n.t.detail.readingFormatLabel : i18n.t.detail.voiceStudioLabel,
  );
  const comboPresets = $derived(
    comboScope === "read"
      ? i18n.t.detail.readingFormatPresets()
      : i18n.t.detail.voiceStudioPresets(isAnimeMedia),
  );
  const comboMemory = $derived(comboScope ? uiSettings.getVoiceOptions(comboScope) : null);

  // Favorites float to the top; the rest follows preset order with the user's own values
  // (which are auto-favorited the moment they are applied) merged in.
  const comboOptions = $derived.by(() => {
    if (!comboMemory) return [] as string[];
    const isFavorite = (value: string) =>
      comboMemory.favorites.some((v) => v.toLowerCase() === value.toLowerCase());
    const seen = new Set<string>();
    const merged: string[] = [];
    for (const value of [...comboPresets, ...comboMemory.custom]) {
      const key = value.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      merged.push(value);
    }
    return merged.sort(
      (a, b) => Number(isFavorite(b)) - Number(isFavorite(a)),
    );
  });

  const comboMenuItems = $derived(comboOptions.map((value) => ({ value, label: value })));
  const comboIsFavorite = $derived.by(
    () => (value: string) =>
      (comboMemory?.favorites ?? []).some((v) => v.toLowerCase() === value.toLowerCase()),
  );

  function toggleComboFavorite(value: string) {
    if (!comboScope) return;
    uiSettings.toggleVoiceFavorite(comboScope, value);
  }

  /** Save + remember: every value the user applies once is kept forever and starred. */
  function commitComboValue(value: string) {
    onWatchedOnInput(value);
    if (comboScope) uiSettings.rememberVoiceOption(comboScope, value);
    void onSaveWatchedOn();
  }

  const finishedRelease = $derived(media.releaseStatus?.toUpperCase() === "FINISHED");
  // Games and books are never polled server-side; the button only makes sense for active ongoings.
  const isOngoing = $derived(
    media.type !== "game" &&
      !finishedRelease &&
      (media.type === "manga" || media.type === "tvshow" || !!media.nextAutoRefreshAt),
  );

  let autoRefreshBusy = $state(false);

  async function handleAutoRefresh() {
    if (autoRefreshBusy) return;
    autoRefreshBusy = true;
    try {
      const updated = await triggerAutoRefresh(media.id);
      onAutoRefreshed?.(updated);
      showToast({ title: i18n.t.detail.autoRefreshDone, description: i18n.t.toast.descUpdated });
    } catch (error) {
      showToast({ title: i18n.t.toast.actionFailed, description: errorMessage(error), type: "error" });
    } finally {
      autoRefreshBusy = false;
    }
  }
</script>

<!-- Без lg:sticky: сайдбар выше окна (~1400px), и пересчёт sticky-нижней границы
     при изменении высоты правой колонки дёргал постер вверх-вниз. -->
<aside class="w-full space-y-6 lg:w-80 lg:shrink-0 lg:self-start" data-widget="detail-sidebar">
  <div
    class="group relative aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] shadow-lg"
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
          if (cover) openLightbox(proxiedExternalCoverUrl(fullSizeCoverUrl(cover)));
        }}
        title="Увеличить постер"
        aria-label="Увеличить постер"
      >
        <img
          src={proxiedExternalCoverUrl(media.coverUrl)}
          alt={media.title}
          referrerpolicy="no-referrer"
          class="h-full w-full object-cover object-top"
          onerror={() => (imgError = true)}
        />
      </button>

      <!-- Hidden until hover: the poster stays clean, the covers manager reveals on
           hover or keyboard focus. -->
      <button
        type="button"
        class="absolute top-2 right-2 z-10 flex items-center gap-1.5 rounded-lg border border-white/20 bg-black/70 px-2.5 py-1 text-xs font-semibold text-white opacity-0 shadow-md transition-opacity duration-150 group-hover:opacity-100 hover:border-white/40 hover:bg-black/90 focus-visible:opacity-100"
        onclick={(e) => {
          e.stopPropagation();
          isCoverManagerOpen = true;
        }}
        title={i18n.t.coversModal.openCovers}
        aria-label={i18n.t.coversModal.openCovers}
      >
        <ImageIcon size={13} aria-hidden="true" />
        <span>{i18n.t.coversModal.openCovers}</span>
        {#if media.covers && media.covers.length > 1}
          <span class="py-0.2 rounded bg-indigo-500/80 px-1.5 text-[10px] font-bold">
            {media.covers.length}
          </span>
        {/if}
      </button>
    {:else}
      <MediaCoverPlaceholder />
      <button
        type="button"
        class="absolute top-2 right-2 z-10 flex items-center gap-1.5 rounded-lg border border-white/20 bg-black/70 px-2.5 py-1 text-xs font-semibold text-white shadow-md transition hover:border-white/40 hover:bg-black/90"
        onclick={(e) => {
          e.stopPropagation();
          isCoverManagerOpen = true;
        }}
        title={i18n.t.coversModal.openCovers}
        aria-label={i18n.t.coversModal.openCovers}
      >
        <ImageIcon size={13} aria-hidden="true" />
        <span>{i18n.t.coversModal.openCovers}</span>
      </button>
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
          {#key scoreValue}
            <span
              class="score-pop text-[17px] font-black tracking-tight text-amber-300 tabular-nums select-none"
              >{scoreValue}</span
            >
          {/key}
        {:else}
          <Star size={18} class="text-white/80" aria-hidden="true" />
        {/if}
      </button>

      {#if ratingOpen}
        <div
          class={`rating-pop absolute top-full right-0 z-30 mt-2 rounded-xl border border-white/[0.12] bg-[var(--color-overlay)] p-3 shadow-2xl shadow-black/90 ${
            detailedExpanded ? "w-72 sm:w-80" : "w-48"
          }`}
        >
          <div class="mb-2 text-center text-xs font-semibold text-slate-300">
            {#if scoreValue !== null}
              {#key scoreValue}
                <span class="score-pop inline-block font-bold text-amber-300 tabular-nums"
                  >{scoreValue}</span
                >
              {/key}
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
                    ? "bg-[var(--color-chart-blue)] text-white shadow-md"
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
        {#if media.type !== "game" && media.nextAutoRefreshAt && !finishedRelease}
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
        {#if comboScope !== null}
          <!-- Seamless combobox in one frame: the input and the dropdown chevron share a single
                 border. The list comes from our PopoverMenu (never a native <datalist>): its popup
                 ignores the app palette and renders its own arrow. -->
          <div class="flex items-center justify-between gap-3 py-2.5">
            <dt class="text-muted shrink-0 text-xs">
              {comboLabel}
            </dt>
            <dd class="flex min-w-0 flex-1 items-center justify-end">
              <div
                class="focus-within:border-accent focus-within:ring-accent/30 flex h-8 w-full max-w-[13rem] items-center rounded-lg border border-white/10 bg-[var(--color-field)] transition focus-within:ring-2"
              >
                <input
                  id="watched-on-input"
                  class="h-full w-full min-w-0 bg-transparent px-2 text-right text-xs text-white outline-none placeholder:text-white/30"
                  placeholder={i18n.t.detail.watchedOnPlaceholder}
                  value={watchedOnInput}
                  oninput={(e) => {
                    onWatchedOnInput(e.currentTarget.value);
                    onWatchedOnDirty();
                  }}
                  onkeydown={(e) => {
                    // Enter commits through the blur handler; no duplicate save here.
                    if (e.key === "Enter") e.currentTarget.blur();
                  }}
                  onblur={() => commitComboValue(watchedOnInput)}
                />
                <PopoverMenu
                  id={`watched-on-${media.id}`}
                  options={comboMenuItems}
                  selected={watchedOnInput}
                  onSelect={(value) => commitComboValue(String(value))}
                  label={comboLabel}
                  placement="bottom-end"
                  matchTriggerWidth={false}
                  class="max-h-64 min-w-[190px] overflow-y-auto"
                  optionClass="text-xs"
                >
                  {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
                    <button
                      type="button"
                      popovertarget={popoverTargetId}
                      popovertargetaction="toggle"
                      style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                      class="tap flex h-full w-7 shrink-0 items-center justify-center text-white/60 transition hover:text-white has-[:popover-open]:text-white"
                      aria-label={comboLabel}
                      aria-haspopup="listbox"
                    >
                      <ChevronDown
                        size={13}
                        class="transition duration-200 has-[:popover-open]:rotate-180"
                        aria-hidden="true"
                      />
                    </button>
                  {/snippet}
                  {#snippet renderOption({ option })}
                    <span class="min-w-0 flex-1 truncate">{option.label}</span>
                    <span class="flex shrink-0 items-center gap-1">
                      <span
                        role="button"
                        tabindex={0}
                        class="grid size-5 cursor-pointer place-items-center rounded transition hover:bg-white/10"
                        title={comboIsFavorite(option.value)
                          ? i18n.t.detail.unmarkFavorite
                          : i18n.t.detail.markFavorite}
                        aria-label={comboIsFavorite(option.value)
                          ? i18n.t.detail.unmarkFavorite
                          : i18n.t.detail.markFavorite}
                        onclick={(e) => {
                          e.stopPropagation();
                          toggleComboFavorite(option.value);
                        }}
                        onkeydown={(e) => {
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            e.stopPropagation();
                            toggleComboFavorite(option.value);
                          }
                        }}
                      >
                        <Star
                          size={13}
                          class={comboIsFavorite(option.value)
                            ? "fill-amber-300 text-amber-300"
                            : "text-muted hover:text-amber-200"}
                          aria-hidden="true"
                        />
                      </span>
                      {#if option.value === watchedOnInput}
                        <Check size={14} class="text-accent-soft shrink-0" aria-hidden="true" />
                      {/if}
                    </span>
                  {/snippet}
                </PopoverMenu>
              </div>
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
    <div class="mb-2 flex items-center justify-between gap-2">
      <h2 class="text-xs font-bold tracking-wider text-slate-200 uppercase">
        {i18n.t.detail.actionsTitle}
      </h2>
      <!-- Rare actions (covers, lists, source, activity) live in the compact "…" menu. -->
      <PopoverMenu
        id={`detail-actions-more-${media.id}`}
        options={moreActionItems}
        selected=""
        onSelect={(value) => runMoreAction(value as MoreAction)}
        label={i18n.t.detail.actionsMore}
        placement="bottom-end"
        matchTriggerWidth={false}
        class="min-w-[170px]"
        optionClass="text-xs"
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap grid size-7 cursor-pointer place-items-center rounded-md text-slate-300 transition hover:bg-white/[0.08] hover:text-white"
            title={i18n.t.detail.actionsMore}
            aria-label={i18n.t.detail.actionsMore}
            aria-haspopup="menu"
          >
            <Ellipsis size={15} aria-hidden="true" />
          </button>
        {/snippet}
        {#snippet renderOption({ option })}
          {@const Icon = moreActionIcon(option.value)}
          <span class="flex min-w-0 flex-1 items-center gap-2">
            {#if Icon}
              <Icon size={14} class="text-[var(--color-accent-soft)]" aria-hidden="true" />
            {/if}
            <span class="truncate">{option.label}</span>
          </span>
        {/snippet}
      </PopoverMenu>
    </div>
    <div class="panel space-y-1.5">
      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
        disabled={refreshBusy}
        onclick={() => void onRefreshMetadata()}
      >
        <RefreshCw
          size={14}
          class={`text-[var(--color-success-line)] ${refreshBusy ? "animate-spin" : ""}`}
          aria-hidden="true"
        />
        {i18n.t.detail.updateMetadata}
      </button>
      {#if refreshBusy && syncStep}<p class="text-muted px-1 text-[11px]" role="status">
          {syncStep}
        </p>{/if}
      {#if refreshError}<p class="text-xs text-rose-300" role="alert">
          {errorMessage(refreshError)}
        </p>{/if}

      {#if isOngoing}
        <button
          type="button"
          class="bg-surface/50 flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
          disabled={autoRefreshBusy}
          onclick={() => void handleAutoRefresh()}
        >
          <RefreshCw
            size={14}
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
        class="bg-surface/50 flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
        disabled={fillMissingBusy || refreshBusy}
        onclick={onFillMissing}
      >
        <Sparkles
          size={14}
          class={`text-[var(--color-accent-soft)] ${fillMissingBusy ? "animate-pulse" : ""}`}
          aria-hidden="true"
        />
        {fillMissingBusy ? i18n.t.detail.fillMissingRunning : i18n.t.detail.fillMissing}
      </button>

      <button
        type="button"
        class="bg-surface/50 flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
        onclick={onStartEdit}
      >
        <Pencil size={14} class="text-[var(--color-info-soft)]" aria-hidden="true" />
        {i18n.t.detailModal.edit}
      </button>

      <button
        type="button"
        class="tap bg-surface/50 flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-rose-300 transition hover:bg-[var(--color-panel-raised)] disabled:cursor-not-allowed disabled:opacity-70"
        disabled={deleteBusy}
        onclick={() => void onDelete()}
      >
        <Trash2 size={14} class="text-rose-400" aria-hidden="true" />
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
      <!-- Alt titles live outside the dl: a squashed right column cannot fit them.
           The tail beyond the first two folds in/out with a smooth slide. -->
      {#if splitAltTitles.length > 0}
        <div class="border-b border-white/5 pb-3">
          <h3 class="text-muted text-xs font-medium">{i18n.t.detail.altTitlesLabel}</h3>
          <ul class="mt-2 space-y-1">
            {#each splitAltTitles.slice(0, 2) as alt (alt)}
              <li class="text-xs leading-5 text-white/85">• {alt}</li>
            {/each}
          </ul>
          {#if showAllAltTitles && splitAltTitles.length > 2}
            <ul transition:slide={{ duration: 200 }} class="space-y-1 pt-1">
              {#each splitAltTitles.slice(2) as alt (alt)}
                <li class="text-xs leading-5 text-white/85">• {alt}</li>
              {/each}
            </ul>
          {/if}
          {#if splitAltTitles.length > 2}
            <button
              type="button"
              class="text-muted mt-1 inline-flex h-6 w-6 cursor-pointer items-center justify-center rounded-md transition hover:bg-white/[0.08] hover:text-white"
              aria-expanded={showAllAltTitles}
              title={showAllAltTitles
                ? i18n.t.detail.altTitlesLess
                : i18n.t.detail.altTitlesMore(splitAltTitles.length - 2)}
              onclick={() => (showAllAltTitles = !showAllAltTitles)}
            >
              <ChevronDown size={14} class={`transition ${showAllAltTitles ? "rotate-180" : ""}`} />
            </button>
          {/if}
        </div>
      {/if}

      <!-- Genres as matte chips across the full panel width; the long tail hides behind a
           spoiler that folds in/out with a smooth slide. -->
      {#if genreChips.length > 0}
        <div class="mt-3 border-b border-white/5 pb-3">
          <h3 class="text-muted text-xs font-medium">{i18n.t.detail.genresLabel}</h3>
          <div class="flex flex-wrap gap-1.5 pt-2">
            {#each genreChips.slice(0, 6) as genre (genre)}
              <span class="rounded-md bg-white/[0.04] px-2.5 py-1 text-xs text-slate-300"
                >{genreLabel(genre)}</span
              >
            {/each}
            {#if genreChips.length > 6}
              <button
                type="button"
                class="grid size-[30px] cursor-pointer place-items-center rounded-md bg-white/[0.04] text-slate-300 transition hover:bg-white/[0.08] hover:text-white"
                aria-expanded={showAllGenres}
                title={showAllGenres
                  ? i18n.t.detail.altTitlesLess
                  : i18n.t.detail.genresMore(genreChips.length - 6)}
                onclick={() => (showAllGenres = !showAllGenres)}
              >
                <ChevronDown size={14} class={`transition ${showAllGenres ? "rotate-180" : ""}`} />
              </button>
            {/if}
          </div>
          {#if showAllGenres && genreChips.length > 6}
            <div transition:slide={{ duration: 200 }} class="mt-1.5 flex flex-wrap gap-1.5">
              {#each genreChips.slice(6) as genre (genre)}
                <span class="rounded-md bg-white/[0.04] px-2.5 py-1 text-xs text-slate-300"
                  >{genreLabel(genre)}</span
                >
              {/each}
            </div>
          {/if}
        </div>
      {/if}

      <dl class="divide-y divide-white/5 pt-3 text-sm">
        {#each filteredSpecRows as row, idx (`${row.label}-${idx}`)}
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
                  class="text-accent-soft inline-flex items-center gap-1 transition-colors duration-150 hover:underline"
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

{#if isActivityOpen}
  {#await import("./MediaActivityModal.svelte") then { default: MediaActivityModal }}
    <MediaActivityModal
      isOpen={isActivityOpen}
      mediaId={media.id}
      title={media.title}
      onClose={() => (isActivityOpen = false)}
    />
  {/await}
{/if}

<!-- Rendered hidden while closed; the "…" menu flips `isOpen` to show the picker modal. -->
<ListPicker
  mediaId={media.id}
  isOpen={isListPickerOpen}
  onClose={() => (isListPickerOpen = false)}
/>

{#if isCoverManagerOpen}
  {#await import("./CoverManagerModal.svelte") then { default: CoverManagerModal }}
    <CoverManagerModal
      isOpen={isCoverManagerOpen}
      {media}
      onClose={() => (isCoverManagerOpen = false)}
      onUpdate={(updated) => {
        media = updated;
        onAutoRefreshed?.(updated);
        onMediaUpdated?.(updated);
      }}
    />
  {/await}
{/if}

<style>
  /* Rating popover entry: opacity + a light lift/scale, transform & opacity only. */
  .rating-pop {
    animation: rating-pop 140ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  @keyframes rating-pop {
    from {
      opacity: 0;
      transform: translateY(-4px) scale(0.96);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  /* The score number rolls over softly when the rating changes. */
  .score-pop {
    animation: score-pop 160ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  @keyframes score-pop {
    from {
      transform: scale(1.3);
    }
    to {
      transform: scale(1);
    }
  }
</style>
