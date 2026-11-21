/// 1:1 port of `mediatracker-ui/src/features/update-progress/seriesProgressController.svelte.ts`.
///
/// TV/Anime episode stepping without the per-click network race. A click only
/// moves the local counter (0 ms) and registers into a per-media 3s debounce;
/// the flush computes ONE season write for the final absolute total and sends
/// it. Season data comes from the shared prefetch cache (absolute totals only
/// — stale `currentEpisode` values in the snapshot cannot change the result),
/// fetched at most once per media when absent.
///
/// SvelteMap contexts/debouncers → поля реестра; showToast/i18n — инъекция
/// (решение #15); item-мутации → copyWithFields (решение #14).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../entities/media/model/series_step.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import '../../shared/utils/progress_debounce.dart';
import '../prefetch-details/media_detail_prefetch.dart';
import 'optimistic_progress.dart';
import 'status_promotion_toast.dart';

class SeriesStepContext {
  MediaItem item; // изменяется rollback-ом (аналог TS writeCardProgress(context.item…))
  /// Series total before the first pending step: the error rollback target.
  final int previousTotal;
  final void Function(String id)? onCommitted;

  SeriesStepContext({
    required this.item,
    required this.previousTotal,
    this.onCommitted,
  });
}

/// Season write that puts the series at exactly `value` watched episodes.
SeriesEpisodeStep? absoluteSeriesTarget(List<TvSeason> seasons, int value) {
  if (seasons.isEmpty) return null;
  final ordered = [...seasons]..sort((a, b) => a.seasonNumber - b.seasonNumber);

  var cumulative = 0;
  for (final season in ordered) {
    final total = season.totalEpisodes;
    // A season with an unknown length ends the walk: everything left lands
    // there.
    if (total <= 0 || value <= cumulative + total) {
      return SeriesEpisodeStep(
          seasonId: season.id, currentEpisode: value - cumulative < 0 ? 0 : value - cumulative);
    }
    cumulative += total;
  }
  final last = ordered.last;
  return SeriesEpisodeStep(
      seasonId: last.id, currentEpisode: last.totalEpisodes);
}

Future<SeriesEpisodeStep?> resolveSeriesStep(
    ProviderContainer ref, String id, int value) async {
  try {
    final detail = await loadMediaDetailRef(ref, id);
    if (!isTvShowDetail(detail) || (detail.seasons?.isEmpty ?? true)) return null;
    return absoluteSeriesTarget(detail.seasons!, value);
  } catch (_) {
    return null;
  }
}

typedef ShowToastFn = void Function({
  required String title,
  required String description,
  String type,
});

/// Реестр контекстов/дебаунсеров (аналог модульных SvelteMap) + API всех
/// step-операций. Провайдер приложения создаёт один инстанс.
class SeriesProgressController {
  final ProviderContainer ref;
  final ShowToastFn showToast;
  final Map<String, SeriesStepContext> _contexts = <String, SeriesStepContext>{};
  final Map<String, ProgressDebouncer> _debouncers = <String, ProgressDebouncer>{};

  SeriesProgressController({required this.ref, required this.showToast});

  ProgressDebouncer _getDebouncer(String id) {
    final existing = _debouncers[id];
    if (existing != null) return existing;
    final debouncer = ProgressDebouncer(ProgressDebounceOptions(
      send: (mediaId, value) async {
        final step = await resolveSeriesStep(ref, mediaId, value);
        if (step == null) return;
        await ref.read(apiClientProvider).setSeasonProgress(step.seasonId, step.currentEpisode);
      },
      // Keepalive flush (tab hide / window close) cannot await a fetch for the
      // season list: it targets the seasons snapshot already in memory.
      buildRequest: (mediaId, value) {
        final cached = ref.read(mediaDetailCacheProvider).peek(mediaId);
        if (cached != null &&
            isTvShowDetail(cached) &&
            (cached.seasons?.isNotEmpty ?? false)) {
          final step = absoluteSeriesTarget(cached.seasons!, value);
          if (step != null) {
            return ProgressRequest(
              url: '/api/seasons/${step.seasonId}/progress',
              body: {'currentEpisode': step.currentEpisode},
            );
          }
        }
        return const ProgressRequest(url: '', body: null);
      },
      onCommitted: (value) {
        final context = _contexts[id];
        ref.read(optimisticProgressProvider.notifier).resolve(id, value);
        ref.read(mediaDetailCacheProvider).invalidate(id);
        context?.onCommitted?.call(id);
        _contexts.remove(id);
      },
      onError: (failure) {
        final context = _contexts.remove(id);
        ref.read(optimisticProgressProvider.notifier).clear(id);
        if (context != null) {
          // Roll the raw item back; the card's effect reads this field, so
          // the visible counter resnaps without any extra plumbing.
          context.item = writeCardProgress(context.item, context.previousTotal);
          showToast(
            title: ref.read(tProvider).tr('toast.actionFailed'),
            description: errorMessage(failure, ref.read(i18nProvider)),
            type: 'error',
          );
        }
      },
    ));
    _debouncers[id] = debouncer;
    return debouncer;
  }

