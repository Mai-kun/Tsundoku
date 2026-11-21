/// 1:1 port of `mediatracker-ui/src/entities/media/model/timeBudget.ts`.
library;

import '../../../shared/types/enums.dart';
import '../../../shared/types/models.dart';

/// `TimeBudgetMinutes = number | null`.
typedef TimeBudgetMinutes = int?;

class TimeFitResult {
  /// Вписывается ли тайтл в выбранный слот времени.
  final bool fits;
  /// Можно ли полностью завершить тайтл до 100% за это время.
  final bool canFinishNow;
  /// Сколько всего минут осталось до конца тайтла.
  final int? remainingMinutes;
  /// Короткая подсказка для бейджа.
  final String sessionLabel;

  const TimeFitResult({
    required this.fits,
    required this.canFinishNow,
    required this.remainingMinutes,
    required this.sessionLabel,
  });

  @override
  bool operator ==(Object other) =>
      other is TimeFitResult &&
      other.fits == fits &&
      other.canFinishNow == canFinishNow &&
      other.remainingMinutes == remainingMinutes &&
      other.sessionLabel == sessionLabel;

  @override
  int get hashCode => Object.hash(fits, canFinishNow, remainingMinutes, sessionLabel);

  @override
  String toString() =>
      'TimeFitResult(fits=$fits, canFinishNow=$canFinishNow, '
      'remainingMinutes=$remainingMinutes, sessionLabel=$sessionLabel)';
}

/// Formats a chosen time budget in minutes for display on compact trigger
/// chips.
String formatTimeBudgetChip(int minutes, {String locale = 'ru'}) {
  if (minutes < 60) {
    return locale == 'ru' ? '$minutes м' : '${minutes}m';
  }
  if (minutes % 60 == 0 || minutes % 30 == 0) {
    final hours = minutes / 60;
    return locale == 'ru'
        ? '${_fmtHours(hours)} ч'
        : '${_fmtHours(hours)}h';
  }
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return locale == 'ru' ? '$hч $mм' : '${h}h ${m}m';
}

String _fmtHours(double hours) =>
    hours == hours.roundToDouble() ? '${hours.toInt()}' : '$hours';

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

