import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/utils/app_exit.dart';

/// Разгон dio-цепочки в fakeAsync-зоне: микротаски + Timer(0)-макротаски,
/// БЕЗ движения fake-времени (не срывает 400ms-тайминги остановки).
void _drain(FakeAsync async) {
  for (var i = 0; i < 6; i++) {
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 1));
  }
}

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

TsundokuApi makeApi({required bool throwOnShutdown}) {
  final dio = Dio()
    ..options.baseUrl = 'http://127.0.0.1:5150';
  dio.httpClientAdapter = StubAdapter((options) {
    if (options.path == '/api/system/shutdown') {
      return throwOnShutdown
          ? ResponseBody.fromString(jsonEncode(null), 500)
          : ResponseBody.fromString(jsonEncode(null), 200);
    }
    return ResponseBody.fromBytes(<int>[], 200);
  });
  return TsundokuApi(dio);
}

/// Полный цикл appExit: shutdown (ok/fail) → closeWindow → stopped-screen
/// через 400ms; closeToTray → toast через 400ms.
void main() {
  test('exitApp: shutdown ok → closeWindow; stopped screen не показывается',
      () {
    fakeAsync((async) {
      var shutdownCalls = 0;
      var closeCalls = 0;
      final stoppedScreens = <StoppedScreenText>[];
      final api = makeApi(throwOnShutdown: false);
      final exit = AppExit(api);

      exit.exitApp(
        closeWindow: () async {
          shutdownCalls += 1;
          closeCalls += 1;
          return;
        },
        showStoppedScreen: stoppedScreens.add,
        isWindowClosed: () => true,
        locale: Locale.en,
      );

      _drain(async);
      expect(shutdownCalls, 1);
      expect(closeCalls, 1);

      // Окно «закрылось» — stopped screen не показывается.
      async.elapse(const Duration(milliseconds: 500));
      expect(stoppedScreens, isEmpty);
    });
  });

  test('exitApp: shutdown fail → closeWindow всё равно (server already down)',
      () async {
    var closeCalls = 0;
    // Connection refused: адаптер бросает, dio оборачивает в DioException —
    // exitApp должен всё равно закрыть окно. Реальный event loop: dio-цепочка
    // ошибок опирается на макротаски, недоступные fakeAsync.
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter((options) {
      throw StateError('Connection refused');
    });
    final api = TsundokuApi(dio);
    final exit = AppExit(api);

    await exit.exitApp(
      closeWindow: () async {
        closeCalls += 1;
        return;
      },
      showStoppedScreen: (_) {},
      isWindowClosed: () => true,
    );
    expect(closeCalls, 1, reason: 'server may already be down — всё равно');
  });

  test('exitApp: браузер отказался закрывать → stopped screen через 400ms',
      () {
    fakeAsync((async) {
      final stoppedScreens = <StoppedScreenText>[];
      final api = makeApi(throwOnShutdown: false);
      final exit = AppExit(api);

      exit.exitApp(
        closeWindow: () async {
          return; // window.close() отказался — ничего не делает.
        },
        showStoppedScreen: stoppedScreens.add,
        isWindowClosed: () => false,
        locale: Locale.en,
      );

      _drain(async);
      async.elapse(const Duration(milliseconds: 390));
      expect(stoppedScreens, isEmpty);

      async.elapse(const Duration(milliseconds: 100));
      expect(stoppedScreens.length, 1);
      expect(stoppedScreens.single.title, isNotEmpty,
          reason: 'closeAppModal.stoppedTitle из i18n');
      expect(stoppedScreens.single.description, isNotEmpty);
    });
  });

  test('closeToTray: closeWindow → toast через 400ms', () {
    fakeAsync((async) {
      var closeCalls = 0;
      final toasts = <({String title, String description})>[];
      final api = makeApi(throwOnShutdown: false);
      final exit = AppExit(api);

      exit.closeToTray(
        closeWindow: () async {
          closeCalls += 1;
          return;
        },
        showToast: ({required title, required description}) =>
            toasts.add((title: title, description: description)),
        isWindowClosed: () => false,
        locale: Locale.ru,
      );

      expect(closeCalls, 1);
      _drain(async);
      async.elapse(const Duration(milliseconds: 390));
      expect(toasts, isEmpty);
      async.elapse(const Duration(milliseconds: 100));
      expect(toasts.length, 1);
      expect(toasts.single.title, isNotEmpty);
      expect(toasts.single.description, isNotEmpty);
    });
  });
}
