import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsundoku_flutter/features/settings/settings_modal.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';

Widget _buildSubject({
  bool isOpen = true,
  bool embedded = false,
  SettingsTab initialTab = SettingsTab.sources,
  VoidCallback? onClose,
  VoidCallback? onImportCompleted,
}) {
  return ProviderScope(
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

  testWidgets('hides when isOpen is false and embedded is false',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false, embedded: false));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsModal), findsOneWidget);
    expect(find.byType(SettingsView), findsNothing);
  });

  testWidgets('renders modal header and SettingsView when isOpen is true',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: true, embedded: false));
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsWidgets);
    expect(find.byIcon(LucideIcons.settings), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('renders directly without modal chrome when embedded is true',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false, embedded: true));
    await tester.pumpAndSettle();

    // In embedded mode, close button is not present
    expect(find.byIcon(LucideIcons.x), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('passes initialTab to SettingsView', (tester) async {
    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      initialTab: SettingsTab.storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Хранилище'), findsWidgets);
  });

  testWidgets('clicking close button triggers onClose callback',
      (tester) async {
    bool closed = false;

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      onClose: () => closed = true,
    ));
    await tester.pumpAndSettle();

    final closeBtn = find.byIcon(LucideIcons.x);
    expect(closeBtn, findsOneWidget);

    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
