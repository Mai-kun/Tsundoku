import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/manga_form_fields.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('MangaFormFields: 4 поля, ввод отдаёт bindable', (tester) async {
    String? author;
    String? currentVolume;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: MangaFormFields(
              author: 'Автор',
              totalChapters: '120',
              currentVolume: '7',
              totalVolumes: '',
              onAuthorChange: (v) => author = v,
              onTotalChaptersChange: (_) {},
              onCurrentVolumeChange: (v) => currentVolume = v,
              onTotalVolumesChange: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Автор'), findsWidgets);
    expect(find.text('Главы'), findsOneWidget);
    expect(find.text('Текущий том'), findsOneWidget);
    expect(find.text('Тома'), findsOneWidget);
    // totalVolumes пустой с placeholder '1' (hint — текст-ребёнок TextField
    // в материальном рендере,EditableText не совпадает).
    await tester.enterText(find.byType(TextField).first, 'Новый автор');
    await tester.pump();
    expect(author, 'Новый автор');
    await tester.enterText(find.widgetWithText(TextField, '7'), '8');
    await tester.pump();
    expect(currentVolume, '8');
  });
}
