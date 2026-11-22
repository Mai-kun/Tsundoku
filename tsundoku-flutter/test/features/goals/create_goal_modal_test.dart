import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/goals/create_goal_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';

GoalDto _dummyGoal({required String title, int year = 2026}) {
  return GoalDto.fromJson(<String, dynamic>{
    'id': 'g1',
    'title': title,
    'description': 'Тест',
    'icon': '🎯',
    'year': year,
    'targetCount': 10,
    'currentCount': 0,
    'isCompleted': false,
    'category': 'all',
    'matchingItems': <dynamic>[],
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  });
}

class _StubGoalApi extends TsundokuApi {
  final Future<GoalDto> Function(CreateGoalPayload payload)? onCreateGoal;

  _StubGoalApi({this.onCreateGoal}) : super(Dio());

  @override
  Future<GoalDto> createGoal(CreateGoalPayload payload) {
    if (onCreateGoal != null) return onCreateGoal!(payload);
    return Future.value(_dummyGoal(title: payload.title, year: payload.year));
  }
}

Future<void> pumpModal(
  WidgetTester tester, {
  required TsundokuApi api,
  bool isOpen = true,
  int year = 2026,
  VoidCallback? onClose,
  ValueChanged<GoalDto>? onCreated,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
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
          child: CreateGoalModal(
            isOpen: isOpen,
            year: year,
            onClose: onClose ?? () {},
            onCreated: onCreated ?? (_) {},
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

  testWidgets('модалка скрыта когда isOpen == false', (tester) async {
    final api = _StubGoalApi();
    await pumpModal(tester, api: api, isOpen: false);

    expect(find.text('Новая цель'), findsNothing);
  });

  testWidgets('вкладка шаблонов: выбор шаблона вызывает createGoal и закрывает модалку',
      (tester) async {
    CreateGoalPayload? submittedPayload;
    bool closed = false;
    GoalDto? createdGoal;

    final api = _StubGoalApi(
      onCreateGoal: (payload) async {
        submittedPayload = payload;
        return _dummyGoal(title: payload.title, year: payload.year);
      },
    );

    await pumpModal(
      tester,
      api: api,
      year: 2026,
      onClose: () => closed = true,
      onCreated: (g) => createdGoal = g,
    );

    expect(find.text('Новая цель'), findsOneWidget);
    expect(find.text('Быстрые шаблоны'), findsOneWidget);
    expect(find.text('Своя цель'), findsOneWidget);

    // Доступны 4 шаблона
    expect(find.text('Прочитать 15 книг'), findsOneWidget);
    expect(find.text('Пройти 10 игр'), findsOneWidget);
    expect(find.text('Посмотреть 30 аниме'), findsOneWidget);
    expect(find.text('Ретро-марафон: 5 фильмов до 2000 года'), findsOneWidget);

    // Тапаем по первому шаблону (Прочитать 15 книг)
    await tester.tap(find.text('Прочитать 15 книг'));
    await tester.pumpAndSettle();

    expect(submittedPayload, isNotNull);
    expect(submittedPayload!.title, 'Прочитать 15 книг 2026');
    expect(submittedPayload!.targetCount, 15);
    expect(submittedPayload!.category, 'book');
    expect(submittedPayload!.icon, '📚');
    expect(closed, isTrue);
    expect(createdGoal, isNotNull);
  });

  testWidgets('вкладка своя цель: заполнение формы и отправка цели',
      (tester) async {
    CreateGoalPayload? submittedPayload;
    bool closed = false;

    final api = _StubGoalApi(
      onCreateGoal: (payload) async {
        submittedPayload = payload;
        return _dummyGoal(title: payload.title, year: payload.year);
      },
    );

    await pumpModal(
      tester,
      api: api,
      year: 2026,
      onClose: () => closed = true,
    );

    // Переключаемся на вкладку «Своя цель»
    await tester.tap(find.text('Своя цель'));
    await tester.pumpAndSettle();

    expect(find.text('Название'), findsOneWidget);
    expect(find.text('Год'), findsOneWidget);
    expect(find.text('Целевое число'), findsOneWidget);
    expect(find.text('Категория'), findsOneWidget);

    // Вводим название цели
    await tester.enterText(find.byType(TextField).at(0), 'Марафон визуальных новелл');
    await tester.pumpAndSettle();

    // Тапаем «Создать цель»
    await tester.tap(find.text('Создать цель'));
    await tester.pumpAndSettle();

    expect(submittedPayload, isNotNull);
    expect(submittedPayload!.title, 'Марафон визуальных новелл');
    expect(submittedPayload!.year, 2026);
    expect(submittedPayload!.targetCount, 10);
    expect(closed, isTrue);
  });

  testWidgets('ошибка создания цели: отображается сообщение об ошибке',
      (tester) async {
    final api = _StubGoalApi(
      onCreateGoal: (_) async => Future.error(Exception('Ошибка сервера')),
    );

    await pumpModal(tester, api: api, year: 2026);

    await tester.tap(find.text('Пройти 10 игр'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось создать цель'), findsOneWidget);
  });
}
