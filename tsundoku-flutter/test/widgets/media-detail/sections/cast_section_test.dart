import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/cast_section.dart';

/// Тесты `CastSection.svelte`: три режима (voice/manga/flat), portrait-сетка
/// главных, secondary-сворачивание, lightbox по тапу.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(String type, List<Map<String, Object?>> cast,
      {bool? isAnime}) =>
      MediaDetail.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'X',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'isAnime': isAnime,
        'cast': cast,
      });

  Future<void> pumpCast(
    WidgetTester tester, {
    required MediaDetail media,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(child: CastSection(media: media)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('аниме-сэйю: группировка по voiceActorName, заголовок сэйю',
      (tester) async {
    await pumpCast(
      tester,
      media: media('tvshow', [
        {
          'name': 'Kana Hanazawa',
          'character': 'Nadeko',
          'characterRole': 'MAIN',
          'voiceActorName': 'Kana Hanazawa',
        },
        {
          'name': 'Yuki Kaji',
          'character': 'Araragi',
          'characterRole': 'SUPPORTING',
          'voiceActorName': 'Hiroshi Kamiya',
        },
      ], isAnime: true),
    );

    expect(find.textContaining('сэйю'), findsWidgets); // заголовок
    expect(find.text('Nadeko'), findsOneWidget);
    expect(find.text('Главный'), findsOneWidget); // roleMain
    expect(find.text('Kana Hanazawa'), findsOneWidget); // sub
    expect(find.text('сэйю'), findsWidgets); // подпись справа (у обоих рядов)
  });

  testWidgets('манга: режим «Персонажи», flat-карточки', (tester) async {
    await pumpCast(
      tester,
      media: media('manga', [
        {'name': 'Author A', 'character': 'Guts', 'characterRole': 'MAIN'},
        {'name': 'Author B', 'character': 'Griffith', 'characterRole': 'SUPPORTING'},
      ]),
    );

    expect(find.textContaining(RegExp('Персонажи', caseSensitive: false)), findsOneWidget);
    expect(find.text('Guts'), findsOneWidget);
    expect(find.text('Griffith'), findsOneWidget);
    expect(find.text('Главный'), findsOneWidget);
    expect(find.text('Второстепенный'), findsOneWidget);
  });

  testWidgets('легаси-плоский: «В главных ролях», actor + роль',
      (tester) async {
    await pumpCast(
      tester,
      media: media('movie', [
        {'name': 'Jane Doe', 'character': 'Detective'},
      ]),
    );

    expect(find.textContaining(RegExp('В главных ролях', caseSensitive: false)), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Detective'), findsOneWidget);
  });

  testWidgets('пустой cast → секция не рендерится', (tester) async {
    await pumpCast(tester, media: media('movie', []));
    expect(find.textContaining('В главных ролях'), findsNothing);
  });

  testWidgets('сворачивание secondary: шеврон скрывает supporting',
      (tester) async {
    await pumpCast(
      tester,
      media: media('manga', [
        {'name': 'A', 'character': 'Main Char', 'characterRole': 'MAIN'},
        {'name': 'B', 'character': 'Support Char', 'characterRole': 'SUPPORTING'},
      ]),
    );

    expect(find.text('Support Char'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Скрыть второстепенных'));
    await tester.pumpAndSettle();

    expect(find.text('Support Char'), findsNothing);
    // Показать обратно.
    await tester.tap(find.bySemanticsLabel('Показать второстепенных'));
    await tester.pumpAndSettle();
    expect(find.text('Support Char'), findsOneWidget);
  });
}
