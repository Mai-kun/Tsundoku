/// 1:1 port of `mediatracker-ui/src/entities/media/model/progressRules.ts`.
///
/// Мутация TS-объекта (writeCardProgress) → иммутабельный copyWithFields
/// (решение #14): функции возвращают обновлённый [MediaItem].
library;

import '../../../shared/types/enums.dart';
import '../../../shared/types/models.dart';

int clampProgress(int current, int? total) {
  final safeCurrent = current < 0 ? 0 : current;
  return (total != null && total > 0)
      ? (safeCurrent > total ? total : safeCurrent)
      : safeCurrent;
}

bool _isNovel(MediaItem item) =>
    item.format == 'light_novel' || item.format == 'web_novel';

/// Games, books, manga and shows expose the user-driven field each of these
/// reads.
int readCardProgress(MediaItem item) {
  switch (item.type) {
    case MediaType.game:
      return item.hoursPlayed ?? 0;
    case MediaType.book:
      return _isNovel(item) ? (item.currentChapter ?? 0) : (item.currentPage ?? 0);
    case MediaType.manga:
      return item.currentChapter ?? 0;
    case MediaType.tvshow:
      return item.totalEpisodesWatched ?? 0;
    default:
      return 0;
  }
}

int? cardProgressTotal(MediaItem item) {
  switch (item.type) {
    case MediaType.book:
      return _isNovel(item) ? item.totalChapters : item.totalPages;
    case MediaType.manga:
      return item.totalChapters;
    default:
      return null;
  }
}

/// Mirrors [readCardProgress] for writes: keeps the item in sync with an
/// optimistic step, so a parent map that spreads the item (e.g. a status
/// flip) carries the new progress instead of reverting it.
MediaItem writeCardProgress(MediaItem item, int value) {
  switch (item.type) {
    case MediaType.game:
      return item.copyWithFields(hoursPlayed: value);
    case MediaType.book:
      return _isNovel(item)
          ? item.copyWithFields(currentChapter: value)
          : item.copyWithFields(currentPage: value);
    case MediaType.manga:
      return item.copyWithFields(currentChapter: value);
    case MediaType.tvshow:
      return item.copyWithFields(totalEpisodesWatched: value);
    default:
      return item;
  }
}

/// Only games, books and manga carry a stepper; movies do not. (TV-шоу
/// держат поштучный счёт эпизодов — в исходнике включены в степпер.)
bool supportsProgressStepper(MediaItem item) {
  return item.type == MediaType.game ||
      item.type == MediaType.book ||
      item.type == MediaType.manga ||
      item.type == MediaType.tvshow;
}

/// Next value after a +/- press, clamped to the known total (never below
/// zero).
int nextCardProgress(MediaItem item, int current, int delta) {
  return clampProgress(current + delta, cardProgressTotal(item));
}

/// Rule 1 of the status contract: the exact 0 → 1 step implies the title is
/// being consumed right now and promotes it to InProgress. Any other progress
/// change keeps the current status — dropped stays dropped, on hold stays on
/// hold, planned stays planned. Mirrors the backend's
/// ProgressStepperRules.PromotesToInProgress, so an optimistic click never
/// diverges from the server's stored state.
bool shouldPromoteToInProgress(int previous, int next) {
  return previous == 0 && next == 1;
}