/// Calculates whether a media item fits the user's available time budget and
/// how much progress can be achieved in a single session.
TimeFitResult evaluateTimeFit(
  MediaItem item,
  int budgetMinutes,
  double bookPageMin,
  double mangaChapterMin, {
  String locale = 'ru',
}) {
  if (budgetMinutes <= 0) {
    return const TimeFitResult(
        fits: false, canFinishNow: false, remainingMinutes: null, sessionLabel: '');
  }

  if (item.type == MediaType.movie) {
    final dur =
        (item.durationMinutes != null && item.durationMinutes! > 0) ? item.durationMinutes! : 90;
    final fits = dur <= budgetMinutes;
    return TimeFitResult(
      fits: fits,
      canFinishNow: fits,
      remainingMinutes: dur,
      sessionLabel: locale == 'ru'
          ? '🔥 Целиком: $dur мин.'
          : '🔥 Entire: $dur min',
    );
  }

  if (item.type == MediaType.tvshow) {
    final rawEpDur =
        (item.durationMinutes != null && item.durationMinutes! > 0)
            ? item.durationMinutes
            : (item.episodeDurationMinutes != null && item.episodeDurationMinutes! > 0)
                ? item.episodeDurationMinutes
                : null;
    final epDur = rawEpDur ?? (item.isAnime == true ? 24 : 45);
    final fits = epDur <= budgetMinutes;
    final possibleEps = fits ? budgetMinutes ~/ epDur : 0;
    final leftEps = (item.totalEpisodesCount ?? 0) > 0
        ? _max(0, item.totalEpisodesCount! - (item.totalEpisodesWatched ?? 0))
        : null;
    final remainingMinutes = leftEps != null ? leftEps * epDur : null;

    if (fits && leftEps != null && leftEps > 0 && leftEps * epDur <= budgetMinutes) {
      return TimeFitResult(
        fits: fits,
        canFinishNow: true,
        remainingMinutes: remainingMinutes,
        sessionLabel: locale == 'ru'
            ? '🔥 Добить финал: $leftEps эп. (~${leftEps * epDur} мин.)'
            : '🔥 Finish: $leftEps ep. (~${leftEps * epDur} min)',
      );
    }

    final epsToWatch = leftEps != null ? _min(possibleEps, leftEps) : possibleEps;
    final sessionLabel = locale == 'ru'
        ? (fits ? 'Успеете: $epsToWatch эп. (~${epsToWatch * epDur} мин.)' : '1 эп. (~$epDur мин.)')
        : (fits ? 'Watch: $epsToWatch ep. (~${epsToWatch * epDur} min)' : '1 ep. (~$epDur min)');
    return TimeFitResult(
      fits: fits,
      canFinishNow: false,
      remainingMinutes: remainingMinutes,
      sessionLabel: sessionLabel,
    );
  }

  if (item.type == MediaType.book) {
    final pageMin = bookPageMin > 0 ? bookPageMin : 1.5;
    final pagesInSlot = _max(1, (budgetMinutes / pageMin).round());
    final leftPages = (item.totalPages ?? 0) > 0
        ? _max(0, item.totalPages! - (item.currentPage ?? 0))
        : null;
    final fits = pagesInSlot >= 5;
    final remainingMinutes = leftPages != null ? (leftPages * pageMin).round() : null;

    if (fits && leftPages != null && leftPages > 0 && leftPages * pageMin <= budgetMinutes) {
      return TimeFitResult(
        fits: fits,
        canFinishNow: true,
        remainingMinutes: remainingMinutes,
        sessionLabel: locale == 'ru'
            ? '🔥 Дочитать до конца: $leftPages стр. (~${(leftPages * pageMin).round()} мин.)'
            : '🔥 Finish: $leftPages pp. (~${(leftPages * pageMin).round()} min)',
      );
    }

    final sessionLabel = locale == 'ru'
        ? 'За сессию: ~$pagesInSlot стр.'
        : 'In session: ~$pagesInSlot pp.';
    return TimeFitResult(
      fits: fits,
      canFinishNow: false,
      remainingMinutes: remainingMinutes,
      sessionLabel: sessionLabel,
    );
  }

  if (item.type == MediaType.manga) {
    final chMin = mangaChapterMin > 0 ? mangaChapterMin : 6.0;
    final chaptersInSlot = budgetMinutes ~/ chMin;
    final fits = chaptersInSlot >= 1;
    final leftChapters = (item.totalChapters ?? 0) > 0
        ? _max(0, item.totalChapters! - (item.currentChapter ?? 0))
        : null;
    final remainingMinutes = leftChapters != null ? (leftChapters * chMin).round() : null;

    if (fits &&
        leftChapters != null &&
        leftChapters > 0 &&
        leftChapters * chMin <= budgetMinutes) {
      return TimeFitResult(
        fits: fits,
        canFinishNow: true,
        remainingMinutes: remainingMinutes,
        sessionLabel: locale == 'ru'
            ? '🔥 Дочитать финал: $leftChapters гл. (~${(leftChapters * chMin).round()} мин.)'
            : '🔥 Finish: $leftChapters ch. (~${(leftChapters * chMin).round()} min)',
      );
    }

    final sessionLabel = locale == 'ru'
        ? (fits
            ? 'Успеете: ~$chaptersInSlot гл.'
            : '~1 гл. (~${chMin.round()} мин.)')
        : (fits
            ? 'You can read: ~$chaptersInSlot ch.'
            : '~1 ch. (~${chMin.round()} min)');
    return TimeFitResult(
      fits: fits,
      canFinishNow: false,
      remainingMinutes: remainingMinutes,
      sessionLabel: sessionLabel,
    );
  }

  if (item.type == MediaType.game) {
    final fits = budgetMinutes >= 30;
    return TimeFitResult(
      fits: fits,
      canFinishNow: false,
      remainingMinutes: null,
      sessionLabel: locale == 'ru'
          ? 'Игровая сессия: $budgetMinutes мин.'
          : 'Gaming session: $budgetMinutes min',
    );
  }

  return const TimeFitResult(
      fits: false, canFinishNow: false, remainingMinutes: null, sessionLabel: '');
}
