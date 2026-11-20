/// 1:1 port of `mediatracker-ui/src/shared/api/offlineMode.svelte.ts`.
/// $state → Riverpod; toggle — оптимистичное обновление с откатом при ошибке.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

/// Иммутабельный снимок стейта ($state-поля → одно состояние).
class OfflineModeState {
  final bool isOffline;
  final bool hasDatabases;
  final bool loading;

  const OfflineModeState({
    this.isOffline = false,
    this.hasDatabases = false,
    this.loading = false,
  });

  OfflineModeState copyWith({
    bool? isOffline,
    bool? hasDatabases,
    bool? loading,
  }) =>
      OfflineModeState(
        isOffline: isOffline ?? this.isOffline,
        hasDatabases: hasDatabases ?? this.hasDatabases,
        loading: loading ?? this.loading,
      );

  @override
  bool operator ==(Object other) =>
      other is OfflineModeState &&
      other.isOffline == isOffline &&
      other.hasDatabases == hasDatabases &&
      other.loading == loading;

  @override
  int get hashCode => Object.hash(isOffline, hasDatabases, loading);
}

class OfflineModeController extends Notifier<OfflineModeState> {
  @override
  OfflineModeState build() => const OfflineModeState();

  Future<void> init() async {
    state = state.copyWith(loading: true);
    try {
      final res = await ref.read(apiClientProvider).getOfflineMode();
      state = OfflineModeState(
        isOffline: res.offlineMode,
        hasDatabases: res.hasDatabases,
        loading: false,
      );
    } catch (_) {
      // Ignore background init failure.
      state = state.copyWith(loading: false);
    }
  }

  Future<void> toggle(bool enable) async {
    final prev = state.isOffline;
    state = state.copyWith(isOffline: enable);
    try {
      final serverValue = await ref.read(apiClientProvider).setOfflineMode(enable);
      state = state.copyWith(isOffline: serverValue);
    } catch (e) {
      state = state.copyWith(isOffline: prev);
      rethrow;
    }
  }

  void refresh(OfflineModeResponse data) {
    state = state.copyWith(
      isOffline: data.offlineMode,
      hasDatabases: data.hasDatabases,
    );
  }
}

final offlineModeProvider =
    NotifierProvider<OfflineModeController, OfflineModeState>(
        OfflineModeController.new);
