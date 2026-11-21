import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/notes_module.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  Future<void> pumpModule(
    WidgetTester tester, {
    required String notes,
    required ValueChanged<String> onNotesChange,
    bool flat = false,
  }) async {
    var current = notes;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 380,
              height: flat ? 300 : null,
              child: StatefulBuilder(builder: (context, setOuter) {
                return NotesModule(
                  notes: current,
                  onNotesChange: (v) {
                    current = v;
                    onNotesChange(v);
                    setOuter(() {});
                  },
                  flat: flat,
                );
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('стейч-режим: тайтл, placeholder, ввод отдаёт значение',
      (tester) async {
    String? changed;
    await pumpModule(
      tester,
      notes: '',
      onNotesChange: (v) => changed = v,
    );
    expect(find.text('ЗАМЕТКИ'), findsOneWidget);
    expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
    expect(find.byType(ModuleCard), findsOneWidget);

    final field = find.byType(EditableText).last;
    await tester.enterText(field, 'Моя заметка');
    await tester.pump();
    expect(changed, 'Моя заметка');
  });

  testWidgets('внешнее значение синхронизируется в контроллер (bindable)',
      (tester) async {
    var external = 'старое';
    await pumpModule(tester, notes: external, onNotesChange: (v) {});
    expect(find.text('старое'), findsOneWidget);
    external = 'новое';
    // didUpdateWidget: parent rebuild с новым notes.
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 380,
              child: NotesModule(
                notes: 'новое',
                onNotesChange: (v) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('новое'), findsOneWidget);
    expect(find.text('старое'), findsNothing);
  });

  testWidgets('flat: без фикс-высоты (растяжение обеспечивает хост)',
      (tester) async {
    await pumpModule(tester, notes: 'x', onNotesChange: (v) {}, flat: true);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.expands, isTrue);
    expect(field.maxLines, isNull);
  });
}
