import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/settings/tabs/appearance_tab.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';

Widget _buildSubject() {
  return ProviderScope(
    child: MaterialApp(
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      home: const Scaffold(
        body: AppearanceTab(),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AppearanceTab renders language buttons, icon cards and accent preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Язык интерфейса'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    expect(find.text('Иконка приложения'), findsOneWidget);
    expect(find.text('Основная (Tsundoku)'), findsOneWidget);
    expect(find.text('Альтернативная'), findsOneWidget);

    expect(find.text('Акцентный цвет'), findsOneWidget);
    expect(find.text('СКОРО'), findsOneWidget);
  });

  testWidgets('AppearanceTab switches language to English and changes text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    // Tap English
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // Verify header switched to English
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Interface Language'), findsOneWidget);
    expect(find.text('App Icon'), findsOneWidget);
    expect(find.text('Default (Tsundoku)'), findsOneWidget);
  });

  testWidgets('AppearanceTab toggles app icon', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    // Tap alternative icon
    await tester.tap(find.text('Альтернативная'));
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(AppearanceTab));
    final container = ProviderScope.containerOf(element);
    expect(container.read(uiSettingsProvider).appIcon, 'alt');

    // Tap default icon
    await tester.tap(find.text('Основная (Tsundoku)'));
    await tester.pumpAndSettle();
    expect(container.read(uiSettingsProvider).appIcon, 'default');
  });
}
