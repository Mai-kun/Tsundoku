import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/game_detail_section.dart';

/// Тесты `GameDetailSection.svelte`: часы-прогресс (teal, total 0),
/// достижения (поиск, тогглы, пагинация 60/стр).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  GameAchievementItem ach(String name, [String? description]) =>
      GameAchievementItem(name: name, description: description, iconUrl: null);

  Future<void> pumpSection(
    WidgetTester tester, {
    required int progressValue,
    required List<GameAchievementItem> achievements,
    required int achievementsTotal,
    Set<String> unlocked = const {},
    bool loading = false,
    required void Function(int value) onCounterChange,
    required void Function(String name) onToggleAchievement,
    required void Function() onToggleAll,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: GameDetailSection(
              progressValue: progressValue,
              progressLabel: 'Наиграно часов',
              progressError: null,
              onCounterChange: onCounterChange,
              achievements: achievements,
              achievementsTotal: achievementsTotal,
              achievementsLoading: loading,
              achievementsBusy: false,
              achievementsTruncated: false,
              unlockedNames: unlocked,
              onToggleAchievement: (name) async => onToggleAchievement(name),
              onToggleAllAchievements: () async => onToggleAll(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('часы: ProgressCard с +1/+5 (total 0 → без кольца)',
      (tester) async {
    final changes = <int>[];
    await pumpSection(
      tester,
      progressValue: 42,
      achievements: [],
      achievementsTotal: 0,
      onCounterChange: changes.add,
      onToggleAchievement: (_) {},
      onToggleAll: () {},
    );

    expect(find.text('НАИГРАНО ЧАСОВ'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('%'), findsNothing); // total 0 → кольца нет

    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(changes, [43]); // onStep → onCounterChange(value+delta)
  });

  testWidgets('достижения: счётчик, «Отметить все», тоггл карточки',
      (tester) async {
    final toggled = <String>[];
    var toggleAll = 0;
    await pumpSection(
      tester,
      progressValue: 42,
      achievements: [ach('First Kill', 'Defeat enemy'), ach('Explorer')],
      achievementsTotal: 30,
      unlocked: {'first kill'},
      onCounterChange: (_) {},
      onToggleAchievement: toggled.add,
      onToggleAll: () => toggleAll += 1,
    );

    expect(find.text('ДОСТИЖЕНИЯ'), findsOneWidget); // uppercase
    expect(find.textContaining('Получено'), findsOneWidget); // unlocked 1/30
    expect(find.text('Отметить все'), findsOneWidget);
    expect(find.text('First Kill'), findsOneWidget);
    expect(find.text('Explorer'), findsOneWidget);

    await tester.tap(find.text('Отметить все'));
    await tester.pump();
    expect(toggleAll, 1);

    await tester.tap(find.text('Explorer'));
    await tester.pump();
    expect(toggled, ['Explorer']);
  });

  testWidgets('поиск: фильтр по названию и описанию, «Достижения не найдены»',
      (tester) async {
    await pumpSection(
      tester,
      progressValue: 42,
      achievements: [ach('First Kill', 'Defeat enemy')],
      achievementsTotal: 1,
      onCounterChange: (_) {},
      onToggleAchievement: (_) {},
      onToggleAll: () {},
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.textContaining('Достижения не найдены'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'enemy');
    await tester.pump();
    expect(find.text('First Kill'), findsOneWidget);
  });

  testWidgets('пустые достижения: приглашение обновить метаданные',
      (tester) async {
    await pumpSection(
      tester,
      progressValue: 0,
      achievements: [],
      achievementsTotal: 0,
      onCounterChange: (_) {},
      onToggleAchievement: (_) {},
      onToggleAll: () {},
    );

    expect(find.textContaining('Достижения не загружены'), findsOneWidget);
  });

  testWidgets('пагинация: 70 достижений → 2 страницы, чип страницы',
      (tester) async {
    final list = [for (var i = 1; i <= 70; i++) ach('Ach $i')];
    await pumpSection(
      tester,
      progressValue: 0,
      achievements: list,
      achievementsTotal: 70,
      onCounterChange: (_) {},
      onToggleAchievement: (_) {},
      onToggleAll: () {},
    );

    expect(find.textContaining('Страница 1 из 2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('показано 60 из 70'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.textContaining('Страница 2 из 2'), findsOneWidget);
    expect(find.text('Ach 70'), findsOneWidget); // вторая страница
  });
}
