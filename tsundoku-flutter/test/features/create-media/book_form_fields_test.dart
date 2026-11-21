import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/book_form_fields.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('BookFormFields: не-роман → страницы', (tester) async {
    String? pages;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: BookFormFields(
              author: 'Автор',
              totalPages: '320',
              format: 'book',
              totalChapters: '',
              totalVolumes: '',
              onAuthorChange: (_) {},
              onTotalPagesChange: (v) => pages = v,
              onFormatChange: (_) {},
              onTotalChaptersChange: (_) {},
              onTotalVolumesChange: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Автор'), findsWidgets);
    expect(find.text('Формат'), findsOneWidget);
    expect(find.text('Страницы'), findsOneWidget);
    expect(find.text('Главы'), findsNothing);
    expect(find.text('Обычная книга'), findsOneWidget); // формат-селект

    await tester.enterText(find.widgetWithText(TextField, '320'), '350');
    await tester.pump();
    expect(pages, '350');
  });

  testWidgets('BookFormFields: ранобэ → главы + тома', (tester) async {
    String? chapters;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: BookFormFields(
              author: 'a',
              totalPages: '',
              format: 'light_novel',
              totalChapters: '42',
              totalVolumes: '5',
              onAuthorChange: (_) {},
              onTotalPagesChange: (_) {},
              onFormatChange: (_) {},
              onTotalChaptersChange: (v) => chapters = v,
              onTotalVolumesChange: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Главы'), findsOneWidget);
    expect(find.text('Тома'), findsOneWidget);
    expect(find.text('Страницы'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '42'), '43');
    await tester.pump();
    expect(chapters, '43');
  });

  testWidgets('BookFormFields: смена формата через селект', (tester) async {
    String? format;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: BookFormFields(
              author: 'a',
              totalPages: '',
              format: 'book',
              totalChapters: '',
              totalVolumes: '',
              onAuthorChange: (_) {},
              onTotalPagesChange: (_) {},
              onFormatChange: (v) => format = v,
              onTotalChaptersChange: (_) {},
              onTotalVolumesChange: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Обычная книга'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Электронная книга').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(format, 'ebook');
  });
}
