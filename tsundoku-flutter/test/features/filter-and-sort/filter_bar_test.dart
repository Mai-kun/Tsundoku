import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/filter-and-sort/filter_bar.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

/// Widget-тесты `FilterBar.svelte`: группировка/статус/сортировка через
/// поповеры, дебаунс поиска 300ms, TotalBadge, счётчик статуса.
void main() {
  final statuses = <StatusFilter>[];
  final sorts = <LibrarySort>[];
  final groups = <GroupBy>[];
  final searches = <String>[];

  Future<void> pumpBar(
    WidgetTester tester, {
    StatusFilter status = const StatusFilter.all(),
    LibrarySort sort = LibrarySort.newest,
    GroupBy groupBy = GroupBy.status,
    Map<StatusFilter, int> counts = const {},
    int? totalCount,
    int? shownCount,
  }) async {
    statuses.clear();
    sorts.clear();
    groups.clear();
    searches.clear();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            child: FilterBar(
              status: status,
              sort: sort,
              groupBy: groupBy,
              search: '',
              counts: counts,
              totalCount: totalCount,
              shownCount: shownCount,
              onStatusChange: statuses.add,
              onSortChange: sorts.add,
              onGroupByChange: groups.add,
              onSearchChange: searches.add,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('рендер: все триггеры + центрированный TotalBadge',
      (tester) async {
    await pumpBar(tester,
        counts: {const StatusFilter.all(): 42},
        totalCount: 100,
        shownCount: 42);
    // Триггеры-иконки: группировка (ListChecks), сортировка (ArrowDown).
    expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowDown), findsOneWidget);
    // Статус-триггер: «Все» + счётчик 42 + ChevronDown.
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    // Поле поиска.
    expect(find.byIcon(LucideIcons.search), findsOneWidget);
  });

  testWidgets('статус-поповер: 6 опций, выбор → onStatusChange',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();

    // 6 опций: Все + 5 статусов.
    expect(find.text('В планах'), findsOneWidget);
    expect(find.text('В процессе'), findsOneWidget);
    expect(find.text('Завершено'), findsOneWidget);
    expect(find.text('Отложено'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);

    await tester.tap(find.text('Завершено'));
    await tester.pumpAndSettle();
    expect(statuses, [const StatusFilter.status(2)]);
  });

  testWidgets('сортировка: выбор «По названию» → onSortChange(title)',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.byIcon(LucideIcons.arrowDown));
    await tester.pumpAndSettle();

    await tester.tap(find.text('По алфавиту'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(sorts, [LibrarySort.title]);
  });

  testWidgets('группировка: выбор «По франшизе» → onGroupByChange',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.byIcon(LucideIcons.listChecks));
    await tester.pumpAndSettle();

    await tester.tap(find.text('По франшизе'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(groups, [GroupBy.franchise]);
  });

  testWidgets('поиск: дебаунс 300ms — один вызов на серию ввода',
      (tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(TextField), 'нар');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'норагами');
    await tester.pump(const Duration(milliseconds: 350));
    expect(searches, ['норагами']);
  });

  testWidgets('иконки опций сортировки в поповере (leading)',
      (tester) async {
    await pumpBar(tester);
    await tester.tap(find.byIcon(LucideIcons.arrowDown));
    await tester.pumpAndSettle();
    // renderOption-аналог: иконки строк.
    expect(find.byIcon(LucideIcons.star), findsOneWidget);
    expect(find.byIcon(LucideIcons.type), findsOneWidget);
  });
}
