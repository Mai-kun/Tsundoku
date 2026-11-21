/// 1:1 port of `mediatracker-ui/src/features/prefetch-details/externalDetailPrefetch.ts`.
///
/// Внешние детали никогда не пишутся в БД: они принадлежат результату поиска,
/// а не библиотеке. Тот же in-memory guard, что у библиотечного детайла;
/// 10 минут — как у серверного кэша агрегатора.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api/api.dart';
import '../../shared/types/models.dart';
import '../../shared/utils/prefetch_cache.dart';

const Duration detailsTtl = Duration(minutes: 10);

final externalDetailsCacheProvider =
    Provider<PrefetchCache<ExternalMedia>>((ref) => createPrefetchCache<ExternalMedia>(
          detailsTtl.inMilliseconds,
        ));

/// Ключ кэша: один и тот же тайтл из разных источников — это разные запросы.
String detailsKey(String type, ExternalMedia item) =>
    '$type:${item.externalSource ?? ''}:${item.externalId.isNotEmpty ? item.externalId : item.title}';

/// Полные метаданные результата поиска.
///
/// getExternalDetails глотает transport-ошибки и отдаёт null, поэтому null
/// пробрасывается как rejection: иначе минутная недоступность провайдера
/// залипла бы в кэше на все 10 минут. Вызывающий ловит ошибку сам и показывает
/// то, что уже есть из результата поиска.
Future<ExternalMedia> loadExternalDetailsCore(
    PrefetchCache<ExternalMedia> cache, TsundokuApi api, String type, ExternalMedia item) {
  return cache.load(detailsKey(type, item), () async {
    final result = await api.getExternalDetails(
      type,
      item.externalId,
      item.title,
      source: item.externalSource,
    );
    if (result == null) {
      throw StateError('External details unavailable');
    }
    return result;
  });
}

/// Ref-обёртка для контроллеров.
Future<ExternalMedia> loadExternalDetails(Ref ref, String type, ExternalMedia item) {
  return loadExternalDetailsCore(
    ref.read(externalDetailsCacheProvider),
    ref.read(apiClientProvider),
    type,
    item,
  );
}
