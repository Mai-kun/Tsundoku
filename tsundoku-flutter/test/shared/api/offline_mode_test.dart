import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/offline_mode.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}


ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late StubAdapter adapter;
  late TsundokuApi api;
  late ProviderContainer container;
  late OfflineModeController ctrl;

  setUp(() {
    adapter = StubAdapter((options) {
      if (options.path == '/api/settings/offline-mode') {
        if (options.method == 'PUT') {
          // Stub-адаптер получает data до сериализации (Map), но быть готовым
          // и к строке (после transformer).
          final body = options.data is Map<String, dynamic>
              ? options.data as Map<String, dynamic>
              : jsonDecode(options.data as String) as Map<String, dynamic>;
          return jsonBody({'offlineMode': body['offlineMode']}, 200);
        }
        return jsonBody({
          'offlineMode': false,
          'hasDatabases': true,
        }, 200);}
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    ctrl = container.read(offlineModeProvider.notifier);
  });

  test('init: GET /api/settings/offline-mode → isOffline/hasDatabases',
      () async {
    await ctrl.init();
    final s = container.read(offlineModeProvider);
    expect(s.isOffline, isFalse);
    expect(s.hasDatabases, isTrue);
    expect(s.loading, isFalse);
  });

  test('init: фоновая ошибка игнорируется, loading=false', () async {
    adapter = StubAdapter(
        (options) => jsonBody(null, 500));
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    ctrl = container.read(offlineModeProvider.notifier);

    await ctrl.init();
    expect(container.read(offlineModeProvider).loading, isFalse);
    expect(container.read(offlineModeProvider).isOffline, isFalse);
  });

  test('toggle: оптимистичное включение → серверное значение', () async {
    await ctrl.init();
    await ctrl.toggle(true);
    expect(container.read(offlineModeProvider).isOffline, isTrue);
    // PUT с {offlineMode: true}:
    final put = adapter.seen
        .where((o) => o.method == 'PUT' && o.path == '/api/settings/offline-mode')
        .single;
    expect(put.data, {'offlineMode': true});
  });

  test('toggle: ошибка сервера → откат к предыдущему значению', () async {
    await ctrl.init();
    expect(container.read(offlineModeProvider).isOffline, isFalse);

    adapter = StubAdapter(
        (options) => jsonBody(null, 500));
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final broken = container.read(offlineModeProvider.notifier);

    await expectLater(broken.toggle(true), throwsA(isA<ApiError>()));
    expect(container.read(offlineModeProvider).isOffline, isFalse,
        reason: 'откат оптимистичного апдейта при ошибке (1-в-1 catch)');
  });

  test('toggle: сервер вернул иное значение → принимается серверное', () async {
    await ctrl.init();
    adapter = StubAdapter(
        (options) => jsonBody({'offlineMode': true, 'extra': 1}, 200));
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final other = container.read(offlineModeProvider.notifier);

    await other.toggle(true);
    expect(container.read(offlineModeProvider).isOffline, isTrue);
  });

  test('refresh: внешние данные (SSE/поллинг) обновляют стейт', () {
    ctrl.refresh(const OfflineModeResponse(
      offlineMode: true,
      hasDatabases: false,
    ));
    final s = container.read(offlineModeProvider);
    expect(s.isOffline, isTrue);
    expect(s.hasDatabases, isFalse);
  });

  test('дефолтное состояние: всё false', () {
    final s = container.read(offlineModeProvider);
    expect(s.isOffline, isFalse);
    expect(s.hasDatabases, isFalse);
    expect(s.loading, isFalse);
  });
}
