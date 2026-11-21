/// 1:1 port of `mediatracker-ui/src/shared/utils/progressDebounce.ts`.
///
/// Дебаунс оптимистичного прогресса: серия быстрых кликов (+/−) сворачивается
/// в один запрос через [defaultDelay], плюс принудительный flush и
/// keepalive-отправка при скрытии/закрытии (в Flutter — через AppLifecycle
/// в Фазе 3; решение #13).
library;

import 'dart:async';

typedef ProgressSender = Future<void> Function(String id, int value);

class ProgressRequest {
  final String url;
  final Object? body;

  const ProgressRequest({required this.url, required this.body});
}

class ProgressDebounceOptions {
  final ProgressSender send;
  final ProgressRequest Function(String id, int value) buildRequest;
  final void Function(int value) onCommitted;
  final void Function(Object error)? onError;

  /// Отправка keepalive-запроса (в TS — голый fetch c keepalive: true,
  /// обходящий контроллер; в Flutter — dio-инъекция).
  final Future<void> Function(ProgressRequest request)? keepaliveSender;

  final Duration? delay;

  const ProgressDebounceOptions({
    required this.send,
    required this.buildRequest,
    required this.onCommitted,
    this.onError,
    this.keepaliveSender,
    this.delay,
  });
}

class _PendingProgress {
  final String id;
  final int value;
  final ProgressRequest Function(String id, int value) buildRequest;

  const _PendingProgress({
    required this.id,
    required this.value,
    required this.buildRequest,
  });
}

/// 3s: quiet clicks (+ / - in a burst) collapse into one request, and the
/// keepalive flush on tab hide/close still guarantees delivery.
const Duration defaultDelay = Duration(seconds: 3);

/// Инстанс-ключ из TS (Symbol) в Dart-порте не нужен: каждый
/// [ProgressDebouncer] держит свои таймеры и pending-задачу.
class ProgressDebouncer {
  final ProgressDebounceOptions options;
  final Duration delay;
  Timer? _timer;
  _PendingProgress? _pending;
  bool _sending = false;

  ProgressDebouncer(this.options) : delay = options.delay ?? defaultDelay;

  void _clearPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  Future<void> _sendKeepalive(_PendingProgress task) async {
    final request = task.buildRequest(task.id, task.value);
    // A builder that cannot represent the value synchronously (no data in
    // memory) reports an empty URL; skipping beats firing a broken request.
    if (request.url.isEmpty) return;
    try {
      await options.keepaliveSender?.call(request);
    } catch (_) {
      // keepalive — fire-and-forget (как .catch(() => {}) в исходнике).
    }
  }

  Future<void> _commit(_PendingProgress task) async {
    if (_sending) return;
    _sending = true;
    try {
      await options.send(task.id, task.value);
      options.onCommitted(task.value);
    } catch (error) {
      options.onError?.call(error);
    } finally {
      _sending = false;
    }
  }

  /// Ставит дебаунс-задачу; предыдущая (если была) отменяется.
  void schedule(String id, int value) {
    _timer?.cancel();
    _pending = _PendingProgress(
      id: id,
      value: value,
      buildRequest: options.buildRequest,
    );
    _timer = Timer(delay, () {
      final pending = _pending;
      _clearPending();
      if (pending != null) {
        _commit(pending);
      }
    });
  }

  /// Немедленная отправка отложенного значения.
  Future<void> flush({bool keepalive = false}) async {
    final task = _pending;
    _clearPending();
    if (task == null) return;

    if (keepalive) {
      await _sendKeepalive(task);
      return;
    }
    await _commit(task);
  }

  /// Drops a scheduled write without sending it — e.g. an undo action that
  /// must not race the still-pending optimistic progress PUT.
  void cancel() {
    _clearPending();
  }
}

/// `createProgressDebounce(options)` — тот же API именованным конструктором.
ProgressDebouncer createProgressDebounce(ProgressDebounceOptions options) =>
    ProgressDebouncer(options);
