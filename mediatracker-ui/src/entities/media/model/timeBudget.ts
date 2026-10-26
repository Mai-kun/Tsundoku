import type { MediaItem } from "$shared/types";

export type TimeBudgetMinutes = number | null;

export interface TimeFitResult {
  fits: boolean; // Вписывается ли тайтл в выбранный слот времени
  canFinishNow: boolean; // Можно ли полностью завершить тайтл до 100% за это время
  remainingMinutes: number | null; // Сколько всего минут осталось до конца тайтла
  sessionLabel: string; // Короткая подсказка для бейджа
}

/**
 * Formats a chosen time budget in minutes for display on compact trigger chips.
 */
export function formatTimeBudgetChip(minutes: number, locale: "ru" | "en" = "ru"): string {
  if (minutes < 60) {
    return locale === "ru" ? `${minutes} м` : `${minutes}m`;
  }
  if (minutes % 60 === 0 || minutes % 30 === 0) {
    const hours = minutes / 60;
    return locale === "ru" ? `${hours} ч` : `${hours}h`;
  }
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return locale === "ru" ? `${h}ч ${m}м` : `${h}h ${m}m`;
}

/**
 * Calculates whether a media item fits the user's available time budget and how much
 * progress can be achieved in a single session.
 */
export function evaluateTimeFit(
  item: MediaItem,
  budgetMinutes: number,
  bookPageMin: number,
  mangaChapterMin: number,
  locale: "ru" | "en" = "ru",
): TimeFitResult {
  if (!budgetMinutes || budgetMinutes <= 0) {
    return {
      fits: false,
      canFinishNow: false,
      remainingMinutes: null,
      sessionLabel: "",
    };
  }

  if (item.type === "movie") {
    const dur = item.durationMinutes && item.durationMinutes > 0 ? item.durationMinutes : 90;
    const fits = dur <= budgetMinutes;
    const canFinishNow = fits;
    const remainingMinutes = dur;
    const sessionLabel = locale === "ru" ? `🔥 Целиком: ${dur} мин.` : `🔥 Entire: ${dur} min`;
    return { fits, canFinishNow, remainingMinutes, sessionLabel };
  }

  if (item.type === "tvshow") {
    const rawEpDur =
      item.durationMinutes && item.durationMinutes > 0
        ? item.durationMinutes
        : item.episodeDurationMinutes && item.episodeDurationMinutes > 0
          ? item.episodeDurationMinutes
          : null;
    const epDur = rawEpDur ?? (item.isAnime ? 24 : 45);
    const fits = epDur <= budgetMinutes;
    const possibleEps = fits ? Math.floor(budgetMinutes / epDur) : 0;
    const leftEps =
      item.totalEpisodesCount > 0
        ? Math.max(0, item.totalEpisodesCount - (item.totalEpisodesWatched || 0))
        : null;
    const remainingMinutes = leftEps !== null ? leftEps * epDur : null;

    if (fits && leftEps !== null && leftEps > 0 && leftEps * epDur <= budgetMinutes) {
      const canFinishNow = true;
      const sessionLabel =
        locale === "ru"
          ? `🔥 Добить финал: ${leftEps} эп. (~${leftEps * epDur} мин.)`
          : `🔥 Finish: ${leftEps} ep. (~${leftEps * epDur} min)`;
      return { fits, canFinishNow, remainingMinutes, sessionLabel };
    }

    const canFinishNow = false;
    const epsToWatch = leftEps !== null ? Math.min(possibleEps, leftEps) : possibleEps;
    const sessionLabel =
      locale === "ru"
        ? fits
          ? `Успеете: ${epsToWatch} эп. (~${epsToWatch * epDur} мин.)`
          : `1 эп. (~${epDur} мин.)`
        : fits
          ? `Watch: ${epsToWatch} ep. (~${epsToWatch * epDur} min)`
          : `1 ep. (~${epDur} min)`;
    return { fits, canFinishNow, remainingMinutes, sessionLabel };
  }

  if (item.type === "book") {
    const pageMin = bookPageMin > 0 ? bookPageMin : 1.5;
    const pagesInSlot = Math.max(1, Math.round(budgetMinutes / pageMin));
    const leftPages =
      item.totalPages > 0 ? Math.max(0, item.totalPages - (item.currentPage || 0)) : null;
    const fits = pagesInSlot >= 5;
    const remainingMinutes = leftPages !== null ? Math.round(leftPages * pageMin) : null;

    if (fits && leftPages !== null && leftPages > 0 && leftPages * pageMin <= budgetMinutes) {
      const canFinishNow = true;
      const sessionLabel =
        locale === "ru"
          ? `🔥 Дочитать до конца: ${leftPages} стр. (~${Math.round(leftPages * pageMin)} мин.)`
          : `🔥 Finish: ${leftPages} pp. (~${Math.round(leftPages * pageMin)} min)`;
      return { fits, canFinishNow, remainingMinutes, sessionLabel };
    }

    const canFinishNow = false;
    const sessionLabel =
      locale === "ru" ? `За сессию: ~${pagesInSlot} стр.` : `In session: ~${pagesInSlot} pp.`;
    return { fits, canFinishNow, remainingMinutes, sessionLabel };
  }

  if (item.type === "manga") {
    const chMin = mangaChapterMin > 0 ? mangaChapterMin : 6.0;
    const chaptersInSlot = Math.floor(budgetMinutes / chMin);
    const fits = chaptersInSlot >= 1;
    const leftChapters =
      item.totalChapters && item.totalChapters > 0
        ? Math.max(0, item.totalChapters - (item.currentChapter || 0))
        : null;
    const remainingMinutes = leftChapters !== null ? Math.round(leftChapters * chMin) : null;

    if (
      fits &&
      leftChapters !== null &&
      leftChapters > 0 &&
      leftChapters * chMin <= budgetMinutes
    ) {
      const canFinishNow = true;
      const sessionLabel =
        locale === "ru"
          ? `🔥 Дочитать финал: ${leftChapters} гл. (~${Math.round(leftChapters * chMin)} мин.)`
          : `🔥 Finish: ${leftChapters} ch. (~${Math.round(leftChapters * chMin)} min)`;
      return { fits, canFinishNow, remainingMinutes, sessionLabel };
    }

    const canFinishNow = false;
    const sessionLabel =
      locale === "ru"
        ? fits
          ? `Успеете: ~${chaptersInSlot} гл.`
          : `~1 гл. (~${Math.round(chMin)} мин.)`
        : fits
          ? `You can read: ~${chaptersInSlot} ch.`
          : `~1 ch. (~${Math.round(chMin)} min)`;
    return { fits, canFinishNow, remainingMinutes, sessionLabel };
  }

  if (item.type === "game") {
    const fits = budgetMinutes >= 30;
    const canFinishNow = false;
    const remainingMinutes = null;
    const sessionLabel =
      locale === "ru"
        ? `Игровая сессия: ${budgetMinutes} мин.`
        : `Gaming session: ${budgetMinutes} min`;
    return { fits, canFinishNow, remainingMinutes, sessionLabel };
  }

  return {
    fits: false,
    canFinishNow: false,
    remainingMinutes: null,
    sessionLabel: "",
  };
}
