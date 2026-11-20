/// 1:1 port of `mediatracker-ui/src/shared/api/navigationCategories.svelte.ts`.
///
/// $state.raw → Riverpod Notifier; иконки — прямое использование
/// `lucide_icons_flutter` (Icons.ts → ⏭️ Заменено нативно).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart' show IconData;

import '../types/models.dart';
import 'api.dart';

/// Вынесенная категория навигации («Комиксы», «Ранобэ») — виртуальный раздел
/// сайдбара, вынесенный из родительского типа медиа. Пока категория активна,
/// её элементы не показываются внутри родителя: фильтрация происходит на
/// сервере (SQL), а на Главной — этим же матчером.
/// Серверная часть: Features/Settings/NavigationCategories.
class PromotedSubcategory {
  /// Slug в навигации: "comics", "light-novels".
  final String id;
  final String label;
  final String icon;
  /// Канонический MediaType сервера: "Book", "Manga", "Game", "TvShow", "Movie".
  final String parentType;
  /// "format" | "genre" | "tag".
  final String matchKind;
  final String matchValue;

  const PromotedSubcategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.parentType,
    required this.matchKind,
    required this.matchValue,
  });

  factory PromotedSubcategory.fromJson(Map<String, dynamic> json) =>
      PromotedSubcategory(
        id: json['id'] as String,
        label: json['label'] as String,
        icon: json['icon'] as String,
        parentType: json['parentType'] as String,
        matchKind: json['matchKind'] as String,
        matchValue: json['matchValue'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'icon': icon,
        'parentType': parentType,
        'matchKind': matchKind,
        'matchValue': matchValue,
      };

  @override
  bool operator ==(Object other) =>
      other is PromotedSubcategory && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// `let categories = $state.raw<PromotedSubcategory[]>([])`.
class NavigationCategoriesController extends Notifier<List<PromotedSubcategory>> {
  bool _loaded = false;
  Future<void>? _loadPromise;

  @override
  List<PromotedSubcategory> build() => const <PromotedSubcategory>[];

  bool get isLoaded => _loaded;

  /// Реактивный список активных категорий (порядок = порядок в сайдбаре).
  List<PromotedSubcategory> promotedCategories() => state;

  PromotedSubcategory? promotedCategoryById(String id) {
    for (final c in state) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<List<PromotedSubcategory>> loadNavigationCategories(
      {bool force = false}) async {
    if (_loaded && !force) return state;
    if (_loadPromise == null || force) {
      _loadPromise = () async {
        final api = ref.read(apiClientProvider);
        final response = await api.requestJson<List<PromotedSubcategory>>(
          '/api/settings/navigation-categories',
          parse: (json) => (json as List<dynamic>)
              .map((e) => PromotedSubcategory.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
        state = response;
        _loaded = true;
      }();
    }
    await _loadPromise;
    return state;
  }

  Future<List<PromotedSubcategory>> saveNavigationCategories(
      List<PromotedSubcategory> list) async {
    final api = ref.read(apiClientProvider);
    try {
      state = await api.requestJson<List<PromotedSubcategory>>(
        '/api/settings/navigation-categories',
        method: 'PUT',
        body: {'categories': list.map((c) => c.toJson()).toList()},
        contentType: 'application/json',
        parse: (json) => (json as List<dynamic>)
            .map((e) => PromotedSubcategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      _loaded = true;
      // Активные категории меняют состав «Книг» и других родителей —
      // серверные кэши списков на клиенте сбрасываются, вьюхи пересобирают
      // выборки через свой provider-эффект на promotedCategories.
      api.invalidateSourcesCache();
      return state;
    } on DioException catch (error) {
      // Ошибка сервера: достаём detail из ProblemDetails (как в исходнике).
      String detail = 'navigation-categories: ${error.response?.statusCode ?? 0}';
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] is String) {
        detail = data['detail'] as String;
      }
      throw Exception(detail);
    }
  }
}

final navigationCategoriesProvider =
    NotifierProvider<NavigationCategoriesController, List<PromotedSubcategory>>(
        NavigationCategoriesController.new);

/// Родительский MediaType в нижнем регистре — как его ждут MediaFilters
/// ("book").
String promotedParentType(PromotedSubcategory sub) =>
    sub.parentType.toLowerCase();

List<String> _asList(List<String>? value) => value ?? const <String>[];

String _normalizeListValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Клиентский матчер — тот же контракт, что и SQL-фрагмент
/// PromotedSubcategorySql.
bool matchesSubcategory(MediaItem item, PromotedSubcategory sub) {
  if (item.type.wire != promotedParentType(sub)) return false;

  switch (sub.matchKind) {
    case 'format':
      return (item.format ?? '').toLowerCase() ==
          sub.matchValue.trim().toLowerCase();
    case 'genre':
      final needle = _normalizeListValue(sub.matchValue);
      return _asList(item.genres).any((g) => _normalizeListValue(g) == needle);
    case 'tag':
      final needle = _normalizeListValue(sub.matchValue);
      return _asList(item.tags).any((t) => _normalizeListValue(t) == needle);
    default:
      return false;
  }
}

/// Вынесенная категория, в которую попадает элемент (первая совпавшая), или
/// null.
PromotedSubcategory? promotedCategoryOfItem(
    MediaItem item, List<PromotedSubcategory> categories) {
  for (final sub in categories) {
    if (matchesSubcategory(item, sub)) return sub;
  }
  return null;
}

/// Согласованный набор иконок для вынесенных категорий (имя из конфига →
/// IconData из lucide_icons_flutter; Icons.ts ⏭️ заменён нативно).
const Map<String, IconData> promotedIcons = <String, IconData>{
  'bookmark': LucideIcons.bookmark,
  'book-open': LucideIcons.bookOpen,
  'clapperboard': LucideIcons.clapperboard,
  'gamepad': LucideIcons.gamepad2,
  'library': LucideIcons.library,
  'sparkle': LucideIcons.sparkles,
  'tv': LucideIcons.tv,
};

/// `promotedIcon(name)`: имя из конфига → IconData, fallback — bookmark.
IconData promotedIcon(String name) => promotedIcons[name] ?? LucideIcons.bookmark;

/// Готовые пресеты для быстрых кнопок в настройках.
const List<PromotedSubcategory> promotedPresets = <PromotedSubcategory>[
  PromotedSubcategory(
    id: 'comics',
    label: 'Комиксы',
    icon: 'bookmark',
    parentType: 'Book',
    matchKind: 'format',
    matchValue: 'comics',
  ),
  PromotedSubcategory(
    id: 'light-novels',
    label: 'Ранобэ',
    icon: 'sparkle',
    parentType: 'Book',
    matchKind: 'format',
    matchValue: 'light_novel',
  ),
];
