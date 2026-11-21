/// 1:1 port of `mediatracker-ui/src/features/prefetch-details/mediaDetailPrefetch.ts`.
///
/// Методика 3: in-memory guard. Всё, что уже загружено (или грузится прямо
/// сейчас), отсекается ещё до отправки запроса в сеть.
///
/// Hover-intent (150ms debounce) и scroll-guard в Flutter управляются из
/// MediaGrid (Фаза 2): колбеки [onHoverIntentChanged]/[setScrolling] вместо
/// document.getElementById (решение #13). `void import($views/...)` не нужен —
/// ленивая загрузка вью в Dart отсутствует.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../shared/api/api.dart';
import '../../shared/types/models.dart';
import '../../shared/utils/prefetch_cache.dart';

const Duration detailTtl = Duration(minutes: 5);
const Duration hoverIntent = Duration(milliseconds: 150);

/// `export const mediaDetailCache = createPrefetchCache<MediaDetail>(...)`.
final mediaDetailCacheProvider =
    Provider<PrefetchCache<MediaDetail>>((ref) => createPrefetchCache<MediaDetail>(
          detailTtl.inMilliseconds,
        ));

/// `loadMediaDetail(id)` — ядро без Riverpod (тестируемость).
Future<MediaDetail> loadMediaDetail(
    PrefetchCache<MediaDetail> cache, TsundokuApi api, String id) {
  return cache.load(id, () => api.getMediaItem(id));
}

/// Ref-обёртка для контроллеров.
Future<MediaDetail> loadMediaDetailRef(Ref ref, String id) {
  return loadMediaDetail(
    ref.read(mediaDetailCacheProvider),
    ref.read(apiClientProvider),
    id,
  );
}

/// Patches the cached detail payload with an optimistic progress value, so
/// opening the detail screen right after stepping a card shows the new number
/// immediately instead of the pre-step one while the refetch is in flight.
void updateCachedDetailProgress(
    PrefetchCache<MediaDetail> cache, String id, int value) {
  final cached = cache.peek(id);
  if (cached != null && cached.id == id) {
    final patched = writeCardProgress(cached, value);
    cache.set(id, patched as MediaDetail);
  }
}

void updateCachedDetailProgressRef(Ref ref, String id, int value) {
  updateCachedDetailProgress(ref.read(mediaDetailCacheProvider), id, value);
}

/// `prefetchMediaDetail(id)` — best-effort: ошибка уйдёт пользователю при
/// реальном открытии.
void prefetchMediaDetail(PrefetchCache<MediaDetail> cache, TsundokuApi api, String id) {
  loadMediaDetail(cache, api, id).then((_) {}, onError: (Object _) {
    // Префетч best-effort: ошибка уйдёт пользователю при реальном открытии.
  });
}

/// Наведение мыши по сетке вызывает hover-события на десятках карточек подряд.
/// Один общий таймер вместо таймера на карточку: запросит только последняя.
/// Во время скролла таймер не ставится — скролл пролетает мимо, намерения нет.
class HoverPrefetchScheduler {
  final PrefetchCache<MediaDetail> cache;
  Timer? _hoverTimer;
  bool _isScrolling = false;
  Timer? _scrollTimer;

  HoverPrefetchScheduler(this.cache);

  /// MediaGrid (Фаза 2) сообщает о прокрутке: гасит префетч на время скролла
  /// (+150 мс тишины) — аналог scroll-guard `#main-scroll`.
  void setScrolling() {
    _isScrolling = true;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 150), () {
      _isScrolling = false;
    });
  }

  void schedule(String id, void Function(String id) prefetch) {
    if (_isScrolling) return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(hoverIntent, () {
      prefetch(id);
    });
  }

  void dispose() {
    _hoverTimer?.cancel();
    _scrollTimer?.cancel();
  }
}

/// Инстанс hover-шедулера (аналог модульных `hoverTimer`/`isScrolling`).
final hoverPrefetchSchedulerProvider = Provider<HoverPrefetchScheduler>((ref) {
  final scheduler = HoverPrefetchScheduler(ref.read(mediaDetailCacheProvider));
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
