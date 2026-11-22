import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsundoku_flutter/features/settings/settings_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';

class _CapturingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  bool isOpen = true,
  bool embedded = false,
  SettingsTab initialTab = SettingsTab.sources,
  VoidCallback? onClose,
  VoidCallback? onImportCompleted,
}) {
  final dio = Dio()..httpClientAdapter = _CapturingAdapter();

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SettingsModal(
          isOpen: isOpen,
          onClose: onClose ?? () {},
          embedded: embedded,
          initialTab: initialTab,
          onImportCompleted: onImportCompleted,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSubject(
    WidgetTester tester, {
    bool isOpen = true,
    bool embedded = false,
    SettingsTab initialTab = SettingsTab.sources,
    VoidCallback? onClose,
    VoidCallback? onImportCompleted,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildSubject(
      isOpen: isOpen,
      embedded: embedded,
      initialTab: initialTab,
      onClose: onClose,
      onImportCompleted: onImportCompleted,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('hides when isOpen is false and embedded is false',
      (tester) async {
    await pumpSubject(tester, isOpen: false, embedded: false);

    expect(find.byType(SettingsModal), findsOneWidget);
    expect(find.byType(SettingsView), findsNothing);
  });

  testWidgets('renders modal header and SettingsView when isOpen is true',
      (tester) async {
    await pumpSubject(tester, isOpen: true, embedded: false);

    expect(find.text('Настройки'), findsWidgets);
    expect(find.byIcon(LucideIcons.settings), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('renders directly without modal chrome when embedded is true',
      (tester) async {
    await pumpSubject(tester, isOpen: false, embedded: true);

    // In embedded mode, close button is not present
    expect(find.byIcon(LucideIcons.x), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('passes initialTab to SettingsView', (tester) async {
    await pumpSubject(tester, isOpen: true, initialTab: SettingsTab.storage);

    expect(find.text('Хранилище'), findsWidgets);
  });

  testWidgets('clicking close button triggers onClose callback',
      (tester) async {
    bool closed = false;

    await pumpSubject(tester, isOpen: true, onClose: () => closed = true);

    final closeBtn = find.byIcon(LucideIcons.x);
    expect(closeBtn, findsOneWidget);

    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
