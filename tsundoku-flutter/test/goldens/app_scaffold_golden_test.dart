import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/main.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';

import 'golden_test_helper.dart';

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(<dynamic>[]), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-total-count': ['0'],
        });
  }

  @override
  void close({bool force = false}) {}
}

Dio _stubDio() {
  final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
  dio.httpClientAdapter = _StubAdapter();
  return dio;
}

class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
}

void main() {
  // Smoke-golden каркаса (Фаза 3: Sidebar/Header/Home живые). Эталон —
  // 1440×900, как Svelte-скриншоты из mediatracker-ui/checks/harness
  // (backstop desktop). dio — стаб (без сети: таймеры запроса не висят).
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tsundokuGoldenTest(
    'app_scaffold_placeholder',
    TsundokuApp(providerOverrides: <dynamic>[
      apiClientProvider.overrideWithValue(TsundokuApi(_stubDio())),
      jobsClientProvider.overrideWith(_NoopJobs.new),
    ]),
    postPumpFrames: 400, // 400×50ms = 20s > 15s safety-таймера networkActivity
  );
}
