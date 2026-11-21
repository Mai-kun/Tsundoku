import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Widget card,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(child: card),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('обычный режим: иконка-плитка, uppercase-тайтл, чип count',
      (tester) async {
    await pumpCard(
      tester,
      card: const ModuleCard(
        icon: Icon(LucideIcons.fileText),
        title: 'Основное',
        count: 3,
        child: Text('Тело'),
      ),
    );
    expect(find.text('ОСНОВНОЕ'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
    expect(find.text('Тело'), findsOneWidget);
  });

  testWidgets('count=0 — чип не рендерится', (tester) async {
    await pumpCard(
      tester,
      card: const ModuleCard(
        icon: Icon(LucideIcons.fileText),
        title: 'Основное',
        count: 0,
        child: SizedBox.shrink(),
      ),
    );
    expect(find.text('0'), findsNothing);
  });

  testWidgets('flat: без рамки-карточки, section-лейбл 10px', (tester) async {
    await pumpCard(
      tester,
      card: const ModuleCard(
        icon: Icon(LucideIcons.fileText),
        title: 'Цитаты',
        count: 2,
        flat: true,
        child: Text('Тело'),
      ),
    );
    expect(find.text('ЦИТАТЫ'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Тело'), findsOneWidget);
  });

  testWidgets('flat + showLabel=false: только тело', (tester) async {
    await pumpCard(
      tester,
      card: const ModuleCard(
        icon: Icon(LucideIcons.fileText),
        title: 'Цитаты',
        count: 2,
        flat: true,
        showLabel: false,
        child: Text('Тело'),
      ),
    );
    expect(find.text('ЦИТАТЫ'), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('Тело'), findsOneWidget);
  });
}
