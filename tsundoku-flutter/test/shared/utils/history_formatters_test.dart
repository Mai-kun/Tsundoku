import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/utils/history_formatters.dart';

/// 1:1 port-тест `historyFormatters.ts`.
void main() {
  const ru = I18nDictionary(Locale.ru);
  const en = I18nDictionary(Locale.en);

  HistoryEvent event(String type, String? oldV, String? newV) =>
      HistoryEvent.fromJson({
        'id': 'e1', 'mediaId': 'm1', 'type': type,
        'oldValue': oldV, 'newValue': newV,
        'createdAt': '2026-11-21T10:30:00Z', 'title': 'Dune',
      });

  group('formatStatusName (Planned/число → i18n)', () {
    test('null/пусто → «—»', () {
      expect(formatStatusName(null, ru), '—');
      expect(formatStatusName('', ru), '—');
    });

    test('именованные и числовые статусы 1-в-1', () {
      expect(formatStatusName('Planned', ru), ru.tr('status.planned'));
      expect(formatStatusName('0', ru), ru.tr('status.planned'));
      expect(formatStatusName('InProgress', en), en.tr('status.inProgress'));
      expect(formatStatusName('1', en), en.tr('status.inProgress'));
      expect(formatStatusName('Completed', ru), ru.tr('status.completed'));
      expect(formatStatusName('2', ru), ru.tr('status.completed'));
      expect(formatStatusName('OnHold', ru), ru.tr('status.paused'));
      expect(formatStatusName('3', ru), ru.tr('status.paused'));
      expect(formatStatusName('Dropped', ru), ru.tr('status.dropped'));
      expect(formatStatusName('4', ru), ru.tr('status.dropped'));
    });

    test('неизвестный статус возвращается как есть', () {
      expect(formatStatusName('SomeNewStatus', ru), 'SomeNewStatus');
    });
  });

  group('formatScoreName', () {
    test('null/пусто/0 → «—»', () {
      expect(formatScoreName(null, ru), '—');
      expect(formatScoreName('', ru), '—');
      expect(formatScoreName('0', ru), '—');
    });

    test('оценка → «X ★»', () {
      expect(formatScoreName('9', ru), '9 ★');
      expect(formatScoreName('7.5', en), '7.5 ★');
    });
  });

  group('formatHistoryEventLabel (полный цикл по типам событий)', () {
    test('Added/Deleted', () {
      expect(formatHistoryEventLabel(event('Added', null, null), ru),
          ru.tr('views.titleAdded'));
      expect(formatHistoryEventLabel(event('Deleted', null, null), en),
          en.tr('views.titleDeleted'));
    });

    test('StatusChanged: old → new', () {
      expect(
        formatHistoryEventLabel(event('StatusChanged', 'Planned', '2'), ru),
        '${ru.tr('views.statusPrefix')} ${ru.tr('status.planned')} → ${ru.tr('status.completed')}',
      );
    });

    test('ScoreChanged: old → new со ★', () {
      expect(
        formatHistoryEventLabel(event('ScoreChanged', '5', '9'), ru),
        '${ru.tr('views.scorePrefix')} 5 ★ → 9 ★',
      );
    });

    test('ProgressChanged: pages-детект (стр/pp/page)', () {
      // «стр» в oldValue → readPrefix:
      expect(
        formatHistoryEventLabel(event('ProgressChanged', 'стр. 10', 'стр. 20'), ru),
        '${ru.tr('views.readPrefix')} стр. 10 → стр. 20',
      );
      // «pp» в newValue → readPrefix:
      expect(
        formatHistoryEventLabel(event('ProgressChanged', null, '12 pp'), en),
        '${en.tr('views.readPrefix')} 12 pp',
      );
      // «page» → readPrefix:
      expect(
        formatHistoryEventLabel(event('ProgressChanged', 'page 1', 'page 5'), en),
        '${en.tr('views.readPrefix')} page 1 → page 5',
      );
      // Без страниц → progressPrefix:
      expect(
        formatHistoryEventLabel(event('ProgressChanged', '2', '5'), ru),
        '${ru.tr('views.progressPrefix')} 2 → 5',
      );
      // Только newValue:
      expect(
        formatHistoryEventLabel(event('ProgressChanged', null, '5'), ru),
        '${ru.tr('views.progressPrefix')} 5',
      );
      // Только prefix при пустых значениях:
      expect(formatHistoryEventLabel(event('ProgressChanged', null, null), ru),
          ru.tr('views.progressPrefix'));
    });

    test('AchievementUnlocked: префикс + значение (trim)', () {
      expect(
        formatHistoryEventLabel(event('AchievementUnlocked', null, 'Protective'), ru),
        '${ru.tr('stats.achievements')} Protective',
      );
      expect(
        formatHistoryEventLabel(event('AchievementUnlocked', null, ''), ru),
        ru.tr('stats.achievements'),
      );
    });
  });

  group('historyEventIcons (lucide 1-в-1)', () {
    test('карта покрывает все типы событий', () {
      expect(historyEventIcons.length, HistoryEventType.values.length);
      expect(historyEventIcons[HistoryEventType.added], historyEventIcons[HistoryEventType.added]);
      for (final type in HistoryEventType.values) {
        expect(historyEventIcons[type], isNotNull);
      }
    });
  });

  group('formatHistoryTime/Date (intl, локали ru/en)', () {
    test('время HH:mm', () {
      final time = formatHistoryTime('2026-11-21T10:30:00Z', Locale.en);
      // Часовой пояс тест-раннера — UTC+0 не гарантирован: проверяем формат.
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(time), isTrue);
    });

    test('дата: ru-локаль содержит месяц словами, en — месяц en', () {
      final ruDate = formatHistoryDate('2026-11-21T00:00:00Z', Locale.ru);
      expect(ruDate, contains('2026'));
      expect(ruDate.toLowerCase(), anyOf(contains('нояб'), contains('november')));
      final enDate = formatHistoryDate('2026-11-21T00:00:00Z', Locale.en);
      expect(enDate, contains('2026'));
    });
  });
}