  /// Оптимистично поднимает кэшированный seasons-снимок, чтобы
  /// hover-prefetched detail не открылся с pre-step числами.
  void _patchCachedSeasonStep(String id, int delta) {
    final cached = ref.read(mediaDetailCacheProvider).peek(id);
    if (cached == null || !isTvShowDetail(cached) || (cached.seasons?.isEmpty ?? true)) {
      return;
    }
    final step = nextSeriesEpisodeStep(cached.seasons!, delta);
    if (step == null) return;
    final seasons = cached.seasons!
        .map((s) => s.id == step.seasonId
            ? TvSeason.fromJson({...s.toJson(), 'currentEpisode': step.currentEpisode})
            : s)
        .toList();
    ref
        .read(mediaDetailCacheProvider)
        .set(id, cached.copyWithFields(seasons: seasons));
  }

  void stepSeriesEpisodes(
    MediaItem item,
    int delta, {
    void Function(String id)? onCommitted,
  }) {
    final current = item.totalEpisodesWatched ?? 0;
    final next = current + delta < 0 ? 0 : current + delta;
    if (next == current) return;

    // Rule 1 of the status contract: only the exact 0 → 1 step of the series
    // total implies watching started. The badge flips optimistically here; the
    // debounced season PUT carries the same rule server-side, so a refetch (or
    // an F5) shows the very same status. The flip is announced by an
    // interactive toast with persisted undo / keep-status outcomes.
    if (shouldPromoteToInProgress(current, next) &&
        item.status != MediaStatus.inProgress) {
      final previousStatus = item.status;
      final flipped = item.copyWithFields(status: MediaStatus.inProgress);
      notifyAutoInProgress(flipped, previousStatus,
          show: (spec) {
            // Показ тоста выполняется общей infra-инъекцией контроллера.
            showToast(title: spec.title, description: spec.description, type: spec.type);
          },
          handlers: StatusPromotionHandlers(
            undo: () => _revertSeriesPromotion(item, previousStatus),
            keepStatus: () => _keepSeriesProgressOnly(item, previousStatus, next),
          ));
      // Обновляем контекст на переведённый item.
      _contexts[item.id] = SeriesStepContext(
        item: flipped,
        previousTotal: _contexts[item.id]?.previousTotal ?? current,
        onCommitted: onCommitted ?? _contexts[item.id]?.onCommitted,
      );
    }

    final targetItem = _contexts[item.id]?.item ?? item;
    _contexts[item.id] = SeriesStepContext(
      item: writeCardProgress(targetItem, next),
      // Roll back to where the burst started, not to the previous click.
      previousTotal: _contexts[item.id]?.previousTotal ?? current,
      onCommitted: onCommitted ?? _contexts[item.id]?.onCommitted,
    );
    ref.read(optimisticProgressProvider.notifier).apply(item.id, next);
    updateCachedDetailProgressRef(ref, item.id, next);
    _patchCachedSeasonStep(item.id, delta);

    _getDebouncer(item.id).schedule(item.id, next);
  }

  /// Undo for a series: the pending season write is cancelled, then the first
  /// season is zeroed and the previous status restored — both persisted
  /// server-side.
  Future<void> _revertSeriesPromotion(MediaItem item, MediaStatus previousStatus) async {
    _getDebouncer(item.id).cancel();
    ref.read(optimisticProgressProvider.notifier).clear(item.id);
    ref.read(mediaDetailCacheProvider).invalidate(item.id);
    _contexts[item.id] = SeriesStepContext(
      item: writeCardProgress(item, 0).copyWithFields(status: previousStatus),
      previousTotal: 0,
      onCommitted: _contexts[item.id]?.onCommitted,
    );
    try {
      final step = await resolveSeriesStep(ref, item.id, 0);
      if (step != null) {
        await ref.read(apiClientProvider).setSeasonProgress(step.seasonId, step.currentEpisode);
      }
    } catch (failure) {
      // console.error аналог.
    }
    ref
        .read(apiClientProvider)
        .updateStatus(item.id, previousStatus)
        .catchError((Object failure) {});
  }

  /// Keep-status for a series: the progress stays (persisted explicitly, since
  /// the debounced write is cancelled) and the previous status is restored.
  Future<void> _keepSeriesProgressOnly(
      MediaItem item, MediaStatus previousStatus, int value) async {
    _getDebouncer(item.id).cancel();
    _contexts[item.id] = SeriesStepContext(
      item: item.copyWithFields(status: previousStatus),
      previousTotal: _contexts[item.id]?.previousTotal ?? 0,
      onCommitted: _contexts[item.id]?.onCommitted,
    );
    try {
      final step = await resolveSeriesStep(ref, item.id, value);
      if (step != null) {
        await ref.read(apiClientProvider).setSeasonProgress(step.seasonId, step.currentEpisode);
      }
    } catch (failure) {
      // console.error аналог.
    }
    ref
        .read(apiClientProvider)
        .updateStatus(item.id, previousStatus)
        .catchError((Object failure) {});
  }
}

final seriesProgressControllerProvider = Provider<SeriesProgressController>((ref) {
  return SeriesProgressController(ref: ref.container, showToast: ({required title, required description, type = 'info'}) {
    // Реальный toast подключается в Фазе 1 (shared/ui/toast) — Фаза 1
    // перепишет этот колбек на toastStore.show (решение #15).
  });
});
