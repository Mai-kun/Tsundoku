/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/relationSources.ts`.
///
/// Какие источники реально умеют отвечать «что ещё есть по вселенной?» для
/// типа медиа: whitelist источников с relations-эндпоинтом, суженный до
/// включённых пользователем в настройках.
library;

import '../../shared/api/api.dart';
import '../../shared/types/index.dart' show MediaItem, SourceInfo;
import 'detail_formatters.dart' show isAnime;

/// Источники, у которых есть relations (1-в-1 с RELATION_SOURCES).
const Map<String, List<String>> kRelationSources = {
  'movie': ['tmdb'],
  'tvshow': ['tmdb'],
  'game': ['rawg'],
  'anime': ['anilist', 'shikimori', 'kitsu'],
  // Shikimori отдаёт relations для manga/ranobe-деревьев, MangaUpdates несёт
  // related_series прямо в ответе details.
  'manga': ['anilist', 'mangadex', 'kitsu', 'shikimori', 'mangaupdates'],
  // Kitsu хранит новеллы в manga-дереве с той же таблицей media-relationships;
  // Shikimori отдаёт новеллы из отдельного ranobe-дерева.
  'book': ['kitsu', 'shikimori'],
};

/// Опция выбора источника relations (Svelte-интерфейс RelationSourceOption).
class RelationSourceOption {
  final String id;
  final String label;

  const RelationSourceOption({required this.id, required this.label});
}

/// Relations-источники для этого тайтла, суженные до включённых пользователем.
Future<List<RelationSourceOption>> availableRelationSources(
    TsundokuApi api, MediaItem item) async {
  final typeWire = item.type.wire;
  final bucket =
      (item.isAnime ?? false) || typeWire == 'anime' || isAnime(item)
          ? 'anime'
          : typeWire;
  final allowed = kRelationSources[bucket];
  if (allowed == null || allowed.isEmpty) return [];

  List<SourceInfo> sources;
  try {
    sources = await api.getSources();
  } catch (_) {
    return [];
  }

  return sources
      .where((source) => source.isEnabled)
      .where((source) {
        final haystack = '${source.id} ${source.name}'.toLowerCase();
        return allowed.any((needle) => haystack.contains(needle));
      })
      .map((source) =>
          RelationSourceOption(id: source.id, label: source.name))
      .toList();
}
