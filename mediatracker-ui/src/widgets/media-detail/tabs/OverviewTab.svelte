<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import type { GameAchievementItem, MediaDetail } from "$shared/types";
  import type { MediaStatus } from "$shared/types/enums";
  import type { ProgressInfo } from "../detailTypes";
  import ProgressStepper from "../ProgressStepper.svelte";
  import GameDetailSection from "../sections/GameDetailSection.svelte";
  import CreatorSection from "../sections/CreatorSection.svelte";
  import NotesSection from "../sections/NotesSection.svelte";
  import QuotesSection from "../sections/QuotesSection.svelte";
  import QuickFactsSection from "../sections/QuickFactsSection.svelte";
  import CastSection from "../sections/CastSection.svelte";
  import TrailerSection from "../sections/TrailerSection.svelte";
  import BookProgressSection from "../sections/BookProgressSection.svelte";
  import BookEditionSection from "../sections/BookEditionSection.svelte";
  import MangaProgressSection from "../sections/MangaProgressSection.svelte";
  import MovieStatusSection from "../sections/MovieStatusSection.svelte";
  import TvShowProgressSection from "../sections/TvShowProgressSection.svelte";
  import type { CreatorRole, MangaDetail, MediaItem } from "$shared/types";

  interface Props {
    media: MediaDetail;
    /** Null when the type tracks no counter (e.g. a movie already watched). */
    support: ProgressInfo | null;
    progressValue: number;
    progressPercent: number;
    progressError: unknown;
    onStep: (delta: number) => void;
    /** Game counter; the parent owns the debounced write. */
    onCounterChange: (value: number) => void;
    achievements: readonly GameAchievementItem[];
    achievementsTotal: number;
    achievementsLoading: boolean;
    achievementsBusy: boolean;
    achievementsTruncated: boolean;
    unlockedAchievementNames: Map<string, string>;
    onToggleAchievement: (name: string) => Promise<void>;
    onToggleAllAchievements: () => Promise<void>;
    onOpenMedia: (item: MediaItem) => void;
    onSearch: (query: string) => void;
    onEdit: () => void;
    onChangeStatus?: (status: MediaStatus) => void;
  }

  let {
    media,
    support,
    progressValue,
    progressPercent,
    progressError,
    onStep,
    onCounterChange,
    achievements,
    achievementsTotal,
    achievementsLoading,
    achievementsBusy,
    achievementsTruncated,
    unlockedAchievementNames,
    onToggleAchievement,
    onToggleAllAchievements,
    onOpenMedia,
    onSearch,
    onEdit,
    onChangeStatus,
  }: Props = $props();

  const creator = $derived.by((): { name: string; role: CreatorRole; label: string } | null => {
    if (media.type === "movie") {
      if ((media.isAnime || (media as { type: string }).type === "anime") && media.studio?.trim()) {
        return {
          name: media.studio.trim(),
          role: "studio",
          label: i18n.t.creator.studio,
        };
      }
      if (media.director?.trim()) {
        return {
          name: media.director.trim(),
          role: "director",
          label: i18n.t.creator.director,
        };
      }
      if (media.studio?.trim()) {
        return {
          name: media.studio.trim(),
          role: "studio",
          label: i18n.t.creator.studio,
        };
      }
    } else if (media.type === "tvshow") {
      if (media.studio?.trim()) {
        return {
          name: media.studio.trim(),
          role: "studio",
          label: i18n.t.creator.studio,
        };
      }
      if (media.network?.trim()) {
        return {
          name: media.network.trim(),
          role: "studio",
          label: i18n.t.creator.network,
        };
      }
    } else if (media.type === "book" || media.type === "manga") {
      if (media.author?.trim()) {
        return {
          name: media.author.trim(),
          role: "author",
          label: media.type === "manga" ? i18n.t.creator.mangaka : i18n.t.creator.author,
        };
      }
    } else if (media.type === "game" && media.studio?.trim()) {
      return {
        name: media.studio.trim(),
        role: "studio",
        label: i18n.t.creator.developer,
      };
    }
    return null;
  });

  // Key crew from the stored staff snapshot: the card must render even when no
  // studio/author came with the metadata.
  const staff = $derived(media.staff ?? []);

  // Anime live-action types count as the anime category: they share the same payload shape.
  const categoryKey = $derived(
    (media.type === "tvshow" || media.type === "movie") && media.isAnime ? "anime" : media.type,
  );

  // The CastSection wrapper only renders when there is somebody to show; manga now carries a
  // stored characters snapshot, live-action carries the classic cast.
  const hasCast = $derived(
    (media.type === "movie" || media.type === "tvshow" || media.type === "manga") &&
      (media.cast?.length ?? 0) > 0,
  );

  const statusLabel = $derived.by(() => {
    switch (media.status) {
      case 0:
        return i18n.t.status.planned;
      case 1:
        return i18n.t.status.inProgress;
      case 2:
        return i18n.t.status.completed;
      case 3:
        return i18n.t.status.paused;
      default:
        return i18n.t.status.dropped;
    }
  });

  const isBook = $derived(media.type === "book");
  const isManga = $derived(media.type === "manga");
  const isMovie = $derived(media.type === "movie");
  const isTvShow = $derived(media.type === "tvshow");
  const hasQuotes = $derived(Boolean(media.quotesJson && media.quotesJson !== "[]"));
  const showQuotes = $derived(isBook || isManga || hasQuotes);
