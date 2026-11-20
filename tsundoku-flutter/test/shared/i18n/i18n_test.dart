import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/i18n/translations.dart';

/// Полный цикл i18n: данные (1-в-1 leaves), resolve ru/en, функции,
/// массивы, persist-локаль (аналог localStorage).
void main() {
  // Подсчёт листьев дерева (страж регрессии генерации против TS-источника).
  int countLeaves(Map<String, Object> node) {
    var n = 0;
    for (final v in node.values) {
      if (v is Map<String, Object>) {
        if (v.containsKey('ru')) {
          n += 1;
        } else {
          n += countLeaves(v);
        }
      }
    }
    return n;
  }

  test('страж генерации: 1528 строковых + 16 массивных + 112 функциональных',
      () {
    expect(countLeaves(translations), 1528 + 16,
        reason: 'строковые + массивные листья должны совпадать с TS-файлом');
    expect(translationFunctions.length, 112,
        reason: 'функциональные листья должны совпадать с TS-файлом');
  });

  group('I18nDictionary.tr / tf / tl', () {
    test('tr: строковые листья 1-в-1 (ru/en)', () {
      const ru = I18nDictionary(Locale.ru);
      const en = I18nDictionary(Locale.en);
      expect(ru.tr('common.add'), 'Добавить');
      expect(en.tr('common.add'), 'Add');
      expect(ru.tr('errors.requestFailed'), isNotEmpty);
      expect(ru.tr('common.loading'), 'Загрузка…');
      expect(en.tr('common.loading'), 'Loading…');
    });

    test('tr: неизвестный путь → ArgumentError с путём', () {
      const ru = I18nDictionary(Locale.ru);
      expect(() => ru.tr('common.noSuchKey'), throwsArgumentError);
      expect(() => ru.tr('no.such.section'), throwsArgumentError);
    });

    test('tr: функциональный лист через tr() — ошибка с подсказкой tf()', () {
      const ru = I18nDictionary(Locale.ru);
      expect(
        () => ru.tr('views.yearSummaryCount'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('use tf()'),
          ),
        ),
      );
    });

    test('tf: plural-функция full cycle (ru склонения, en plural)', () {
      const ru = I18nDictionary(Locale.ru);
      const en = I18nDictionary(Locale.en);
      // Русские склонения (mod10/mod100 логика из исходника):
      expect(ru.tf('views.yearSummaryCount', [1]), '1 тайтл');
      expect(ru.tf('views.yearSummaryCount', [3]), '3 тайтла');
      expect(ru.tf('views.yearSummaryCount', [11]), '11 тайтлов');
      expect(ru.tf('views.yearSummaryCount', [21]), '21 тайтл');
      expect(ru.tf('views.yearSummaryCount', [100]), '100 тайтлов');
      // Английский plural:
      expect(en.tf('views.yearSummaryCount', [1]), '1 title');
      expect(en.tf('views.yearSummaryCount', [2]), '2 titles');
    });

    test(r'tf: интерполяция граничит с литеральной буквой (${sec}s)', () {
      const en = I18nDictionary(Locale.en);
      // `Reset in ${sec}s` — $sec + литеральная 's':
      expect(en.tf('activity.resetInSeconds', [30]), 'Reset in 30s');
    });

    test('tf: неизвестная функция → ArgumentError', () {
      const ru = I18nDictionary(Locale.ru);
      expect(() => ru.tf('no.such.fn', [1]), throwsArgumentError);
    });

    test('tl: массивные листья 1-в-1', () {
      const ru = I18nDictionary(Locale.ru);
      const en = I18nDictionary(Locale.en);
      expect(ru.tl('stats.taste.personas.action_junkie.traits'),
          ['Высокий темп', 'Драйв и зрелищность', 'Боевой дух']);
      expect(en.tl('stats.taste.personas.action_junkie.traits'),
          ['High tempo', 'Kinetic spectacle', 'Fighting spirit']);
    });

    test(r'tf: массивная функция-лист (readingFormatPresets)', () {
      const ru = I18nDictionary(Locale.ru);
      const en = I18nDictionary(Locale.en);
      expect(ru.tfl('detail.readingFormatPresets'),
          ['Электронная', 'Печатная', 'Аудиокнига']);
      expect(en.tfl('detail.readingFormatPresets'),
          ['E-book', 'Print', 'Audiobook']);
    });

    test('locales: только ru/en (как в исходнике)', () {
      expect(locales.map((l) => l.wire), ['ru', 'en']);
      expect(Locale.tryFromWire('de'), isNull);
    });
  });

  group('I18nController (persist, аналог localStorage)', () {
    test('default ru (нет stored / stored не en)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(i18nProvider.notifier);
      await ctrl.loadStored();
      expect(container.read(i18nProvider), Locale.ru);
    });

    test('stored en → en; setLocale persist; reload → persisted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(i18nProvider.notifier);

      await ctrl.loadStored();
      expect(container.read(i18nProvider), Locale.ru);

      await ctrl.setLocale(Locale.en);
      expect(container.read(i18nProvider), Locale.en);

      // Persist произошёл: новый контейнер читает 'en'.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(i18nProvider.notifier).loadStored();
      expect(container2.read(i18nProvider), Locale.en);
    });

    test(r'tProvider пересоздаёт словарь при смене локали (аналог $state)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(i18nProvider.notifier);
      await ctrl.loadStored();

      expect(container.read(tProvider).tr('common.cancel'), 'Отмена');
      await ctrl.setLocale(Locale.en);
      expect(container.read(tProvider).tr('common.cancel'), 'Cancel');
    });

    test('stored мусор → ru (localStorage.getItem !== "en")', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        storageKey: 'de',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(i18nProvider.notifier).loadStored();
      expect(container.read(i18nProvider), Locale.ru);
    });
  });
}
