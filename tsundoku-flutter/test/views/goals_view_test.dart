import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/views/goals_view.dart';

GoalDto _makeGoal({
  required String id,
  required String title,
  int year = 2026,
  int targetCount = 10,
  int currentCount = 5,
  bool isCompleted = false,
}) {
  return GoalDto.fromJson(<String, dynamic>{
    'id': id,
    'title': title,
    'description': 'Тестовое описание',
    'icon': '🎯',
    'year': year,
    'targetCount': targetCount,
    'currentCount': currentCount,
    'isCompleted': isCompleted,
    'category': 'all',
    'matchingItems': <dynamic>[],
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  });
}

List<GoalDto> _sampleGoals() {
  return [
    _makeGoal(
      id: 'g1',
      title: 'Прочитать 15 книг',
      targetCount: 15,
      currentCount: 15,
      isCompleted: true,
    ),
    _makeGoal(
      id: 'g2',
      title: 'Пройти 10 игр',
      targetCount: 10,
      currentCount: 3,
      isCompleted: false,
    ),
  ];
}

class _StubGoalsViewApi extends TsundokuApi {
  final Future<List<GoalDto>> Function(int year)? onGetGoals;
  final Future<void> Function(String id)? onDeleteGoal;
  final Future<GoalDto> Function(CreateGoalPayload payload)? onCreateGoal;

  _StubGoalsViewApi({
    this.onGetGoals,
    this.onDeleteGoal,
    this.onCreateGoal,
  }) : super(Dio());

  @override
  Future<List<GoalDto>> getGoals([int? year]) {
    if (onGetGoals != null) return onGetGoals!(year ?? 2026);
    return Future.value(_sampleGoals());
  }

  @override
  Future<void> deleteGoal(String id) {
    if (onDeleteGoal != null) return onDeleteGoal!(id);
    return Future.value();
  }

  @override
  Future<GoalDto> createGoal(CreateGoalPayload payload) {
    if (onCreateGoal != null) return onCreateGoal!(payload);
    return Future.value(_makeGoal(id: 'g_new', title: payload.title));
  }
}

Future<void> pumpGoalsView(
  WidgetTester tester, {
  required TsundokuApi api,
  int refreshKey = 0,
  ValueChanged<String>? onOpenMedia,
  VoidCallback? onMediaChanged,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              GoalsView(
                refreshKey: refreshKey,
                onOpenMedia: onOpenMedia ?? (_) {},
                onMediaChanged: onMediaChanged ?? () {},
              ),
              const ConfirmModal(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('loading state: скелетон / кольцо 0%', (tester) async {
    final completer = Completer<List<GoalDto>>();
    final api = _StubGoalsViewApi(onGetGoals: (_) => completer.future);

    await pumpGoalsView(tester, api: api);

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Новая цель'), findsOneWidget);

    completer.complete(_sampleGoals());
    await tester.pumpAndSettle();
  });

  testWidgets('ошибка загрузки: блок с ошибкой loadFailed', (tester) async {
    final api = _StubGoalsViewApi(
      onGetGoals: (_) => Future.error(Exception('Сбой сервера')),
    );

    await pumpGoalsView(tester, api: api);

    expect(find.text('Не удалось загрузить цели'), findsOneWidget);
  });

  testWidgets('пустой список целей: сообщение goals.empty', (tester) async {
    final api = _StubGoalsViewApi(onGetGoals: (_) => Future.value(const []));

    await pumpGoalsView(tester, api: api);

    expect(find.text('На этот год целей пока нет — создайте первую!'),
        findsOneWidget);
  });

  testWidgets('успешный список целей: кольцо, процент, карточки целей',
      (tester) async {
    final api = _StubGoalsViewApi();

    await pumpGoalsView(tester, api: api);

    // 1 из 2 выполнена = 50%
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Выполнено 1 из 2 целей'), findsOneWidget);
    expect(find.text('Общий прогресс'), findsOneWidget);

    // Карточки
    expect(find.text('Прочитать 15 книг'), findsOneWidget);
    expect(find.text('Пройти 10 игр'), findsOneWidget);
  });

  testWidgets('переключение года запрашивает цели за выбранный год',
      (tester) async {
    int? requestedYear;
    final api = _StubGoalsViewApi(
      onGetGoals: (year) async {
        requestedYear = year;
        return _sampleGoals();
      },
    );

    await pumpGoalsView(tester, api: api);

    final currentYear = DateTime.now().year;
    final nextYear = currentYear + 1;

    await tester.tap(find.text(nextYear.toString()));
    await tester.pumpAndSettle();

    expect(requestedYear, nextYear);
  });

  testWidgets('удаление цели вызывает подтверждение ConfirmModal и deleteGoal',
      (tester) async {
    String? deletedId;
    final api = _StubGoalsViewApi(
      onDeleteGoal: (id) async {
        deletedId = id;
      },
    );

    await pumpGoalsView(tester, api: api);

    // Тапаем по кнопке удаления карточки
    final deleteButtons = find.byTooltip('Удалить цель');
    expect(deleteButtons, findsWidgets);

    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle();

    // ConfirmModal открыт
    expect(find.textContaining('Удалить цель'), findsWidgets);
    expect(find.text('Удалить'), findsOneWidget);

    // Подтверждаем удаление
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(deletedId, 'g1');
    expect(find.text('Прочитать 15 книг'), findsNothing);
  });

  testWidgets('открытие CreateGoalModal и добавление новой цели',
      (tester) async {
    bool mediaChanged = false;
    CreateGoalPayload? createdPayload;
    final api = _StubGoalsViewApi(
      onCreateGoal: (payload) async {
        createdPayload = payload;
        return _makeGoal(id: 'g3', title: payload.title);
      },
    );

    await pumpGoalsView(
      tester,
      api: api,
      onMediaChanged: () => mediaChanged = true,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Новая цель'));
    await tester.pumpAndSettle();

    // CreateGoalModal открыт
    expect(find.text('Быстрые шаблоны'), findsOneWidget);

    // Тапаем по шаблону
    await tester.tap(find.text('Пройти 10 игр').last);
    await tester.pumpAndSettle();

    // Модалка закрылась и вызван onMediaChanged
    expect(find.text('Быстрые шаблоны'), findsNothing);
    expect(mediaChanged, isTrue);
    expect(createdPayload, isNotNull);
  });
}
