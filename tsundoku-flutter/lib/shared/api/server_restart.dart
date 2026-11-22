/// 1:1 port of `mediatracker-ui/src/shared/api/serverRestart.svelte.ts`.
///
/// $state → Riverpod (serverRestartProvider); fetch+AbortController → dio с
/// per-probe таймаутами; дедлайны — параметры с дефолтами 1-в-1
/// (тестируемость; решение #10). Стейт мутится через колбек — провайдер
/// приложения подключает его в Фазе 5 (SettingsView).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

export 'package:meta/meta.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

/// True while the backend is restarting after a storage-mode switch or an
/// update apply. The window survives the restart by design, so background
/// refreshes hit a short window of network errors: those failures are
/// expected and must not surface as error toasts.
class ServerRestartController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Устанавливает статус перезапуска сервера.
  void setRestarting(bool value) => state = value;

  /// Тест-хук (аналог мутации $state из Svelte).
  @visibleForTesting
  void setForTest(bool value) => state = value;
}

final serverRestartProvider =
    NotifierProvider<ServerRestartController, bool>(ServerRestartController.new);

String _probeUrl() =>
    '/api/settings/storage?t=${DateTime.now().millisecondsSinceEpoch}';

Future<bool> _probe(TsundokuApi api, Duration timeout) async {
  try {
    final response = await api.dio.fetch<dynamic>(RequestOptions(
      path: _probeUrl(),
      method: 'GET',
      // cache: "no-store" — Dio по умолчанию не кэширует.
      sendTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
    ));
    final code = response.statusCode ?? 0;
    return code >= 200 && code < 300;
  } catch (_) {
    return false;
  }
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// Survives the backend restart end-to-end and only returns control once the
/// NEW process is already responding. Two-phase scheme — otherwise there is a
/// race: the first successful poll could catch the dying old server, the page
/// would reload too early and collect errors.
///
/// Phase 1: wait for the current server to actually go down (connection
/// refused). If it never goes down within the limit — no restart was
/// scheduled, reload right away.
/// Phase 2: wait for the new process to start responding.
///
/// The calling modal keeps its loader (saving/isSavingStorage) the whole time;
/// the reload happens only after this returns — the page starts on a live
/// server, with no errors.
///
/// [onRestartingChange] — мост в `serverRestartProvider` (в приложении
/// передаётся из виджета через ref, в тестах — счётчик).
Future<void> waitForBackendRestart(
  TsundokuApi api,
  bool restartScheduled, {
  void Function(bool isRestarting)? onRestartingChange,
  Duration downWindow = const Duration(seconds: 5),
  Duration upWindow = const Duration(seconds: 20),
  Duration downProbeTimeout = const Duration(milliseconds: 400),
  Duration upProbeTimeout = const Duration(milliseconds: 800),
  Duration pollInterval = const Duration(milliseconds: 150),
}) async {
  try {
    onRestartingChange?.call(true);
    if (!restartScheduled) {
      return;
    }

    // Phase 1: the current server must go down (graceful shutdown fits in
    // ~2 s).
    final downDeadline = DateTime.now().add(downWindow);
    var wentDown = false;
    while (DateTime.now().isBefore(downDeadline)) {
      if (!await _probe(api, downProbeTimeout)) {
        wentDown = true;
        break;
      }
      await _sleep(pollInterval);
    }
    if (!wentDown) {
      // No restart happened (or it already finished before the first poll).
      return;
    }

    // Phase 2: the new process comes up and starts responding.
    final upDeadline = DateTime.now().add(upWindow);
    while (DateTime.now().isBefore(upDeadline)) {
      if (await _probe(api, upProbeTimeout)) {
        return;
      }
      await _sleep(pollInterval);
    }
    // The server never came up within 20 s: reload anyway and let the UI show
    // its own state.
  } finally {
    onRestartingChange?.call(false);
  }
}
