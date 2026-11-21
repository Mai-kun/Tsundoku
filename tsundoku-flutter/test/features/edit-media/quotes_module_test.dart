import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/quotes_module.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

void main() {
  Future<void> pumpModule(
    WidgetTester tester,
    List<MediaQuote> quotes,
    ValueChanged<List<MediaQuote>> onChange,
  ) async {
    var current = quotes;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: StatefulBuilder(builder: (context, setOuter) {
                return QuotesModule(
                  quotes: current,
                  onChange: (next) {
                    current = next;
                    onChange(next);
                    setOuter(() {});
                  },
                );
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('пустой: empty-строка + кнопка добавления', (tester) async {
    List<List<MediaQuote>>? commits;
    await pumpModule(tester, const [], (next) {
      commits ??= [];
      commits!.add(next);
    });
    expect(find.byType(ModuleCard), findsOneWidget);
    expect(find.byIcon(LucideIcons.quote), findsOneWidget);
    expect(find.textContaining('нет сохранённых цитат'), findsOneWidget);
    expect(find.text('Добавить цитату'), findsOneWidget);
    expect(commits, isNull); // ничего не добавлено
  });

  testWidgets('add: форма ввода → цитата с context и created', (tester) async {
    List<List<MediaQuote>>? commits;
    await pumpModule(tester, const [], (next) {
      commits ??= [];
      commits!.add(next);
    });
    await tester.tap(find.text('Добавить цитату'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Сохранить цитату'), findsOneWidget);

    // Текст цитаты в multiline-поле (первый TextField).
    await tester.enterText(find.byType(TextField).first, 'Быть или не быть');
    await tester.pump();
    // Контекст — второй TextField.
    await tester.enterText(
        find.byType(TextField).at(1), 'акт 3, сцена 1');
    await tester.pump();
    await tester.tap(find.text('Сохранить цитату'));
    await tester.pump();
    expect(commits, hasLength(1));
    expect(commits!.last.single.text, 'Быть или не быть');
    expect(commits!.last.single.pageOrContext, 'акт 3, сцена 1');
    expect(commits!.last.single.createdAt, isNotEmpty);
    // Форма закрылась, кнопка добавления вернулась.
    expect(find.text('Добавить цитату'), findsOneWidget);
  });

  testWidgets('кавычки «» вокруг текста цитаты', (tester) async {
    await pumpModule(tester, [
      const MediaQuote(
        id: 'q1',
        text: 'Истина в вине',
        pageOrContext: null,
        createdAt: '2024-01-01T00:00:00Z',
      ),
    ], (_) {});
    // rich-text: „...“ как части Text.rich.
    expect(find.textContaining('Истина в вине'), findsOneWidget);
    final text = tester.widget<Text>(find.textContaining('Истина в вине'));
    final span = text.textSpan! as TextSpan;
    expect(span.children!.first.toString(), contains('“'));
    expect(span.children!.last.toString(), contains('”'));
  });

  testWidgets('edit: pencil → правка текста → check-commit', (tester) async {
    List<List<MediaQuote>>? commits;
    await pumpModule(tester, [
      const MediaQuote(
        id: 'q1',
        text: 'Старый текст',
        pageOrContext: 'стр. 5',
        createdAt: '2024-01-01T00:00:00Z',
      ),
    ], (next) {
      commits ??= [];
      commits!.add(next);
    });
    await tester.tap(find.byIcon(LucideIcons.pencil).first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Старый текст'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Новый текст');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.check).first);
    await tester.pump();
    expect(commits!.last.single.text, 'Новый текст');
    expect(commits!.last.single.pageOrContext, 'стр. 5');
    expect(commits!.last.single.createdAt, '2024-01-01T00:00:00Z'); // сохранён
  });

  testWidgets('удаление trash2', (tester) async {
    List<List<MediaQuote>>? commits;
    await pumpModule(tester, [
      const MediaQuote(
        id: 'q1',
        text: 'A',
        pageOrContext: null,
        createdAt: '2024-01-01T00:00:00Z',
      ),
    ], (next) {
      commits ??= [];
      commits!.add(next);
    });
    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await tester.pump();
    expect(commits!.last, isEmpty);
    // Пустой стейт вернулся.
    expect(find.textContaining('нет сохранённых цитат'), findsOneWidget);
  });
}
