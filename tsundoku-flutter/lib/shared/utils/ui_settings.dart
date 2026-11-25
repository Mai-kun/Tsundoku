/// 1:1 port of `mediatracker-ui/src/shared/utils/uiSettings.svelte.ts`.
///
/// $state-поля → единый Riverpod-стейт [UiSettingsState]; localStorage →
/// shared_preferences (те же ключи `tsundoku_*`); applyAppIcon/applyTheme —
/// браузерные DOM-манипуляции, в Flutter не нужны (решение #13: иконка
/// приложения/тема применяются в AppShell через TsundokuTheme).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';

const String _prefix = 'tsundoku_';
const Set<String> _detailViews = <String>{'detail', 'seasons'};

const String _bookPageMinutesKey = 'tsundoku_reading_book_page_minutes';
const String _mangaChapterMinutesKey = 'tsundoku_reading_manga_chapter_minutes';
const String _castSizeByCategoryKey = 'tsundoku_cast_size_by_category';
const String _staffSizeByCategoryKey = 'tsundoku_staff_size_by_category';
const String _onCloseActionKey = 'tsundoku_on_close_action';
const String _voiceOptionMemoryKey = 'tsundoku_voice_option_memory';

const double defaultBookPageMinutes = 1.5;
const double defaultMangaChapterMinutes = 6.0;

/// `type PeopleCardSize = "compact" | "large"`.
enum PeopleCardSize {
  compact('compact'),
  large('large');

  final String wire;
  const PeopleCardSize(this.wire);

  static PeopleCardSize? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// `type OnCloseAction = "tray" | "exit" | "ask"`.
enum OnCloseActionPref {
  tray('tray'),
  exit('exit'),
  ask('ask');

  final String wire;
  const OnCloseActionPref(this.wire);

  static OnCloseActionPref? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// `type VoiceOptionScope = "watch" | "read"`.
enum VoiceOptionScope {
  watch('watch'),
  read('read');

  final String wire;
  const VoiceOptionScope(this.wire);
}

/// User-remembered combobox options: values the user typed themselves plus
/// their starred picks.
@immutable
class VoiceOptionMemory {
  final List<String> custom;
  final List<String> favorites;

  const VoiceOptionMemory({
    this.custom = const <String>[],
    this.favorites = const <String>[],
  });

  factory VoiceOptionMemory.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return const VoiceOptionMemory();
    List<String> pick(Object? list) => list is List
        ? list.whereType<String>().toList()
        : const <String>[];
    final custom = raw['custom'];
    final favorites = raw['favorites'];
    return VoiceOptionMemory(
      custom: pick(custom),
      favorites: pick(favorites),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'custom': custom,
        'favorites': favorites,
      };

  @override
  bool operator ==(Object other) =>
      other is VoiceOptionMemory &&
      other.custom.toString() == custom.toString() &&
      other.favorites.toString() == favorites.toString();

  @override
  int get hashCode => Object.hash(custom, favorites);
}

@immutable
class VoiceOptionMemoryMap {
  final VoiceOptionMemory watch;
  final VoiceOptionMemory read;

  const VoiceOptionMemoryMap({
    this.watch = const VoiceOptionMemory(),
    this.read = const VoiceOptionMemory(),
  });

  VoiceOptionMemory byScope(VoiceOptionScope scope) =>
      scope == VoiceOptionScope.watch ? watch : read;

  VoiceOptionMemoryMap copyWith({
    VoiceOptionMemory? watch,
    VoiceOptionMemory? read,
  }) =>
      VoiceOptionMemoryMap(
        watch: watch ?? this.watch,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'watch': watch.toJson(),
        'read': read.toJson(),
      };
}

/// `type PeopleSizeMap = Record<string, PeopleCardSize>`.
typedef PeopleSizeMap = Map<String, PeopleCardSize>;

/// Иммутабельный снимок всех $state-полей UiSettingsService.
@immutable
class UiSettingsState {
  final String lastView;
  final bool groupByType;
  final String sortOption;
  final String statusFilter;
  final double bookPageMinutes;
  final double mangaChapterMinutes;
  final PeopleSizeMap castSizeByCategory;
  final PeopleSizeMap staffSizeByCategory;
  /// `"completed" | "all"`.
  final String statsScope;
  final OnCloseActionPref onCloseAction;
  final VoiceOptionMemoryMap voiceOptionMemory;
  final String appIcon;
  /// Color theme id (`ThemeId = "obsidian"`).
  final String theme;
  final bool isLoaded;

