/// 1:1 port of `mediatracker-ui/src/features/update-progress/optimisticProgress.svelte.ts`.
///
/// Single source of truth for progress the user has stepped but the server has
/// not confirmed yet. Cards and the detail page both write here, so a value
/// stepped on a card survives the trip into the detail screen (and back) even
/// though the underlying items are separate objects and the debounce has not
/// fired. SvelteMap → Riverpod [Notifier] с Map-стейтом.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../shared/types/models.dart';

@immutable
class OptimisticEntry {
  final int value;
  final DateTime at;

  const OptimisticEntry({required this.value, required this.at});
}

@immutable
class OptimisticProgressState {
  /// The debounce sends after 3s; a network round-trip cannot outlive this
  /// much more. Entries older than the TTL are dropped on read — a keepalive
  /// flush on tab close never reports back, and without a cap a stale
  /// override would freeze the UI on a value the server may have rejected.
  static const Duration entryTtl = Duration(milliseconds: 15000);

  final Map<String, OptimisticEntry> entries;

  const OptimisticProgressState({this.entries = const <String, OptimisticEntry>{}});

  OptimisticProgressState copyWith({Map<String, OptimisticEntry>? entries}) =>
      OptimisticProgressState(entries: entries ?? this.entries);
}

class OptimisticProgressController extends Notifier<OptimisticProgressState> {
  @override
  OptimisticProgressState build() => const OptimisticProgressState();

  /// Records (or updates, while the debounce keeps resetting) the local value.
  void apply(String id, int value) {
    applyAt(id, value, DateTime.now());
  }

  /// Тест-хук: apply с явным моментом записи (для TTL-проверок).
  @visibleForTesting
  void applyAt(String id, int value, DateTime at) {
    final next = <String, OptimisticEntry>{...state.entries};
    next[id] = OptimisticEntry(value: value, at: at);
    state = state.copyWith(entries: next);
  }

  /// Server confirmed `confirmed`: drop the override, or re-base it if a newer
  /// step landed while the request was in flight.
  void resolve(String id, int confirmed) {
    final entry = state.entries[id];
    if (entry == null) return;
    final next = <String, OptimisticEntry>{...state.entries};
    if (entry.value == confirmed) {
      next.remove(id);
    } else {
      next[id] = OptimisticEntry(value: entry.value, at: DateTime.now());
    }
    state = state.copyWith(entries: next);
  }

  /// The request failed: the optimistic value has nothing backing it anymore.
  void clear(String id) {
    if (!state.entries.containsKey(id)) return;
    final next = <String, OptimisticEntry>{...state.entries};
    next.remove(id);
    state = state.copyWith(entries: next);
  }

  int? peek(String id) {
    final entry = state.entries[id];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > OptimisticProgressState.entryTtl) {
      clear(id);
      return null;
    }
    return entry.value;
  }

  /// Anti-rollback merge for incoming DB data. While a local step is pending
  /// (debounce ticking or request in flight), refetched data must not drag the
  /// visible number back to the stale server value in either direction, so the
  /// optimistic value is held until the server reports the same number — which
  /// also clears the override, since the server has caught up.
  int reconcile(String id, int incoming) {
    final optimistic = peek(id);
    if (optimistic == null) return incoming;
    if (optimistic == incoming) {
      clear(id);
      return incoming;
    }
    return optimistic;
  }

  /// Bulk [reconcile] for a refetched list before it replaces the rendered
  /// items (`allItems = found`): any item with a live optimistic step keeps
  /// that step on the incoming object instead of snapping back to the server
  /// value. Items the server has caught up with drop their override here, so
  /// the entries never outlive the confirmation.
  List<MediaItem> reconcileListProgress(List<MediaItem> items) {
    return [
      for (final item in items)
        if (!state.entries.containsKey(item.id))
          item
        else
          _reconciledItem(item),
    ];
  }

  MediaItem _reconciledItem(MediaItem item) {
    final current = readCardProgress(item);
    final reconciled = reconcile(item.id, current);
    if (reconciled == current) return item;
    return writeCardProgress(item, reconciled);
  }
}

final optimisticProgressProvider = NotifierProvider<OptimisticProgressController,
    OptimisticProgressState>(OptimisticProgressController.new);

/// Процедурные аналоги экспортируемых функций Svelte-модуля.
void applyOptimisticProgress(Ref ref, String id, int value) =>
    ref.read(optimisticProgressProvider.notifier).apply(id, value);

void resolveOptimisticProgress(Ref ref, String id, int confirmed) =>
    ref.read(optimisticProgressProvider.notifier).resolve(id, confirmed);

void clearOptimisticProgress(Ref ref, String id) =>
    ref.read(optimisticProgressProvider.notifier).clear(id);

int? peekOptimisticProgress(ProviderContainer ref, String id) =>
    ref.read(optimisticProgressProvider.notifier).peek(id);

int reconcileProgress(ProviderContainer ref, String id, int incoming) =>
    ref.read(optimisticProgressProvider.notifier).reconcile(id, incoming);

List<MediaItem> reconcileListProgress(ProviderContainer ref, List<MediaItem> items) =>
    ref.read(optimisticProgressProvider.notifier).reconcileListProgress(items);
