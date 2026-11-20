/// 1:1 port of `mediatracker-ui/src/shared/api/networkActivity.svelte.ts`.
///
/// Svelte-5 `$state`/`$derived` → Riverpod [Notifier] + derived-провайдер.
/// Таймер — `dart:async` (не платформенный API, фасад не требуется).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Счётчик активных HTTP-запросов: единственный глобальный индикатор
/// сетевой активности (спиннеры Header/BackgroundJobsModal читают [isLoading]).
class NetworkActivityController extends Notifier<int> {
  /// Safety fallback: network activity indicator never stays active longer
  /// than 15s.
  static const Duration _safetyTimeout = Duration(milliseconds: 15000);

  Timer? _safetyTimer;

  @override
  int build() => 0;

  void begin() {
    state = (state < 0 ? 0 : state) + 1;
    _armSafetyTimer();
  }

  void end() {
    state = state > 0 ? state - 1 : 0;
    if (state == 0 && _safetyTimer != null) {
      _safetyTimer!.cancel();
      _safetyTimer = null;
    }
  }

  void reset() {
    state = 0;
    if (_safetyTimer != null) {
      _safetyTimer!.cancel();
      _safetyTimer = null;
    }
  }

  void _armSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = Timer(_safetyTimeout, reset);
  }
}

/// Глобальный singleton-провайдер (аналог `export const networkActivity`).
final networkActivityProvider =
    NotifierProvider<NetworkActivityController, int>(
  NetworkActivityController.new,
);

/// `$derived(this.activeRequests > 0)`.
final networkActivityLoadingProvider = Provider<bool>((ref) {
  return ref.watch(networkActivityProvider) > 0;
});