  const UiSettingsState({
    this.lastView = 'home',
    this.groupByType = false,
    this.sortOption = 'newest',
    this.statusFilter = 'all',
    this.bookPageMinutes = defaultBookPageMinutes,
    this.mangaChapterMinutes = defaultMangaChapterMinutes,
    this.castSizeByCategory = const <String, PeopleCardSize>{},
    this.staffSizeByCategory = const <String, PeopleCardSize>{},
    this.statsScope = 'completed',
    this.onCloseAction = OnCloseActionPref.tray,
    this.voiceOptionMemory = const VoiceOptionMemoryMap(),
    this.appIcon = 'default',
    this.theme = 'obsidian',
    this.isLoaded = false,
  });

  UiSettingsState copyWith({
    String? lastView,
    bool? groupByType,
    String? sortOption,
    String? statusFilter,
    double? bookPageMinutes,
    double? mangaChapterMinutes,
    PeopleSizeMap? castSizeByCategory,
    PeopleSizeMap? staffSizeByCategory,
    String? statsScope,
    OnCloseActionPref? onCloseAction,
    VoiceOptionMemoryMap? voiceOptionMemory,
    String? appIcon,
    String? theme,
    bool? isLoaded,
  }) =>
      UiSettingsState(
        lastView: lastView ?? this.lastView,
        groupByType: groupByType ?? this.groupByType,
        sortOption: sortOption ?? this.sortOption,
        statusFilter: statusFilter ?? this.statusFilter,
        bookPageMinutes: bookPageMinutes ?? this.bookPageMinutes,
        mangaChapterMinutes: mangaChapterMinutes ?? this.mangaChapterMinutes,
        castSizeByCategory: castSizeByCategory ?? this.castSizeByCategory,
        staffSizeByCategory: staffSizeByCategory ?? this.staffSizeByCategory,
        statsScope: statsScope ?? this.statsScope,
        onCloseAction: onCloseAction ?? this.onCloseAction,
        voiceOptionMemory: voiceOptionMemory ?? this.voiceOptionMemory,
        appIcon: appIcon ?? this.appIcon,
        theme: theme ?? this.theme,
        isLoaded: isLoaded ?? this.isLoaded,
      );
}

class UiSettingsController extends Notifier<UiSettingsState> {
  final SharedPreferences? _initialPrefs;

  UiSettingsController([this._initialPrefs]);

  @override
  UiSettingsState build() {
    ref.onDispose(disposeWatchers);
    final prefs = _initialPrefs;
    if (prefs != null) {
      return _readStateFromPrefs(prefs, const UiSettingsState());
    }
    return const UiSettingsState();
  }

  // ------------------------------------------------------------------
  // SharedPreferences-хранилище (аналог private read/write).
  // ------------------------------------------------------------------

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  T _read<T>(SharedPreferences prefs, String key, T fallback) {
    try {
      final raw = prefs.getString(_prefix + key);
      if (raw == null) return fallback;
      return jsonDecode(raw) as T;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _write<T>(String key, T value) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_prefix + key, jsonEncode(value));
    } catch (_) {
      // try/catch {} из исходника.
    }
  }

  PeopleSizeMap _readStoredMap(
    SharedPreferences prefs,
    String key, {
    String? legacyKey,
  }) {
    try {
      final parsed = prefs.getString(key) ??
          (legacyKey != null ? prefs.getString(legacyKey) : null);
      if (parsed == null) return <String, PeopleCardSize>{};
      final decoded = jsonDecode(parsed);
      if (decoded is! Map<String, dynamic>) return <String, PeopleCardSize>{};
      return decoded.map((k, v) => MapEntry(
          k,
          PeopleCardSize.tryFromWire(v as String? ?? '') ??
              PeopleCardSize.large));
    } catch (_) {
      // Unreadable payload: fall through to an empty map.
      return <String, PeopleCardSize>{};
    }
  }

  Future<void> _writeStoredMap(String key, PeopleSizeMap value) async {
    final prefs = await _prefs();
    await prefs.setString(key, jsonEncode(
      value.map((k, v) => MapEntry(k, v.wire)),
    ));
  }

