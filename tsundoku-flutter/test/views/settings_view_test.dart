import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/settings/tabs/appearance_tab.dart';
import 'package:tsundoku_flutter/features/settings/tabs/backup_tab.dart';
import 'package:tsundoku_flutter/features/settings/tabs/search_tab.dart';
import 'package:tsundoku_flutter/features/settings/tabs/sources_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';

class _CapturingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;

    if (path.contains('/api/settings/sources')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (path.contains('/api/settings/offline-databases')) {
      return ResponseBody.fromString(
        jsonEncode({
          'isEnabled': false,
          'databases': [],
          'lastScannedAt': null,
          'isIndexing': false,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/settings/proxy')) {
      return ResponseBody.fromString(
        jsonEncode({
          'enabled': false,
          'proxyUrl': '',
          'hasPassword': false,
          'username': null,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/settings/category-order')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (path.contains('/api/settings/navigation-categories')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (path.contains('/api/settings/source-priority')) {
      return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }

    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildTestSubject({
  SettingsTab initialTab = SettingsTab.sources,
  VoidCallback? onImportCompleted,
  ValueChanged<String>? onNavigateToList,
  void Function(String sourceId, String? type)? onTestSearch,
  Widget Function(
    BuildContext context,
    SettingsTab activeTab,
    VoidCallback onImportCompleted,
    ValueChanged<String>? onNavigateToList,
    void Function(String sourceId, String? type)? onTestSearch,
  )? panelBuilder,
}) {
  final dio = Dio()..httpClientAdapter = _CapturingAdapter();

  return ProviderScope(
    overrides: [
      tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: SettingsView(
          initialTab: initialTab,
          onImportCompleted: onImportCompleted,
          onNavigateToList: onNavigateToList,
          onTestSearch: onTestSearch,
          panelBuilder: panelBuilder,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders default initial tab (sources) in desktop mode',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject());
    await tester.pumpAndSettle();

    // Sidebar navigation contains tabs
    expect(find.text('Источники'), findsWidgets);
    expect(find.text('Поиск'), findsOneWidget);
    expect(find.text('Резервная копия'), findsOneWidget);
    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Хранилище'), findsOneWidget);

    // Section content is real SourcesTab
    expect(find.byType(SourcesTab), findsOneWidget);
  });

  testWidgets('respects custom initialTab (e.g. appearance)', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject(
      initialTab: SettingsTab.appearance,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceTab), findsOneWidget);
  });

  testWidgets('switching tabs updates active tab and content', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject());
    await tester.pumpAndSettle();

    expect(find.byType(SourcesTab), findsOneWidget);

    // Click "Поиск" in tab rail
    await tester.tap(find.text('Поиск'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchTab), findsOneWidget);

    // Click "Резервная копия"
    await tester.tap(find.text('Резервная копия'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupTab), findsOneWidget);
  });

  testWidgets('delegates to custom panelBuilder when provided', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SettingsTab? passedTab;
    await tester.pumpWidget(_buildTestSubject(
      initialTab: SettingsTab.storage,
      panelBuilder: (context, activeTab, onImport, onNav, onTest) {
        passedTab = activeTab;
        return Center(
          child: Text('CustomPanel:${activeTab.wire}'),
        );
      },
    ));
    await tester.pumpAndSettle();

    expect(passedTab, SettingsTab.storage);
    expect(find.text('CustomPanel:storage'), findsOneWidget);
  });

  testWidgets('mobile layout renders horizontal tab rail under 700px',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject());
    await tester.pumpAndSettle();

    expect(find.byType(SourcesTab), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
  });

  testWidgets('renders all 10 tabs at 1440x900 without any layout overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final tab in SettingsTab.values) {
      await tester.pumpWidget(_buildTestSubject(initialTab: tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Tab ${tab.wire} threw an exception');
    }
  });
}
