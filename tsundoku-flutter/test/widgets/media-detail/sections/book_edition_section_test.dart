import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/book_edition_section.dart';

/// Тесты `BookEditionSection.svelte`: строки издания, ISBN-копирование.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(Map<String, Object?> extra) => MediaDetail.fromJson({
        'id': 'm1',
        'type': 'book',
        'title': 'Book',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  Future<void> pumpEdition(
    WidgetTester tester, {
    required MediaDetail media,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(child: BookEditionSection(media: media)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('строки: издатель, страницы, год, язык, формат',
      (tester) async {
    await pumpEdition(
      tester,
      media: media({
        'studio': 'Азбука',
        'totalPages': 320,
        'releaseYear': 2018,
        'originalLanguage': 'en',
      }),
    );

    expect(find.text('ОБ ИЗДАНИИ'), findsOneWidget);
    expect(find.text('Издатель'), findsOneWidget);
    expect(find.text('Азбука'), findsOneWidget);
    expect(find.text('320 стр.'), findsOneWidget);
    expect(find.text('2018'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Электронная книга'), findsOneWidget); // format book → дефолт
  });

  testWidgets('ISBN: строка col-span-2 с кнопкой «Копировать»',
      (tester) async {
    await pumpEdition(
      tester,
      media: media({'isbn': '978-5-17-012345-6'}),
    );

    expect(find.text('ISBN'), findsOneWidget);
    expect(find.text('978-5-17-012345-6'), findsOneWidget);
    expect(find.text('Копировать'), findsOneWidget);
  });

  testWidgets('userPlatform переопределяет формат', (tester) async {
    await pumpEdition(
      tester,
      media: media({'userPlatform': 'Печатная'}),
    );

    expect(find.text('Печатная'), findsOneWidget);
    expect(find.text('Электронная книга'), findsNothing);
  });

  testWidgets('формат из provider format ≠ book показывается как есть',
      (tester) async {
    await pumpEdition(
      tester,
      media: media({'format': 'paperback'}),
    );

    expect(find.text('paperback'), findsOneWidget);
  });
}
