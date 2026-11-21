/// 1:1 port of `mediatracker-ui/src/features/update-progress/progressController.svelte.ts`.
///
/// $state-поля → поля контроллера + Riverpod-инъекция (оптимистичный реестр).
/// TS-мутация item → copyWithFields (решение #14): колбеки получают копии.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../shared/api/api.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import '../../shared/utils/progress_debounce.dart';
import '../change-status/status_controller.dart' show OnStatusChanged;
import '../prefetch-details/media_detail_prefetch.dart';
import 'optimistic_progress.dart';
import 'status_promotion_toast.dart';

class CardProgressOptions {
  /// Accessor, not a value: the item prop is replaced when the grid refetches.
  final MediaItem Function() getItem;

  final Future<void> Function(String id, int currentProgress)? Function()
      getOnProgress;
  final void Function() Function() getOnProgressCommitted;
  final OnStatusChanged? Function()? getOnStatusChange;
  /// Инъекция shower для интерактивного тоста promotion (решение #15).
  final StatusPromotionToastShower showPromotionToast;
  final ProviderContainer ref;
  /// Тест-инъекция: сокращённый дебаунс.
  final Duration? delayOverride;
  /// UI-хук перерисовки: Svelte-карточка реактивна на $state-поля
  /// (value/error); Dart-контроллер не-реактивный — карточка подписывается
  /// через этот колбек (решение #36).
  final void Function()? onChange;

  const CardProgressOptions({
    required this.getItem,
    required this.getOnProgress,
    required this.getOnProgressCommitted,
    required this.showPromotionToast,
    required this.ref,
    this.getOnStatusChange,
    this.delayOverride,
    this.onChange,
  });
}

class CardProgressState {
  int _currentProgress;
  int _committedProgress;
  int? _pendingSnapshot;
  Object? _error;
  /// True while a scheduled step is newer than the tracked item's progress
  /// field.
  bool _hasOptimisticProgress = false;
  MediaItem? _trackedItem;
  late final ProgressDebouncer _debounce;
  final List<void Function()> _changeListeners = <void Function()>[];
  final CardProgressOptions options;

  /// Подписка карточки (setState) на UI-релевантные мутации value/error.
  void addChangeListener(void Function() listener) =>
      _changeListeners.add(listener);
  void removeChangeListener(void Function() listener) =>
      _changeListeners.remove(listener);
  void _notifyChanged() {
    for (final listener in List.of(_changeListeners)) {
      listener();
    }
  }

  CardProgressState(this.options) : _currentProgress = 0, _committedProgress = 0 {
    _currentProgress = readCardProgress(options.getItem());
    _committedProgress = _currentProgress;
    _debounce = ProgressDebouncer(ProgressDebounceOptions(
      // Замыкания на this: состояние контроллера доступно в момент вызова.
      delay: options.delayOverride,
      send: (id, value) async {
        final sender = options.getOnProgress();
        if (sender != null) {
          await sender(id, value);
        }
      },
      buildRequest: (id, value) => ProgressRequest(
          url: '/api/media/$id/progress', body: {'currentProgress': value}),
      onCommitted: (value) {
        _committedProgress = value;
        _hasOptimisticProgress = false;
        options.ref
            .read(optimisticProgressProvider.notifier)
            .resolve(_trackedItem?.id ?? '', value);
        if (_currentProgress == value) {
          options.getOnProgressCommitted()();
        }
        _notifyChanged();
      },
      onError: (failure) {
        _currentProgress = _pendingSnapshot ?? _committedProgress;
        _committedProgress = _currentProgress;
        _pendingSnapshot = null;
        _hasOptimisticProgress = false;
        options.ref
            .read(optimisticProgressProvider.notifier)
            .clear(_trackedItem?.id ?? '');
        _error = failure;
        _notifyChanged();
      },
    ));
  }

  /// Аналог $effect(getItem): an in-flight optimistic step is newer than the
  /// replaced item's progress field (e.g. the status flip swaps the object
  /// mid-step): keep it instead of snapping back to the stale snapshot.
  void onItemReplaced(MediaItem item) {
    if (item != _trackedItem) {
      _trackedItem = item;
      if (!_hasOptimisticProgress) {
        _currentProgress = options.ref
            .read(optimisticProgressProvider.notifier)
            .reconcile(item.id, readCardProgress(item));
        _committedProgress = readCardProgress(item);
      }
      _pendingSnapshot = null;
      _notifyChanged();
    }
  }

