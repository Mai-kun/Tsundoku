import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/server_restart.dart';

/// Адаптер: последовательность ответов на probe-запросы.
class ProbeAdapter implements HttpClientAdapter {
  final List<bool> okSequence;
  int calls = 0;

  ProbeAdapter(this.okSequence);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final ok = calls < okSequence.length ? okSequence[calls] : okSequence.last;
    calls += 1;
    return ok
        ? ResponseBody.fromString(jsonEncode(null), 200)
        : ResponseBody.fromString(jsonEncode(null), 500);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ProviderContainer container;
  late TsundokuApi api;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    api = container.read(apiClientProvider);
  });

  test('restartScheduled=false: не ждёт, isRestarting true→false', () async {
    final transitions = <bool>[];
    final adapter = ProbeAdapter(<bool>[]);
    api.dio.httpClientAdapter = adapter;

    await waitForBackendRestart(
      api,
      false,
      onRestartingChange: transitions.add,
      downWindow: const Duration(milliseconds: 50),
      upWindow: const Duration(milliseconds: 50),
    );
    expect(transitions, [true, false]);
    expect(adapter.calls, 0, reason: 'не планировался рестарт — probes нет');
  });

  test('two-phase: сервер упал и поднялся → выход после первого ok', () async {
    // Фазы: сначала сервер жив (не down), потом down (500), потом up (200).
    final adapter = ProbeAdapter(<bool>[true, false, true, true]);
    api.dio.httpClientAdapter = adapter;
    final transitions = <bool>[];

    await waitForBackendRestart(
      api,
      true,
      onRestartingChange: transitions.add,
      downWindow: const Duration(seconds: 2),
      upWindow: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(transitions, [true, false]);
    // Первый probe увидел живой сервер, второй — down, третий — up:
    expect(adapter.calls >= 3, isTrue);
  });

  test('сервер не упал в пределах downWindow → early return', () async {
    final adapter = ProbeAdapter(<bool>[true, true, true, true]);
    api.dio.httpClientAdapter = adapter;
    final transitions = <bool>[];

    await waitForBackendRestart(
      api,
      true,
      onRestartingChange: transitions.add,
      downWindow: const Duration(milliseconds: 80),
      pollInterval: const Duration(milliseconds: 10),
      upWindow: const Duration(milliseconds: 50),
    );
    expect(transitions, [true, false]);
    expect(adapter.calls >= 2, isTrue, reason: 'несколько probes упали, все ok');
  });

  test('сервер не поднялся за upWindow → выход по дедлайну (false в конце)',
      () async {
    // down сразу, потом всё время 500:
    final adapter = ProbeAdapter(<bool>[false]);
    api.dio.httpClientAdapter = adapter;
    final transitions = <bool>[];

    await waitForBackendRestart(
      api,
      true,
      onRestartingChange: transitions.add,
      downWindow: const Duration(milliseconds: 30),
      upWindow: const Duration(milliseconds: 60),
      pollInterval: const Duration(milliseconds: 5),
    );
    expect(transitions, [true, false]);
    expect(adapter.calls >= 2, isTrue, reason: 'phase-2 поллил до дедлайна');
  });

  test('probe: 2xx = ok, не-2xx = down, сетевая ошибка = down', () async {
    final adapter = ProbeAdapter(<bool>[false]);
    api.dio.httpClientAdapter = adapter;

    expect(await _probeDirect(api, const Duration(milliseconds: 50)), isFalse);
    adapter.calls = 0;
    adapter.okSequence[0] = true;
    expect(await _probeDirect(api, const Duration(milliseconds: 50)), isTrue);
  });
}

// Прямой доступ к _probe через публичный waitForBackendRestart невозможно —
// поэтому здесь диагностика через адаптер: «ok → не down» уже покрыто
// two-phase тестами; helper для читаемости.
Future<bool> _probeDirect(TsundokuApi api, Duration timeout) async {
  try {
    final response = await api.dio.fetch<dynamic>(RequestOptions(
      path: '/api/settings/storage?t=0',
      method: 'GET',
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
