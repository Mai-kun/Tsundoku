import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/goals/goal_card.dart';

Future<void> pumpGoalCard(
  WidgetTester tester, {
  required GoalDto goal,
  ValueChanged<String>? onOpenMedia,
  ValueChanged<GoalDto>? onDelete,
  Locale locale = Locale.ru,
  double width = 400,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tProvider.overrideWithValue(I18nDictionary(locale)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: GoalCard(
                goal: goal,
                onOpenMedia: onOpenMedia ?? (_) {},
                onDelete: onDelete ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('незавершенная цель без описания и элементов', (tester) async {
    const goal = GoalDto(
      id: 'goal-1',
      title: 'Прочитать 12 книг',
      description: null,
      icon: '📚',
      year: 2026,
      targetCount: 12,
      currentCount: 3,
      isCompleted: false,
      category: 'book',
      smartQueryJson: null,
      completedItems: [],
    );

    await pumpGoalCard(tester, goal: goal);

    expect(find.text('📚'), findsOneWidget);
    expect(find.text('Прочитать 12 книг'), findsOneWidget);
    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('🎉 Выполнено!'), findsNothing);
    expect(find.text('Пока ни одного тайтла в зачёте'), findsOneWidget);
  });

  testWidgets('завершенная цель с описанием и тайтлами', (tester) async {
    String? openedMediaId;

    final mediaItem1 = MediaItem.fromJson({
      'id': 'book-1',
      'title': 'Dune',
      'type': 'book',
      'status': 2,
      'createdAt': '2026-01-01',
    });

    final goal = GoalDto(
      id: 'goal-2',
      title: 'Пройти 5 игр',
      description: 'Игры разных жанров для расширения кругозора',
      icon: '🎮',
      year: 2026,
      targetCount: 5,
      currentCount: 5,
      isCompleted: true,
      category: 'game',
      smartQueryJson: null,
      completedItems: [mediaItem1],
    );

    await pumpGoalCard(
      tester,
      goal: goal,
      onOpenMedia: (id) => openedMediaId = id,
    );

    expect(find.text('🎮'), findsOneWidget);
    expect(find.text('Пройти 5 игр'), findsOneWidget);
    expect(
      find.text('Игры разных жанров для расширения кругозора'),
      findsOneWidget,
    );
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('🎉 Выполнено!'), findsOneWidget);

    // Превью завершенных тайтлов
    expect(find.text('Пока ни одного тайтла в зачёте'), findsNothing);
    expect(find.byType(InkWell), findsWidgets);

    // Клик по превью открывает тайтл
    await tester.tap(find.byKey(const Key('goal-item-book-1')));
    expect(openedMediaId, equals('book-1'));
  });

  testWidgets('клик по кнопке удаления вызывает onDelete', (tester) async {
    GoalDto? deletedGoal;

    const goal = GoalDto(
      id: 'goal-del',
      title: 'Удаляемая цель',
      description: null,
      icon: '🎯',
      year: 2026,
      targetCount: 10,
      currentCount: 1,
      isCompleted: false,
      category: 'all',
      smartQueryJson: null,
      completedItems: [],
    );

    await pumpGoalCard(
      tester,
      goal: goal,
      onDelete: (g) => deletedGoal = g,
    );

    final deleteFinder = find.byKey(const Key('goal-delete-btn'));
    expect(deleteFinder, findsOneWidget);

    await tester.tap(deleteFinder);
    expect(deletedGoal?.id, equals('goal-del'));
  });

  testWidgets('английская локаль', (tester) async {
    const goal = GoalDto(
      id: 'goal-en',
      title: 'Read 10 books',
      description: null,
      icon: '📖',
      year: 2026,
      targetCount: 10,
      currentCount: 10,
      isCompleted: true,
      category: 'book',
      smartQueryJson: null,
      completedItems: [],
    );

    await pumpGoalCard(
      tester,
      goal: goal,
      locale: Locale.en,
    );

    expect(find.text('🎉 Completed!'), findsOneWidget);
    expect(
      find.text('No titles count toward this goal yet'),
      findsOneWidget,
    );
  });
}
