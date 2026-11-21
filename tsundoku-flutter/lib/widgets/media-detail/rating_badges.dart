/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/ratingBadges.ts`.
///
/// Единый список бейджей для трёх потребителей рейтингов (шапка библиотеки,
/// превью related, search-превью). Два поведения, которые раньше дублировались
/// трижды: score 0 = «спрошено, рейтинга нет» (плейсхолдер, не «источник
/// отсутствует»), выключенные источники выбрасываются целиком.
library;

import '../../shared/types/index.dart' show SourceInfo;
import 'detail_types.dart';

/// Источники по категориям, когда список включённых источников ещё не
/// загружен (или недоступен) — шапка всё равно показывает ожидаемые бейджи.
const Map<String, List<String>> kCategoryExpectedSources = {
  'anime': ['AniList'],
  'manga': ['AniList', 'MangaDex', 'MangaUpdates'],
  'movie': ['TMDB'],
  'tvshow': ['TMDB'],
  'game': ['RAWG', 'Steam'],
  'book': ['OpenLibrary'],
};

/// Сырой рейтинг от источника (Svelte-интерфейс RawRating).
class RawRating {
  final String source;
  final double? rating;
  final int? votes;
  final bool queried;

  const RawRating({
    required this.source,
    required this.rating,
    this.votes,
    this.queried = false,
  });
}

/// Fallback одиночного score (Svelte: fallback-объект в RatingBadgeInput).
class FallbackRating {
  final String source;
  final double score;
  final int? votes;

  const FallbackRating({
    required this.source,
    required this.score,
    this.votes,
  });
}

/// Вход buildRatingBadges (Svelte-интерфейс RatingBadgeInput).
class RatingBadgeInput {
  /// Рейтинги, уже пришедшие от источников, в порядке провайдера.
  final List<RawRating> ratings;

  /// Fallback одиночного score для источников с одним числом вместо списка.
  /// Используется, только когда [ratings] пуст.
  final FallbackRating? fallback;

  /// Категория агрегатора — решает, каких источников «не хватает».
  final String category;
  final List<SourceInfo> availableSources;

  /// Используется, когда [availableSources] пуст.
  final List<String>? fallbackSources;

  /// Добавлять ли плейсхолдеры для ожидаемых источников, которые не ответили.
  final bool includeMissing;

  /// Когда задан — бейджи рендерятся ТОЛЬКО для источников, привязанных к
  /// тайтлу.
  final List<String>? linkedSources;

  const RatingBadgeInput({
    required this.ratings,
    this.fallback,
    required this.category,
    required this.availableSources,
    this.fallbackSources,
    this.includeMissing = true,
    this.linkedSources,
  });
}

bool matchesSource(String s1, String s2) {
  final a = s1.trim().toLowerCase();
  final b = s2.trim().toLowerCase();
  if (a == b) return true;
  return a.contains(b) || b.contains(a);
}

/// Список бейджей: рейтинги (дедуп) → fallback → linkedSources-фильтр →
/// плейсхолдеры ожидаемых источников.
List<RatingBadge> buildRatingBadges(RatingBadgeInput input) {
  final results = <RatingBadge>[];
  final seen = <String>{};
  final disabledSources = <String>{
    for (final s in input.availableSources.where((s) => !s.isEnabled)) ...[
      s.name.toLowerCase(),
      s.id.toLowerCase(),
    ],
  };

  for (final r in input.ratings) {
    final src = r.source.trim();
    if (src.isEmpty || disabledSources.contains(src.toLowerCase())) continue;
    // SocialLib — зонт над MangaLib/AnimeLib/RanobeLib: per-site бейджи несут
    // score, а сама зонт-строка бейджем рейтинга не рендерится.
    if (src.toLowerCase().contains('sociallib')) continue;
    final key = src.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    results.add(RatingBadge(
      source: src,
      score: r.rating != null && r.rating! > 0 ? r.rating : null,
      votes: r.votes,
      queried: r.queried,
    ));
  }

  if (results.isEmpty &&
      input.fallback != null &&
      !disabledSources.contains(input.fallback!.source.toLowerCase())) {
    // Зонт-бейдж не рендерится и как fallback одиночного score: точное имя
    // сайта («MangaLib») предпочтительнее, а голый SocialLib не всплывает.
    if (input.fallback!.source.toLowerCase().contains('sociallib')) {
      return results;
    }
    seen.add(input.fallback!.source.toLowerCase());
    results.add(RatingBadge(
      source: input.fallback!.source,
      score: input.fallback!.score,
      votes: input.fallback!.votes,
    ));
  }

  if (input.linkedSources != null) {
    bool isLinked(String src) =>
        input.linkedSources!.any((ls) => matchesSource(ls, src));
    final linkedResults =
        results.where((r) => isLinked(r.source)).toList();
    final seenLinked = <String>{
      for (final r in linkedResults) r.source.toLowerCase(),
    };

    for (final ls in input.linkedSources!) {
      final lsClean = ls.trim();
      if (lsClean.isEmpty) continue;
      final lsNorm = lsClean.toLowerCase();
      if (disabledSources.contains(lsNorm) || lsNorm.contains('sociallib')) {
        continue;
      }

      final found = seenLinked.any(
          (s) => s.contains(lsNorm) || lsNorm.contains(s));
      if (!found) {
        seenLinked.add(lsNorm);
        final resolvedName = input.availableSources
            .where((s) =>
                matchesSource(s.id, lsClean) ||
                matchesSource(s.name, lsClean))
            .map((s) => s.name)
            .firstOrNull ??
            lsClean;
        linkedResults.add(RatingBadge(source: resolvedName, score: null));
      }
    }

    return linkedResults;
  }

  if (!input.includeMissing) return results;

  final expected =
      input.availableSources.isNotEmpty
          ? input.availableSources
              .where((s) =>
                  s.isEnabled && s.mediaTypes.contains(input.category))
              .map((s) => s.name)
              .toList()
          : (input.fallbackSources ??
              kCategoryExpectedSources[input.category] ??
              const <String>[]);

  for (final exp in expected) {
    final expNorm = exp.toLowerCase();
    // Правило зонта для «ожидаем, но не ответили»-плейсхолдеров: SocialLib не
    // получает пустой бейдж, даже если в настройках он включён.
    if (expNorm.contains('sociallib')) continue;
    // Имена провайдеров варьируются («MyAnimeList» vs «MAL») — матч по
    // вхождению в обе стороны.
    final found = seen.any((s) => s.contains(expNorm) || expNorm.contains(s));
    if (!found) {
      seen.add(expNorm);
      results.add(RatingBadge(source: exp, score: null));
    }
  }

  return results;
}
