import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_label.dart';

void main() {
  test('реэкспорт genreLabel возвращает локализованные жанры', () {
    const ruT = I18nDictionary(Locale.ru);
    const enT = I18nDictionary(Locale.en);
    expect(genreLabel('action', ruT, Locale.ru), 'Боевик');
    expect(genreLabel('action', enT, Locale.en), 'Action');
    expect(genreLabel('comedy', ruT, Locale.ru), 'Комедия');
    expect(genreLabel('custom_unknown_genre', ruT, Locale.ru), 'custom_unknown_genre');
  });
}