  VoiceOptionMemoryMap _readVoiceOptionMemory(SharedPreferences prefs) {
    try {
      final parsed = prefs.getString(_voiceOptionMemoryKey);
      final decoded =
          parsed == null ? null : jsonDecode(parsed) as Map<String, dynamic>?;
      if (decoded == null) return const VoiceOptionMemoryMap();
      return VoiceOptionMemoryMap(
        watch: VoiceOptionMemory.fromJson(decoded['watch']),
        read: VoiceOptionMemory.fromJson(decoded['read']),
      );
    } catch (_) {
      return const VoiceOptionMemoryMap();
    }
  }

  Future<void> _writeVoiceOptionMemory() async {
    final prefs = await _prefs();
    await prefs.setString(
        _voiceOptionMemoryKey, jsonEncode(state.voiceOptionMemory.toJson()));
  }

  UiSettingsState _readStateFromPrefs(
    SharedPreferences prefs,
    UiSettingsState base,
  ) {
    return base.copyWith(
      lastView: _read<String>(prefs, 'last_view', 'home'),
      groupByType: _read<bool>(prefs, 'group_by_type', false),
      sortOption: _read<String>(prefs, 'sort_option', 'newest'),
      statusFilter: _read<String>(prefs, 'status_filter', 'all'),
      bookPageMinutes:
          _readStoredNumber(prefs, _bookPageMinutesKey, defaultBookPageMinutes),
      mangaChapterMinutes: _readStoredNumber(
          prefs, _mangaChapterMinutesKey, defaultMangaChapterMinutes),
      castSizeByCategory: _readStoredMap(
        prefs,
        _castSizeByCategoryKey,
        legacyKey: 'tsundoku_cast_size',
      ),
      staffSizeByCategory: _readStoredMap(
        prefs,
        _staffSizeByCategoryKey,
        legacyKey: 'tsundoku_staff_size',
      ),
      statsScope: prefs.getString('stats_scope') == 'all' ? 'all' : 'completed',
      onCloseAction: OnCloseActionPref.tryFromWire(
              prefs.getString(_onCloseActionKey) ?? '') ??
          OnCloseActionPref.tray,
      voiceOptionMemory: _readVoiceOptionMemory(prefs),
      appIcon: _read<String>(prefs, 'app_icon', 'default'),
      theme: prefs.getString('$_prefix' 'theme') == 'obsidian'
          ? 'obsidian'
          : 'obsidian',
    );
  }

  /// Асинхронная инициализация из persisted-значений + сервера (аналог
  /// конструктора с read*/load()).
  Future<void> loadPersisted() async {
    final prefs = await _prefs();
    state = _readStateFromPrefs(prefs, state);
    await load();
  }

  double _readStoredNumber(SharedPreferences prefs, String key, double fallback) {
    final val = prefs.getString(key);
    if (val == null || val.isEmpty) return fallback;
    final num = double.tryParse(val);
    return (num == null || num <= 0) ? fallback : num;
  }

  // ------------------------------------------------------------------
  // Setters (write → persist).
  // ------------------------------------------------------------------

  /// setLastView: DETAIL_VIEWS не пишутся (deep-link поверх restored view).
  Future<void> setLastView(String view) async {
    if (_detailViews.contains(view)) return;
    state = state.copyWith(lastView: view);
    await _write('last_view', view);
  }

  Future<void> setGroupByType(bool enabled) async {
    state = state.copyWith(groupByType: enabled);
    await _write('group_by_type', enabled);
  }

  Future<void> setSortOption(String sort) async {
    state = state.copyWith(sortOption: sort);
    await _write('sort_option', sort);
  }

  Future<void> setStatusFilter(String filter) async {
    state = state.copyWith(statusFilter: filter);
    await _write('status_filter', filter);
  }

  Future<void> setStatsScope(String scope) async {
    state = state.copyWith(statsScope: scope);
    final prefs = await _prefs();
    await prefs.setString('stats_scope', scope);
  }

  Future<void> setOnCloseAction(OnCloseActionPref value) async {
    state = state.copyWith(onCloseAction: value);
    final prefs = await _prefs();
    await prefs.setString(_onCloseActionKey, value.wire);
  }

  Future<void> setAppIcon(String iconId) async {
    state = state.copyWith(appIcon: iconId);
    await _write('app_icon', iconId);
    // applyAppIcon: favicon/DOM-манипуляции web — во Flutter не применимы.
  }

  Future<void> setTheme(String theme) async {
    state = state.copyWith(theme: theme);
    final prefs = await _prefs();
    await prefs.setString('$_prefix' 'theme', theme);
    // applyTheme: html[data-theme] — во Flutter применяет TsundokuTheme
    // (AppShell смотрит на theme-поле).
  }

