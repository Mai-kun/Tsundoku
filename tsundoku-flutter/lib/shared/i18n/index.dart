/// 1:1 port of `mediatracker-ui/src/shared/i18n/index.svelte.ts`.
///
/// Svelte-5 `$state` → Riverpod; `localStorage` → `shared_preferences`
/// (тот же ключ `tsundoku_lang`, дефолт `ru`, значения только `ru`/`en`).
///
/// Доступ к строкам: TS-синтаксис `i18n.t.errors.requestFailed` в Dart
/// выражается path-доступом `t.tr('errors.requestFailed')` (решение #8),
/// параметризованные листья — `t.tf('views.yearSummaryCount', [1])`.
/// `syncDocumentLang` (DOM `document.lang`) не имеет Flutter-аналога — локаль
/// приложения задаётся через MaterialApp в Фазе 3 (решение #8, пояснение).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

/// `type Locale = "ru" | "en"`.
enum Locale {
  ru('ru'),
  en('en');

  final String wire;
  const Locale(this.wire);

  static Locale? tryFromWire(String wire) {
    for (final l in values) {
      if (l.wire == wire) return l;
    }
    return null;
  }
}

/// `export const locales: readonly Locale[] = ["ru", "en"];`
const List<Locale> locales = <Locale>[Locale.ru, Locale.en];

/// Ключ persisted-локали (аналог `localStorage`-ключа).
const String storageKey = 'tsundoku_lang';

/// Словарь одной локали: развёрнутый доступ к paired-дереву translations.
/// В Svelte словарь кэшировался полностью; здесь resolve — 2-3 шага по Map,
/// что дешевле кэша (YAGNI), данные те же.
class I18nDictionary {
  final Locale locale;

  const I18nDictionary(this.locale);

  /// Строковый лист: `i18n.t.errors.requestFailed` → `tr('errors.requestFailed')`.
  String tr(String path) {
    final leaf = _leaf(path);
    return leaf[locale.wire] as String;
  }

  /// Массивный лист (`string[]`).
  List<String> tl(String path) {
    final leaf = _leaf(path);
    return (leaf[locale.wire] as List<Object?>).cast<String>().toList();
  }

  /// Функциональный лист (параметризованная строка):
  /// `i18n.t.mediaDetail.episodesCount(n)` → `tf('mediaDetail.episodesCount', [n])`.
  String tf(String path, [List<Object?> args = const <Object?>[]]) {
    final entry = translationFunctions[path];
    if (entry == null) {
      throw ArgumentError.value(
          path, 'path', 'unknown i18n function leaf');
    }
    final fn = entry[locale.wire] as Function;
    return Function.apply(fn, args) as String;
  }

  /// Функциональный лист, возвращающий список строк.
  List<String> tfl(String path, [List<Object?> args = const <Object?>[]]) {
    final entry = translationFunctions[path];
    if (entry == null) {
      throw ArgumentError.value(
          path, 'path', 'unknown i18n function leaf');
    }
    final fn = entry[locale.wire] as Function;
    return (Function.apply(fn, args) as List<Object?>)
        .cast<String>()
        .toList();
  }

  Map<String, Object?> _leaf(String path) {
    // Функции живут в отдельном реестре, но tr/tf пути едины.
    if (translationFunctions.containsKey(path)) {
      throw ArgumentError.value(
          path, 'path', 'i18n function leaf — use tf() instead of tr()');
    }
    Object? node = translations;
    for (final part in path.split('.')) {
      if (node is! Map<String, Object?>) {
        throw ArgumentError.value(
            path, 'path', 'unknown i18n path (no such node "$part")');
      }
      node = node[part];
      if (node == null) {
        throw ArgumentError.value(
            path, 'path', 'unknown i18n path (no such key "$part")');
      }
    }
    return node as Map<String, Object?>;
  }
}

/// Сервис локали (аналог `class I18nService`): `current` — Riverpod state.
class I18nController extends Notifier<Locale> {
  @override
  Locale build() => Locale.ru;

  /// `readStoredLocale()`: stored === 'en' ? en : ru (async, т.к. SharedPreferences).
  Future<void> loadStored() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(storageKey) == Locale.en.wire
        ? Locale.en
        : Locale.ru;
  }

  /// `setLocale`: обновить state + persist (localStorage.setItem-аналог).
  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, locale.wire);
  }
}

/// `export const i18n = new I18nService();`
final i18nProvider =
    NotifierProvider<I18nController, Locale>(I18nController.new);

/// `get t(): Dictionary` — словарь текущей локали; пересоздаётся при смене
/// локали (все читающие виджеты перестраиваются — аналог $state-графа).
final tProvider = Provider<I18nDictionary>((ref) {
  return I18nDictionary(ref.watch(i18nProvider));
});
