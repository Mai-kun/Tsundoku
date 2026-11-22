import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';

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
  return ProviderScope(
    overrides: [
      tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
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
  testWidgets('renders default initial tab (sources) in desktop mode',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject());
    await tester.pumpAndSettle();

    // Sidebar navigation contains tabs
    expect(find.text('Источники'), findsWidgets); // tab + header
    expect(find.text('Поиск'), findsOneWidget);
    expect(find.text('Резервная копия'), findsOneWidget);
    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Хранилище'), findsOneWidget);

    // Section content
    expect(find.text('Источники: секция настроек'), findsOneWidget);
  });

  testWidgets('respects custom initialTab (e.g. appearance)', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject(
      initialTab: SettingsTab.appearance,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Внешний вид: секция настроек'), findsOneWidget);
  });

  testWidgets('switching tabs updates active tab and content', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject());
    await tester.pumpAndSettle();

    expect(find.text('Источники: секция настроек'), findsOneWidget);

    // Click "Поиск" in tab rail
    await tester.tap(find.text('Поиск'));
    await tester.pumpAndSettle();

    expect(find.text('Поиск: секция настроек'), findsOneWidget);

    // Click "Резервная копия"
    await tester.tap(find.text('Резервная копия'));
    await tester.pumpAndSettle();

    expect(find.text('Резервная копия: секция настроек'), findsOneWidget);
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

    expect(find.text('Источники: секция настроек'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
  });
}
