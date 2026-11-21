import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/features/update-progress/optimistic_progress.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// Полный цикл оптимистичного реестра прогресса.
void main() {
  late ProviderContainer container;
  late OptimisticProgressController ctrl;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    ctrl = container.read(optimisticProgressProvider.notifier);
  });

  test('apply/peek: значение регистрируется', () {
    ctrl.apply('m1', 42);
    expect(ctrl.peek('m1'), 42);
  });

  test('resolve: совпадение снимает override; расхождение ре-базируется',
      () {
    ctrl.apply('m1', 42);
    ctrl.resolve('m1', 42);
    expect(ctrl.peek('m1'), isNull, reason: 'сервер догнал — override снят');

    ctrl.apply('m1', 42);
    // Пока запрос в полёте пользователь шагнул ещё раз:
    ctrl.apply('m1', 45);
    ctrl.resolve('m1', 42);
    expect(ctrl.peek('m1'), 45,
        reason: 'новер шаг сохранился (re-base на новый value)');
  });

  test('clear: ошибка запроса убирает оптимистичное значение', () {
    ctrl.apply('m1', 7);
    ctrl.clear('m1');
    expect(ctrl.peek('m1'), isNull);
  });

  test('TTL 15s: протухшая запись отбрасывается на чтении', () {
    // DateTime.now в fakeAsync не сдвигается — TTL проверяем через applyAt
    // (запись 16s назад) — поведение 1-в-1 с Date.now() в TS.
    ctrl.applyAt('m1', 3, DateTime.now().subtract(const Duration(milliseconds: 14900)));
    expect(ctrl.peek('m1'), 3);
    ctrl.applyAt('m1', 3, DateTime.now().subtract(const Duration(milliseconds: 15100)));
    expect(ctrl.peek('m1'), isNull,
        reason: 'keepalive flush не отчитается — stale override не живёт');
  });

  test('reconcile: анти-откат входящих данных', () {
    ctrl.apply('m1', 12);
    // Сервер вернул старое значение — держим оптимистичное:
    expect(ctrl.reconcile('m1', 5), 12);
    // Сервер догнал — override снят:
    expect(ctrl.reconcile('m1', 12), 12);
    expect(ctrl.peek('m1'), isNull);
    // Без override — входящее значение проходит:
    expect(ctrl.reconcile('m1', 99), 99);
  });

  test('reconcileListProgress: item с живым override получает шаг', () {
    MediaItem media(String id, int currentPage) => MediaItem.fromJson({
          'id': id, 'type': 'book', 'title': 'T', 'status': 1,
          'createdAt': '2026-11-21T00:00:00Z',
          'currentPage': currentPage, 'totalPages': 300,
        });

    final incoming = [media('a', 10), media('b', 20), media('c', 30)];
    ctrl.apply('b', 25);

    final reconciled = ctrl.reconcileListProgress(incoming);
    expect(reconciled[0].currentPage, 10);
    expect(reconciled[1].currentPage, 25,
        reason: 'живой шаг сохранён на входящем объекте');
    expect(reconciled[2].currentPage, 30);
    // Сервер догнал по b? Нет (25 != 20) — override жив:
    expect(ctrl.peek('b'), 25);
  });

  test('reconcileListProgress: сервер догнал — override снят', () {
    MediaItem media(String id, int currentPage) => MediaItem.fromJson({
          'id': id, 'type': 'book', 'title': 'T', 'status': 1,
          'createdAt': '2026-11-21T00:00:00Z', 'currentPage': currentPage,
        });
    ctrl.apply('a', 10);
    final reconciled = ctrl.reconcileListProgress([media('a', 10)]);
    expect(reconciled.single.currentPage, 10);
    expect(ctrl.peek('a'), isNull,
        reason: 'override снят: сервер догнал, записи не переживают подтверждение');
  });
}
