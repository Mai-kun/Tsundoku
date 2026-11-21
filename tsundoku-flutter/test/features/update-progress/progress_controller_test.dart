import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/features/change-status/status_controller.dart';
import 'package:tsundoku_flutter/features/update-progress/optimistic_progress.dart';
import 'package:tsundoku_flutter/features/update-progress/progress_controller.dart';
import 'package:tsundoku_flutter/features/update-progress/status_promotion_toast.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

MediaItem book({int currentPage = 0, int totalPages = 100}) {
  return MediaItem.fromJson({
    'id': 'm1', 'type': 'book', 'title': 'T', 'status': 0,
    'createdAt': '2026-11-21T00:00:00Z',
    'currentPage': currentPage, 'totalPages': totalPages,
  });
}

/// Полный цикл контроллеров прогресса/статуса. Тесты — реальный event loop:
/// дебаунс сокращён до 50ms, ожидание 120ms (надёжнее fakeAsync: dio
/// завершается через макро-таски).
void main() {
  const debounceDelay = Duration(milliseconds: 50);
  const settle = Duration(milliseconds: 120);

  late StubAdapter adapter;
  late TsundokuApi api;
  late ProviderContainer container;
  final sentPayloads = <Map<String, dynamic>>[];

  setUp(() {
    sentPayloads.clear();
    adapter = StubAdapter((options) {
      if (options.method == 'PUT' && options.path.endsWith('/progress')) {
        sentPayloads.add({
          'path': options.path,
          'currentProgress': options.data['currentProgress'],
        });
        return jsonBody(null, 200);
      }
      if (options.method == 'PUT' && options.path.endsWith('/status')) {
        sentPayloads.add({'path': options.path, 'status': options.data['status']});
        return jsonBody(null, 200);
      }
      return jsonBody(null);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  group('CardProgressState (step/debounce/promotion)', () {
    test('step: оптимистичный шаг → debounce PUT с payload 1-в-1', () async {
      var item = book();
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) => api.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: (_) {},
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);

      ctrl.step(1);
      expect(ctrl.value, 1);

      await Future<void>.delayed(settle);
      // ignore: avoid_print
      print('DIAG seen=${adapter.seen.map((o) => o.method + o.path).toList()} ctrlValue=${ctrl.value}');
      final put = adapter.seen.firstWhere(
          (o) => o.path == '/api/media/m1/progress' && o.method == 'PUT');
      expect(put.data, {'currentProgress': 1});
      expect(container.read(optimisticProgressProvider).entries['m1'], isNull,
          reason: 'сервер подтвердил — override снят');
    });

    test('burst кликов: дебаунс отправляет последнее значение', () async {
      var item = book();
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) => api.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: (_) {},
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);

      ctrl.step(1);
      ctrl.step(1);
      ctrl.step(1);
      expect(ctrl.value, 3);

      await Future<void>.delayed(settle);
      final progressPuts = adapter.seen
          .where((o) => o.path == '/api/media/m1/progress' && o.method == 'PUT')
          .toList();
      expect(progressPuts, hasLength(1),
          reason: 'bursts collapse: один PUT с итоговым значением');
      expect(progressPuts.single.data, {'currentProgress': 3});
    });

    test('promotion toast (rule 1): спецификация + optimistic статус', () async {
      var item = book();
      final toasts = <StatusPromotionToastSpec>[];
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) => api.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: toasts.add,
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);

      ctrl.step(1);
      expect(toasts.length, 1);
      expect(toasts.single.title, isNotEmpty);
      expect(toasts.single.durationMs, 8000);
      expect(toasts.single.showOk, isTrue);
      expect(toasts.single.actions.single.id, 'keepStatus');

      await Future<void>.delayed(settle);
      // Статус оптимистично переведён в InProgress (rule 1) и persisted:
      expect(sentPayloads.any((p) => p['status'] == 1), isTrue);
    });

    test('undo promotion: progress 0 + статус обратно, оба persist', () async {
      var item = book();
      final toasts = <StatusPromotionToastSpec>[];
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) => api.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: toasts.add,
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);

      ctrl.step(1);
      // Пользователь жмёт Undo ПОСЛЕ показа тоста:
      toasts.single.undo();
      await Future<void>.delayed(settle);

      expect(
          sentPayloads.any((p) =>
              p['path'] == '/api/media/m1/progress' &&
              p['currentProgress'] == 0),
          isTrue,
          reason: 'undo: PUT progress=0');
      expect(sentPayloads.any((p) => p['status'] == 0), isTrue,
          reason: 'undo: PUT status обратно на planned');
      expect(ctrl.value, 0);
    });

    test('keepStatus: progress остаётся, статус восстанавливается', () async {
      var item = book();
      final toasts = <StatusPromotionToastSpec>[];
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) => api.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: toasts.add,
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);

      ctrl.step(1);
      toasts.single.actions.single.onClick(); // keepStatus
      await Future<void>.delayed(settle);

      expect(sentPayloads.any((p) => p['status'] == 0), isTrue,
          reason: 'статус восстановлен');
      expect(
          sentPayloads.any((p) =>
              p['path'] == '/api/media/m1/progress' &&
              p['currentProgress'] == 1),
          isTrue,
          reason: 'прогресс персистится явно (дебаунс отменён)');
      expect(ctrl.value, 1);
    });

    test('ошибка сети: откат к snapshot, optimistic снят, error выставлен',
        () async {
      var item = book(currentPage: 2);
      final errorAdapter = StubAdapter((options) {
        if (options.path == '/api/media/m1/progress') {
          return jsonBody({'detail': 'network down'}, 500);
        }
        return jsonBody(null);
      });
      final errorDio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      errorDio.httpClientAdapter = errorAdapter;
      final errorApi = TsundokuApi(errorDio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(errorApi),
      ]);
      addTearDown(container.dispose);
      final ctrl = container.read(Provider<CardProgressState>((ref) {
        return CardProgressState(CardProgressOptions(
          getItem: () => item,
          getOnProgress: () => (id, value) =>
              errorApi.setProgress(id, value),
          getOnProgressCommitted: () => () {},
          showPromotionToast: (_) {},
          ref: container,
          delayOverride: debounceDelay,
        ));
      }));
      ctrl.onItemReplaced(item);
      ctrl.step(1);

      await Future<void>.delayed(settle);
      expect(ctrl.error, isA<ApiError>(), reason: 'ошибка выставлена');
      expect(ctrl.value, 2, reason: 'откат к pendingSnapshot (2)');
      expect(container.read(optimisticProgressProvider).entries.containsKey('m1'),
          isFalse, reason: 'clearOptimisticProgress при ошибке');
    });
  });

  group('CardStatusState (createCardStatus)', () {
    test('optimistic смена статуса: badge → PUT; не-dropped чистит причины',
        () async {
      var item = book()
          .copyWithFields(status: MediaStatus.completed, dropReason: 'boring');
      MediaItem? lastSeen;
      final ctrlState = container.read(Provider<CardStatusState>((ref) {
        return createCardStatus(CardStatusOptions(
          getItem: () => item,
          getOnStatusChange: () => (updated, newStatus) => lastSeen = updated,
          getOnProgressCommitted: () => () {},
          ref: container,
        ));
      }));

      await ctrlState.changeStatus(MediaStatus.inProgress);
      expect(lastSeen?.status, MediaStatus.inProgress);
      expect(lastSeen?.dropReason, isNull, reason: 'не-dropped чистит drop-поля');
      expect(sentPayloads.any((p) => p['status'] == 1), isTrue);
    });

    test('rule 2: уход из Completed сбрасывает прогресс оптимистично',
        () async {
      var item = book(currentPage: 120)
          .copyWithFields(status: MediaStatus.completed);
      MediaItem? lastSeen;
      final ctrlState = container.read(Provider<CardStatusState>((ref) {
        return createCardStatus(CardStatusOptions(
          getItem: () => item,
          getOnStatusChange: () => (updated, newStatus) => lastSeen = updated,
          getOnProgressCommitted: () => () {},
          ref: container,
        ));
      }));

      await ctrlState.changeStatus(MediaStatus.inProgress);
      expect(lastSeen?.currentPage, 0,
          reason: 'rule 2: leaving Completed сбрасывает прогресс');
    });

    test('ошибка PUT статуса: откат к прежнему статусу/прогрессу', () async {
      final errorAdapter = StubAdapter((options) {
        if (options.path.endsWith('/status')) {
          return jsonBody({'detail': 'forbidden'}, 403);
        }
        return jsonBody(null);
      });
      final errorDio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      errorDio.httpClientAdapter = errorAdapter;
      final errorApi = TsundokuApi(errorDio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(errorApi),
      ]);
      addTearDown(container.dispose);

      final original =
          book(currentPage: 120).copyWithFields(status: MediaStatus.completed);
      var item = original;
      MediaItem? lastSeen;
      final ctrlState = container.read(Provider<CardStatusState>((ref) {
        return createCardStatus(CardStatusOptions(
          getItem: () => item,
          getOnStatusChange: () => (updated, newStatus) {
            lastSeen = updated;
            // Имитация родительской мапы: item заменяется на присланную копию.
            item = updated;
          },
          getOnProgressCommitted: () => () {},
          ref: container,
        ));
      }));

      await ctrlState.changeStatus(MediaStatus.inProgress);
      expect(lastSeen?.status, MediaStatus.completed,
          reason: 'rollback к прежнему статусу');
      expect(lastSeen?.currentPage, 120,
          reason: 'rollback сброшенного прогресса (rule 2 revert)');
    });
  });
}