</script>

<div class="space-y-5">
  <QuickFactsSection {media} />

  <!-- Ladder, not a stretched grid: two independent columns, each block sized by
         its own content, so nothing stretches to match its neighbour and no black
         holes open up. Below lg the columns are `display: contents`, so the blocks
         fall back into one flow ordered Progress → Cast → Trailer → Studio → Notes. -->
  <div class="grid w-full grid-cols-1 items-start gap-4 lg:grid-cols-2">
    <!-- ЛЕВАЯ КОЛОНКА -->
    <div class="contents lg:flex lg:min-w-0 lg:flex-col lg:gap-4">
      <!-- 1. БЛОК ПРОГРЕССА: серии / страницы / главы, высота по содержимому -->
      <div class="order-1 min-w-0">
        {#if media.type === "game"}
          <GameDetailSection
            {progressValue}
            progressLabel={support?.label ?? i18n.t.detail.hoursLabel}
            {progressError}
            {onCounterChange}
            {achievements}
            {achievementsTotal}
            {achievementsLoading}
            {achievementsBusy}
            {achievementsTruncated}
            unlockedNames={unlockedAchievementNames}
            {onToggleAchievement}
            {onToggleAllAchievements}
          />
        {:else if isBook && support}
          <!-- Книги: расширенный блок с временными расчётами -->
          <BookProgressSection
            totalPages={(media as { totalPages: number }).totalPages ?? 0}
            currentPage={(media as { currentPage: number }).currentPage ?? 0}
            progress={support}
            value={progressValue}
            percent={progressPercent}
            error={progressError}
            {onStep}
            {onCounterChange}
          />
        {:else if isManga && support}
          <!-- Манга: расширенный блок с расчетом времени и главами -->
          <MangaProgressSection
            media={media as MangaDetail}
            totalChapters={(media as MangaDetail).totalChapters ?? 0}
            currentChapter={(media as MangaDetail).currentChapter ?? 0}
            progress={support}
            value={progressValue}
            percent={progressPercent}
            error={progressError}
            {onStep}
            {onCounterChange}
          />
        {:else if isTvShow && support}
          <!-- Сериалы и аниме: расширенный блок с аналитикой времени просмотра -->
          <TvShowProgressSection
            {media}
            totalEpisodes={support.total ?? 0}
            watchedEpisodes={progressValue}
            progress={support}
            value={progressValue}
            percent={progressPercent}
            error={progressError}
            {onStep}
            {onCounterChange}
          />
        {:else if isMovie}
          <!-- Фильмы: хронометраж + статус вместо плоской плашки -->
          <MovieStatusSection {media} {statusLabel} {onEdit} {onChangeStatus} />
        {:else if support && support.editable}
          <ProgressStepper
            progress={support}
            value={progressValue}
            percent={progressPercent}
            error={progressError}
            {onStep}
            {onCounterChange}
          />
        {:else}
          <div
            class="flex flex-col justify-center rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
          >
            <span class="text-muted text-xs font-bold tracking-wider uppercase"
              >{i18n.t.status.label}</span
            >
            <span class="mt-1 text-lg font-bold text-white">{statusLabel}</span>
          </div>
        {/if}
      </div>

      <!-- 3. БЛОК ВИДЕО / ТРЕЙЛЕРА: нативный плеер aspect-video -->
      {#if media.trailerVideoId}
        <div class="order-3 min-w-0">
          <TrailerSection trailerVideoId={media.trailerVideoId} title={media.title} />
        </div>
      {/if}

      <!-- 5. БЛОК ЦИТАТ: для книг, манги или тайтлов с сохраненными цитатами -->
      {#if showQuotes}
        <div class="order-5 min-w-0">
          <QuotesSection {media} />
        </div>
      {/if}

      <!-- 7. БЛОК ЗАМЕТОК: closes the left column, which is what balances its height
                 against cast + creator on the right. -->
      <div class="order-7 min-w-0">
        <NotesSection notes={media.notes} {onEdit} />
      </div>
    </div>

    <!-- ПРАВАЯ КОЛОНКА -->
    <div class="contents lg:flex lg:min-w-0 lg:flex-col lg:gap-4">
      <!-- 2. БЛОК АКТЕРОВ (СЭЙЮ) -->
      {#if hasCast}
        <div class="order-2 min-w-0">
          <CastSection {media} />
        </div>
      {/if}

      <!-- 4. БЛОК СТУДИИ / АВТОРА + КОМАНДЫ СОЗДАТЕЛЕЙ -->
      <div class="order-4 min-w-0">
        {#if creator || staff.length > 0}
          <CreatorSection
            creatorName={creator?.name ?? ""}
            role={creator?.role ?? "author"}
            mediaType={media.type}
            label={creator?.label ?? null}
            imageUrl={media.creatorImageUrl ?? null}
            {staff}
            category={categoryKey}
            currentMediaId={media.id}
            {onOpenMedia}
            {onSearch}
          />
        {:else}
          <div
            class="text-muted flex items-center rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 text-sm shadow-sm"
          >
            {i18n.t.creator.noCreator}
          </div>
        {/if}
      </div>

      <!-- 6. Книги: карточка «Об издании» -->
      {#if isBook}
        <div class="order-6 min-w-0">
          <BookEditionSection media={media as typeof media & { type: "book" }} />
        </div>
      {/if}
    </div>
  </div>
</div>
