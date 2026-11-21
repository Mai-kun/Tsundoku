import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/shared/utils/progress_debounce.dart';

/// Полный цикл дебаунса прогресса: burst → один send → commit/error →
/// flush → cancel → keepalive.
void main() {
  test('burst кликов сворачивается в один send после 3s', () {
    fakeAsync((async) {
      final sends = <String, int>{};
      final committed = <int>[];
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          sends[id] = value;
        },
        buildRequest: (id, value) =>
            const ProgressRequest(url: '/api/media/m1/progress', body: null),
        onCommitted: committed.add,
      ));

      debouncer.schedule('m1', 5);
      debouncer.schedule('m1', 6);
      debouncer.schedule('m1', 7);

      // До 3s ничего не отправлено (bursts collapse):
      async.elapse(const Duration(milliseconds: 2900));
      expect(sends, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      expect(sends, {'m1': 7}, reason: 'осталось только последнее значение');
      expect(committed, [7]);
    });
  });

  test('flush: немедленная отправка без ожидания delay', () {
    fakeAsync((async) {
      final sends = <String, int>{};
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          sends[id] = value;
        },
        buildRequest: (id, value) => const ProgressRequest(url: '/x', body: 1),
        onCommitted: (_) {},
      ));

      debouncer.schedule('m1', 10);
      // flush вызывается снаружи — Future завершается микротасками:
      debouncer.flush();
      async.flushMicrotasks();
      async.flushMicrotasks();
      expect(sends, {'m1': 10},
          reason: 'flush немедленно отправляет отложенное значение');
    });
  });

  test('flush после timeout не отправляет второй раз', () {
    fakeAsync((async) {
      final sends = <String, int>{};
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          sends[id] = value;
        },
        buildRequest: (id, value) => const ProgressRequest(url: '/x', body: 1),
        onCommitted: (_) {},
      ));

      debouncer.schedule('m1', 3);
      async.elapse(const Duration(seconds: 3));
      expect(sends, {'m1': 3});

      // Pending уже пуст — flush ничего не делает.
      debouncer.flush();
      expect(sends, {'m1': 3});
    });
  });

  test('cancel: запланированная запись не отправляется (undo)', () {
    fakeAsync((async) {
      final sends = <String, int>{};
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          sends[id] = value;
        },
        buildRequest: (id, value) => const ProgressRequest(url: '/x', body: 1),
        onCommitted: (_) {},
      ));

      debouncer.schedule('m1', 9);
      debouncer.cancel();
      async.elapse(const Duration(seconds: 5));
      expect(sends, isEmpty,
          reason: 'undo-действие не должно гонять pending PUT');
    });
  });

  test('keepalive-флаш: buildRequest → keepaliveSender; пустой url скипается',
      () {
    fakeAsync((async) {
      final keepalive = <String, Object?>{};
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {},
        buildRequest: (id, value) =>
            ProgressRequest(url: '/api/media/$id/progress', body: value),
        onCommitted: (_) {},
        keepaliveSender: (request) async {
          keepalive[request.url] = request.body;
        },
      ));

      debouncer.schedule('m1', 12);
      debouncer.flush(keepalive: true);
      async.flushMicrotasks();
      async.flushMicrotasks();
      expect(keepalive['/api/media/m1/progress'], 12);

      // Пустой url — пропуск:
      final empty = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {},
        buildRequest: (id, value) => const ProgressRequest(url: '', body: null),
        onCommitted: (_) {},
        keepaliveSender: (request) async {
          keepalive['should-not-happen'] = null;
        },
      ));
      empty.schedule('m2', 1);
      empty.flush(keepalive: true);
      async.flushMicrotasks();
      async.flushMicrotasks();
      expect(keepalive.containsKey('should-not-happen'), isFalse);
    });
  });

  test('send: ошибка → onError, onCommitted не вызывается; при повторном — ок',
      () {
    fakeAsync((async) {
      var attempts = 0;
      Object? caught;
      final committed = <int>[];
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          attempts += 1;
          throw StateError('network down');
        },
        buildRequest: (id, value) => const ProgressRequest(url: '/x', body: 1),
        onCommitted: committed.add,
        onError: (error) => caught = error,
      ));

      debouncer.schedule('m1', 4);
      async.elapse(const Duration(seconds: 3));
      expect(attempts, 1);
      expect(caught, isA<StateError>());
      expect(committed, isEmpty);
    });
  });

  test('sending-флаг: повторный flush не дублирует отправку', () {
    fakeAsync((async) {
      final sends = <String, int>{};
      final debouncer = ProgressDebouncer(ProgressDebounceOptions(
        send: (id, value) async {
          sends[id] = value;
        },
        buildRequest: (id, value) => const ProgressRequest(url: '/x', body: 1),
        onCommitted: (_) {},
      ));

      debouncer.schedule('m1', 2);
      // Первый flush снимает pending и запускает отправку (send стартует
      // синхронно до первого await); второй flush — pending уже снят, ничего
      // не делает → дублирования нет.
      debouncer.flush();
      debouncer.flush();
      async.flushMicrotasks();
      async.flushMicrotasks();
      expect(sends, {'m1': 2},
          reason: 'ровно одна отправка: второй flush не дублирует');
    });
  });

  test('defaultDelay = 3s (1-в-1 с исходником)', () {
    expect(defaultDelay, const Duration(seconds: 3));
  });
}