  /// Аналог $effect(() => () => debounce.flush(true)) — при уничтожении
  /// контроллера.
  void dispose() {
    _debounce.flush(keepalive: true);
  }

  int get value => _currentProgress;
  Object? get error => _error;

  /// Undo: the pending progress=1 write is cancelled, then progress 0 and the
  /// previous status are persisted — exactly what the server stores after an
  /// F5.
  void _revertPromotion(MediaItem target, MediaStatus previousStatus) {
    _debounce.cancel();
    options.ref.read(optimisticProgressProvider.notifier).clear(target.id);
    _pendingSnapshot = null;
    _currentProgress = 0;
    _committedProgress = 0;
    _hasOptimisticProgress = false;
    _trackedItem = writeCardProgress(target, 0);
    updateCachedDetailProgressRef(options.ref, target.id, 0);
    final api = options.ref.read(apiClientProvider);
    api.setProgress(target.id, 0).then((_) {
      return api.updateStatus(target.id, previousStatus);
    }).catchError((Object failure) {});
    _notifyChanged();
  }

  /// Keep-status: the progress stays at its new value (persisted explicitly,
  /// since the debounced write is cancelled) and the previous status is
  /// restored.
  void _keepProgressOnly(
      MediaItem target, MediaStatus previousStatus, int value) {
    _debounce.cancel();
    _pendingSnapshot = null;
    _committedProgress = value;
    _hasOptimisticProgress = false;
    _trackedItem = target.copyWithFields(status: previousStatus);
    final api = options.ref.read(apiClientProvider);
    api.setProgress(target.id, value).then((_) {
      options.ref
          .read(optimisticProgressProvider.notifier)
          .resolve(target.id, value);
    }).catchError((Object failure) {});
    api.updateStatus(target.id, previousStatus).catchError((Object failure) {});
    _notifyChanged();
  }

  void step(int delta) {
    final item = options.getItem();
    if (options.getOnProgress() == null || !supportsProgressStepper(item)) return;

    final next = nextCardProgress(item, _currentProgress, delta);
    if (next == _currentProgress) return;

    // Write through to the item BEFORE the status flip below: the flip's
    // parent map spreads this object into a new one, and the spread must
    // carry the stepped progress.
    final steppedItem = writeCardProgress(item, next);

    // Rule 1 of the status contract: only the exact 0 → 1 step implies the
    // title started and flips to InProgress. Every other step keeps the badge
    // as it is (dropped stays dropped, on hold stays on hold), mirroring the
    // server's single stored rule so an F5 never shows a different status.
    // The flip is announced by an interactive toast: OK accepts, Undo fully
    // reverts (progress 0 + previous status), keep-status keeps the progress
    // and restores the previous status.
    if (shouldPromoteToInProgress(_currentProgress, next) &&
        item.status != MediaStatus.inProgress) {
      final previousStatus = item.status;
      final flipped = transitionToInProgress(
        item,
        options.getOnStatusChange?.call(),
        updateStatus: (id, status) =>
            options.ref.read(apiClientProvider).updateStatus(id, status),
      );
      notifyAutoInProgress(flipped, previousStatus,
          show: options.showPromotionToast,
          handlers: StatusPromotionHandlers(
            undo: () => _revertPromotion(flipped, previousStatus),
            keepStatus: () => _keepProgressOnly(flipped, previousStatus, next),
          ));
      _trackedItem = flipped;
    } else {
      _trackedItem = steppedItem;
    }

    _pendingSnapshot ??= _committedProgress;

    _currentProgress = next;
    _hasOptimisticProgress = true;
    _error = null;
    options.ref.read(optimisticProgressProvider.notifier).apply(item.id, next);
    // The cached detail payload (hover prefetch) would otherwise open the
    // detail screen with the pre-step number and snap only after refetch.
    updateCachedDetailProgressRef(options.ref, item.id, next);
    _debounce.schedule(item.id, next);
    _notifyChanged();
  }
}

/// Оптимистично переводит item в InProgress и сохраняет смену статуса.
/// Возвращает обновлённую копию (решение #14).
MediaItem transitionToInProgress(
  MediaItem item,
  OnStatusChanged? onStatusChange, {
  required Future<void> Function(String id, MediaStatus status) updateStatus,
}) {
  if (item.status == MediaStatus.inProgress) return item;
  final next = item.copyWithFields(status: MediaStatus.inProgress);
  onStatusChange?.call(next, MediaStatus.inProgress);
  updateStatus(item.id, MediaStatus.inProgress).catchError((Object failure) {});
  return next;
}