  PeopleCardSize getCastSize(String category) =>
      state.castSizeByCategory[category] ?? PeopleCardSize.large;

  Future<void> setCastSize(String category, PeopleCardSize size) async {
    final next = <String, PeopleCardSize>{...state.castSizeByCategory, category: size};
    state = state.copyWith(castSizeByCategory: next);
    await _writeStoredMap(_castSizeByCategoryKey, next);
  }

  PeopleCardSize getStaffSize(String category) =>
      state.staffSizeByCategory[category] ?? PeopleCardSize.large;

  Future<void> setStaffSize(String category, PeopleCardSize size) async {
    final next = <String, PeopleCardSize>{...state.staffSizeByCategory, category: size};
    state = state.copyWith(staffSizeByCategory: next);
    await _writeStoredMap(_staffSizeByCategoryKey, next);
  }

  VoiceOptionMemory getVoiceOptions(VoiceOptionScope scope) =>
      state.voiceOptionMemory.byScope(scope);

  /// A user-applied value lands in the permanent list and is starred
  /// automatically.
  Future<void> rememberVoiceOption(VoiceOptionScope scope, String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return;
    final current = state.voiceOptionMemory.byScope(scope);
    if (current.favorites.contains(value)) return;
    final next = VoiceOptionMemory(
      custom: current.custom.contains(value)
          ? current.custom
          : [...current.custom, value],
      favorites: [...current.favorites, value],
    );
    state = state.copyWith(
      voiceOptionMemory: scope == VoiceOptionScope.watch
          ? state.voiceOptionMemory.copyWith(watch: next)
          : state.voiceOptionMemory.copyWith(read: next),
    );
    await _writeVoiceOptionMemory();
  }

  Future<void> toggleVoiceFavorite(VoiceOptionScope scope, String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return;
    final current = state.voiceOptionMemory.byScope(scope);
    final isFavorite = current.favorites.contains(value);
    final next = VoiceOptionMemory(
      custom: (isFavorite || current.custom.contains(value))
          ? current.custom
          : [...current.custom, value],
      favorites: isFavorite
          ? current.favorites.where((v) => v != value).toList()
          : [...current.favorites, value],
    );
    state = state.copyWith(
      voiceOptionMemory: scope == VoiceOptionScope.watch
          ? state.voiceOptionMemory.copyWith(watch: next)
          : state.voiceOptionMemory.copyWith(read: next),
    );
    await _writeVoiceOptionMemory();
  }

  // ------------------------------------------------------------------
  // load() — серверные ReadingSettings перекрывают persisted-значения.
  // ------------------------------------------------------------------

  Future<void> load() async {
    try {
      final data = await ref.read(apiClientProvider).getReadingSettings();
      var bookPageMinutes = state.bookPageMinutes;
      var mangaChapterMinutes = state.mangaChapterMinutes;
      if (data.bookPageMinutes > 0) {
        bookPageMinutes = data.bookPageMinutes.toDouble();
        final prefs = await _prefs();
        await prefs.setString(_bookPageMinutesKey, '${data.bookPageMinutes}');
      }
      if (data.mangaChapterMinutes > 0) {
        mangaChapterMinutes = data.mangaChapterMinutes.toDouble();
        final prefs = await _prefs();
        await prefs.setString(_mangaChapterMinutesKey, '${data.mangaChapterMinutes}');
      }
      state = state.copyWith(
        bookPageMinutes: bookPageMinutes,
        mangaChapterMinutes: mangaChapterMinutes,
      );
    } catch (_) {
      // Keep localStorage / default values if backend is unreachable.
    } finally {
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<ReadingSettings> setReadingSpeed(
      double bookPageMinutes, double mangaChapterMinutes) async {
    state = state.copyWith(
      bookPageMinutes: bookPageMinutes,
      mangaChapterMinutes: mangaChapterMinutes,
    );
    final prefs = await _prefs();
    await prefs.setString(_bookPageMinutesKey, '$bookPageMinutes');
    await prefs.setString(_mangaChapterMinutesKey, '$mangaChapterMinutes');
    return ref
        .read(apiClientProvider)
        .saveReadingSettings(ReadingSettings(
          bookPageMinutes: bookPageMinutes.toInt(),
          mangaChapterMinutes: mangaChapterMinutes.toInt(),
        ));
  }

  void disposeWatchers() {}
}

final uiSettingsProvider =
    NotifierProvider<UiSettingsController, UiSettingsState>(
        UiSettingsController.new);
