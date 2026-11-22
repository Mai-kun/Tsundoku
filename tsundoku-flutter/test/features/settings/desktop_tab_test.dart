import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/settings/tabs/desktop_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/platform/platform.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _FakePlatformService implements PlatformService {
  bool windowClosed = false;

  @override
  Future<void> closeWindow() async {
    windowClosed = true;
  }

  @override
  Future<void> initWindow() async {}
  @override
  Future<void> copyText(String text) async {}
  @override
  Future<void> copyImagePng(Uint8List pngBytes) async {}
  @override
  Future<({Uint8List bytes, String mimeType})?> pasteImage() async => null;
  @override
  Future<void> saveFile({required String suggestedName, required Uint8List bytes}) async {}
  @override
  Future<({String name, Uint8List bytes})?> pickFile() async => null;
  @override
  Future<void> openExternalUrl(String url) async {}
}

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  Map<String, dynamic> appSettingsResponse = {
    'launchMode': 'app_window',
    'closeAction': 'minimize_to_tray',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/app')) {
      if (options.method == 'PUT') {
        final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
        appSettingsResponse = Map<String, dynamic>.from(body);
        return ResponseBody.fromString(
          jsonEncode(appSettingsResponse),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode(appSettingsResponse),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/system/shutdown')) {
      return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }

    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({_CapturingAdapter? adapter}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      home: const Scaffold(
        body: DesktopTab(),
      ),
    ),
  );
}

void main() {
  late _FakePlatformService fakePlatform;
  late PlatformService prevPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakePlatform = _FakePlatformService();
    prevPlatform = platformService;
    platformService = fakePlatform;
  });

  tearDown(() {
    platformService = prevPlatform;
  });

  testWidgets('DesktopTab renders all options and loads settings', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Режим отображения интерфейса'), findsOneWidget);
    expect(find.text('🖥️ Окно приложения'), findsOneWidget);
    expect(find.text('🌐 Вкладка браузера'), findsOneWidget);

    expect(find.text('Действие при закрытии окна'), findsOneWidget);
    expect(find.text('Сворачивать в трей'), findsOneWidget);
    expect(find.text('Полный выход'), findsOneWidget);

    expect(find.text('Запомненные подтверждения'), findsOneWidget);
    expect(find.text('Остановить Tsundoku (Выход)'), findsOneWidget);
  });

  testWidgets('DesktopTab changes launch mode and sends save request', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Tap Browser Tab
    await tester.tap(find.text('🌐 Вкладка браузера'));
    await tester.pumpAndSettle();

    final putReq = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/settings/app') && r.method == 'PUT',
    );
    final data = putReq.data is Map ? putReq.data as Map : jsonDecode(putReq.data.toString()) as Map;
    expect(data['launchMode'], 'browser_tab');
  });

  testWidgets('DesktopTab exit app calls shutdown and closeWindow', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Остановить Tsundoku (Выход)'));
    await tester.pumpAndSettle();

    expect(adapter.requests.any((r) => r.path.contains('/api/system/shutdown')), isTrue);
    expect(fakePlatform.windowClosed, isTrue);
  });
}
