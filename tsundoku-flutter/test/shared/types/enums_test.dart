import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

void main() {
  group('числовые статусы (1:1 с SYNC_STATUS / MEDIA_STATUS)', () {
    test('значения совпадают с Svelte-эталоном', () {
      expect(SyncStatus.ready.value, 0);
      expect(SyncStatus.syncing.value, 1);
      expect(SyncStatus.failed.value, 2);
      expect(SyncStatus.needsReview.value, 3);

      expect(MediaStatus.planned.value, 0);
      expect(MediaStatus.inProgress.value, 1);
      expect(MediaStatus.completed.value, 2);
      expect(MediaStatus.onHold.value, 3);
      expect(MediaStatus.dropped.value, 4);
    });

    test('round-trip value → enum → value', () {
      for (final s in SyncStatus.values) {
        expect(SyncStatus.tryValue(s.value), s);
      }
      for (final s in MediaStatus.values) {
        expect(MediaStatus.tryValue(s.value), s);
      }
    });

    test('неизвестное значение: tryValue → null, fromValue → ArgumentError', () {
      expect(SyncStatus.tryValue(99), isNull);
      expect(MediaStatus.tryValue(-1), isNull);
      expect(() => SyncStatus.fromValue(99), throwsArgumentError);
      expect(() => MediaStatus.fromValue(-1), throwsArgumentError);
    });
  });

  group('wire-enum\'ы (строковые union)', () {
    test('wire-строки 1:1 с сервером (JobStatus сериализуется по имени)', () {
      expect(JobStatus.queued.wire, 'Queued');
      expect(JobStatus.running.wire, 'Running');
      expect(JobStatus.completed.wire, 'Completed');
      expect(JobStatus.failed.wire, 'Failed');
      expect(JobStatus.cancelled.wire, 'Cancelled');

      expect(HistoryEventType.added.wire, 'Added');
      expect(HistoryEventType.statusChanged.wire, 'StatusChanged');
      expect(HistoryEventType.scoreChanged.wire, 'ScoreChanged');
      expect(HistoryEventType.progressChanged.wire, 'ProgressChanged');
      expect(HistoryEventType.deleted.wire, 'Deleted');
      expect(HistoryEventType.achievementUnlocked.wire, 'AchievementUnlocked');

      expect(SettingsTab.apiTokens.wire, 'apiTokens');
      expect(MediaType.tvshow.wire, 'tvshow');
      expect(SortBy.createdAt.wire, 'createdAt');
      expect(SortOrder.desc.wire, 'desc');
    });

    test('round-trip wire → enum → wire для всех значений', () {
      for (final s in JobStatus.values) {
        expect(JobStatus.tryFromWire(s.wire), s);
      }
      for (final s in HistoryEventType.values) {
        expect(HistoryEventType.tryFromWire(s.wire), s);
      }
      for (final s in SettingsTab.values) {
        expect(SettingsTab.tryFromWire(s.wire), s);
      }
      for (final s in MediaType.values) {
        expect(MediaType.tryFromWire(s.wire), s);
      }
      for (final s in SortBy.values) {
        expect(SortBy.tryFromWire(s.wire), s);
      }
      for (final s in SortOrder.values) {
        expect(SortOrder.tryFromWire(s.wire), s);
      }
    });

    test('неизвестный wire: tryFromWire → null, fromWire → ArgumentError', () {
      expect(JobStatus.tryFromWire('Zombie'), isNull);
      expect(MediaType.tryFromWire('series'), isNull);
      expect(() => MediaType.fromWire('series'), throwsArgumentError);
    });
  });

  group('JobProgress (полный цикл сериализации)', () {
    const json = <String, dynamic>{
      'jobId': 'job-1',
      'mediaId': 'media-42',
      'title': 'Труд в руки',
      'progressPercent': 57.5,
      'currentStep': 'Filling metadata',
      'status': 'Running',
      'startedAt': '2026-11-21T10:15:00Z',
      'errorMessage': null,
    };

    test('fromJson → toJson равен исходному payload', () {
      final parsed = JobProgress.fromJson(json);
      expect(parsed.toJson(), json);
    });

    test('парсинг полей 1:1', () {
      final parsed = JobProgress.fromJson(json);
      expect(parsed.jobId, 'job-1');
      expect(parsed.mediaId, 'media-42');
      expect(parsed.title, 'Труд в руки');
      expect(parsed.progressPercent, 57.5);
      expect(parsed.currentStep, 'Filling metadata');
      expect(parsed.status, JobStatus.running);
      expect(parsed.startedAt, '2026-11-21T10:15:00Z');
      expect(parsed.errorMessage, isNull);
    });

    test('целый progressPercent от сервера приводится к double', () {
      final parsed = JobProgress.fromJson({...json, 'progressPercent': 100});
      expect(parsed.progressPercent, 100.0);
      expect(parsed.status, JobStatus.running);
    });

    test('nullable mediaId/errorMessage', () {
      final parsed = JobProgress.fromJson({
        ...json,
        'mediaId': null,
        'errorMessage': 'boom',
        'status': 'Failed',
      });
      expect(parsed.mediaId, isNull);
      expect(parsed.errorMessage, 'boom');
      expect(parsed.status, JobStatus.failed);
      // Обратная сериализация сохраняет null-поля.
      expect(parsed.toJson()['mediaId'], isNull);
    });

    test('неизвестный статус job в payload — ArgumentError (fail fast)', () {
      expect(
        () => JobProgress.fromJson({...json, 'status': 'Zombie'}),
        throwsArgumentError,
      );
    });

    test('равенство и hashCode (пере-парсинг того же payload)', () {
      final a = JobProgress.fromJson(json);
      final b = JobProgress.fromJson(json);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('открытые union (AppView / SearchScope / StatusFilter)', () {
    test('StatusFilter.all vs статус', () {
      const all = StatusFilter.all();
      expect(all.isAll, isTrue);
      expect(all.status, isNull);

      final byEnum = StatusFilter.of(MediaStatus.inProgress);
      expect(byEnum.status, 1);
      expect(byEnum.isAll, isFalse);
      expect(byEnum, const StatusFilter.status(1));
      expect(all == byEnum, isFalse);
    });

    test('knownSearchScopes содержит все media types + anime + all', () {
      expect(knownSearchMediaTypes, <String>{
        'game', 'movie', 'tvshow', 'book', 'manga', 'anime',
      });
      expect(knownSearchScopes.contains('all'), isTrue);
    });

    test('AppView — открытый union: builtin набор + свободные slug', () {
      expect(AppViews.builtin.contains('home'), isTrue);
      expect(AppViews.builtin.contains('game'), isTrue);
      expect(AppViews.builtin.contains('stats'), isTrue);
      expect(AppViews.builtin.contains('detail'), isTrue);
      // Slug пользовательской категории ("comics") не builtin, но валиден.
      const AppView slug = 'comics';
      expect(AppViews.builtin.contains(slug), isFalse);
    });
  });
}
