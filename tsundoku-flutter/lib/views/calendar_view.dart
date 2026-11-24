/// 1:1 port of `mediatracker-ui/src/views/CalendarView.svelte`.
///
/// Экран календаря релизов и обновлений:
/// - Секция дедлайнов бэклога («Успеть к релизу», горизонт 30 дней)
/// - Панель управления: переключение месяца (< Название > с возвратом на сегодня),
///   фильтры категорий и типов событий, кнопка сброса, экспорт .ICS,
///   переключатель режима ячеек (Обложки / Значки в режиме сетки),
///   переключатель вида (Сетка месяца / Лента ближайших)
/// - Режим Ленты: группировка по дням с бейджами «Сегодня» / «Завтра»,
///   карточки тайтлов с постерами, прогрессом, бейджами событий и кнопкой автопроверки
/// - Режим Сетки: календарь 7 колонок (Пн..Вс) с переливающимися стопками обложек или
///   иконками категорий, боковая панель выбранного дня с релизом, сериями и проверками
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/api/api.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/dtos.dart';
import '../shared/ui/media_cover_placeholder.dart';
import '../shared/ui/tsundoku_image.dart';
import '../shared/ui/popover_menu.dart';
import '../shared/ui/toast.dart';

class CalendarView extends ConsumerStatefulWidget {
  final ValueChanged<String>? onOpenMedia;

  const CalendarView({
    super.key,
    this.onOpenMedia,
  });

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  String _mode = 'feed'; // 'feed' | 'grid'
  String _cellMode = 'posters'; // 'posters' | 'icons'

  late int _viewYear;
  late int _viewMonthIndex; // 0..11
  String? _selectedDay; // 'yyyy-MM-dd' or null

  String _kindFilter = 'all';
  String _typeFilter = 'all';

  CalendarScheduleDto? _schedule;
  bool _isLoading = false;
  Object? _loadError;

  List<BacklogDeadlineDto> _backlogItems = const [];
  bool _isExportingIcs = false;
  Set<String> _checkingIds = const {};
  final Set<String> _brokenCovers = {};

  int _fetchRequestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonthIndex = now.month - 1;

    _loadBacklogDeadlines();
    _loadSchedule();
  }

  String get _todayStr {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }

  String get _tomorrowStr {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateFormat('yyyy-MM-dd').format(tomorrow);
  }

  // ── Network: Backlog Deadlines ──────────────────────────────────────────
  Future<void> _loadBacklogDeadlines() async {
    try {
      final items = await ref.read(apiClientProvider).getBacklogDeadlines();
      if (!mounted) return;
      setState(() => _backlogItems = items);
    } catch (_) {}
  }

  // ── Network: Schedule ───────────────────────────────────────────────────
  Future<void> _loadSchedule() async {
    final requestId = ++_fetchRequestId;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final from = _isoDate(_viewYear, _viewMonthIndex, 1);
    final lastDay = DateTime(_viewYear, _viewMonthIndex + 2, 0).day;
    final to = _isoDate(_viewYear, _viewMonthIndex, lastDay);

    try {
      final result =
          await ref.read(apiClientProvider).getCalendar(from: from, to: to);
      if (!mounted || _fetchRequestId != requestId) return;

      setState(() {
        _schedule = result;
        _isLoading = false;
      });
      _autoSelectGridDay(result, _viewYear, _viewMonthIndex);
    } catch (err) {
      if (!mounted || _fetchRequestId != requestId) return;
      setState(() {
        _loadError = err;
        _isLoading = false;
      });
    }
  }

  void _autoSelectGridDay(
      CalendarScheduleDto sched, int year, int monthIndex) {
    if (_mode != 'grid') return;
    final monthPrefix =
        '$year-${(monthIndex + 1).toString().padLeft(2, '0')}';

    if (_selectedDay != null && _selectedDay!.startsWith(monthPrefix)) {
      return;
    }

    final todayItems = sched.days
        .where((d) => d.date == _todayStr)
        .expand((d) => d.items)
        .where(_matchesFilters)
        .toList();

    if (_todayStr.startsWith(monthPrefix) && todayItems.isNotEmpty) {
      setState(() => _selectedDay = _todayStr);
      return;
    }

    final daysWithMatches = sched.days
        .where(
            (d) => d.date.startsWith(monthPrefix) && d.items.any(_matchesFilters))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (daysWithMatches.isNotEmpty) {
      setState(() => _selectedDay = daysWithMatches.first.date);
      return;
    }

    if (_todayStr.startsWith(monthPrefix)) {
      setState(() => _selectedDay = _todayStr);
    } else {
      setState(() => _selectedDay = _isoDate(year, monthIndex, 1));
    }
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewYear, _viewMonthIndex + 1 + delta, 1);
    setState(() {
      _viewYear = next.year;
      _viewMonthIndex = next.month - 1;
      _selectedDay = null;
    });
    _loadSchedule();
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _viewYear = now.year;
      _viewMonthIndex = now.month - 1;
      _selectedDay = _todayStr;
    });
    _loadSchedule();
  }

  void _resetFilters() {
    setState(() {
      _typeFilter = 'all';
      _kindFilter = 'all';
      _selectedDay = null;
    });
  }

  void _setMode(String newMode) {
    setState(() {
      _mode = newMode;
      if (newMode == 'feed') {
        _selectedDay = null;
      } else if (newMode == 'grid' && _schedule != null) {
        _autoSelectGridDay(_schedule!, _viewYear, _viewMonthIndex);
      }
    });
  }

  Future<void> _checkNow(CalendarItemDto item) async {
    if (_checkingIds.contains(item.mediaId)) return;
    setState(() => _checkingIds = {..._checkingIds, item.mediaId});
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);

    try {
      await ref.read(apiClientProvider).triggerAutoRefresh(item.mediaId);
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.autoRefreshDone'),
          description: t.tr('toast.descUpdated'),
        ),
      );
      _loadSchedule();
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          final next = Set<String>.from(_checkingIds)..remove(item.mediaId);
          _checkingIds = next;
        });
      }
    }
  }

  Future<void> _handleExportIcs() async {
    if (_isExportingIcs) return;
    setState(() => _isExportingIcs = true);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);

    try {
      await ref.read(apiClientProvider).exportCalendarIcs();
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('views.calendarExportIcs'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExportingIcs = false);
    }
  }

  // ── Filters & Formatting ────────────────────────────────────────────────
  bool _matchesFilters(CalendarItemDto item) {
    if (_kindFilter == 'no_auto_refresh') {
      if (item.kind == CalendarEventKind.autoRefresh) return false;
    } else if (_kindFilter == 'auto_refresh') {
      if (item.kind != CalendarEventKind.autoRefresh) return false;
    } else if (_kindFilter == 'air_date') {
      if (item.kind != CalendarEventKind.airDate) return false;
    } else if (_kindFilter == 'release') {
      if (item.kind != CalendarEventKind.release) return false;
    }

    if (_typeFilter == 'all') return true;
    if (_typeFilter == 'anime') {
      return item.isAnime == true || item.type == 'anime';
    }
    if (_typeFilter == 'tvshow') {
      return item.type == 'tvshow' && item.isAnime != true;
    }
    if (_typeFilter == 'movie') {
      return item.type == 'movie' && item.isAnime != true;
    }
    return item.type == _typeFilter;
  }

  bool get _hasActiveFilters =>
      _typeFilter != 'all' || _kindFilter != 'all' || _selectedDay != null;

  Map<String, List<CalendarItemDto>> get _itemsByDate {
    final map = <String, List<CalendarItemDto>>{};
    for (final day in _schedule?.days ?? const <CalendarDayDto>[]) {
      final items = day.items.where(_matchesFilters).toList();
      if (items.isNotEmpty) map[day.date] = items;
    }
    return map;
  }

  List<MapEntry<String, List<CalendarItemDto>>> get _visibleDays {
    final entries = _itemsByDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (_selectedDay != null) {
      return entries.where((e) => e.key == _selectedDay).toList();
    }
    return entries;
  }

  String _isoDate(int year, int monthIndex, int day) {
    final month = (monthIndex + 1).toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$month-$d';
  }

  String _monthLabel(Locale locale) {
    initializeDateFormatting(locale.wire, null);
    final dt = DateTime(_viewYear, _viewMonthIndex + 1, 1);
    final raw = DateFormat.yMMMM(locale.wire).format(dt);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _dayHeading(String dateStr, Locale locale) {
    try {
      initializeDateFormatting(locale.wire, null);
      final dt = DateTime.parse(dateStr);
      final raw = DateFormat('EEEE, d MMMM', locale.wire).format(dt);
      if (raw.isEmpty) return raw;
      return raw.split(' ').map((w) => w.isNotEmpty ? (w[0].toUpperCase() + w.substring(1)) : '').join(' ');
    } catch (_) {
      return dateStr;
    }
  }

  List<String> _weekdays(Locale locale) {
    initializeDateFormatting(locale.wire, null);
    return List.generate(7, (i) {
      final dt = DateTime(2023, 1, 2 + i);
      final raw = DateFormat.E(locale.wire).format(dt).replaceAll('.', '');
      if (raw.isEmpty) return raw;
      return raw[0].toUpperCase() + raw.substring(1);
    });
  }

  String _kindLabel(CalendarEventKind kind, I18nDictionary t) {
    switch (kind) {
      case CalendarEventKind.autoRefresh:
        return t.tr('views.calendarFilterAutoRefresh');
      case CalendarEventKind.airDate:
        return t.tr('views.calendarFilterAirDate');
      case CalendarEventKind.release:
        return t.tr('views.calendarFilterRelease');
    }
  }

  String _typeLabel(CalendarItemDto item, I18nDictionary t) {
    if (item.isAnime == true || item.type == 'anime') {
      return t.tr('navigation.anime');
    }
    switch (item.type) {
      case 'manga':
        return t.tr('types.manga');
      case 'tvshow':
        return t.tr('types.tvshow');
      case 'movie':
        return t.tr('types.movie');
      case 'game':
        return t.tr('types.game');
      case 'book':
        return t.tr('types.book');
      default:
        return item.type;
    }
  }

  String _formatDaysLeft(int days, Locale locale) {
    final ru = locale == Locale.ru;
    if (days <= 0) return ru ? 'Сегодня' : 'Today';
    if (days == 1) return ru ? 'Завтра' : 'Tomorrow';
    return ru ? 'Через $days дн.' : 'In $days d.';
  }

  String _backlogUnit(BacklogDeadlineDto item, Locale locale) {
    if (item.type == 'manga') return locale == Locale.ru ? 'гл.' : 'ch.';
    return locale == Locale.ru ? 'эп.' : 'ep.';
  }

  String _backlogTypeLabel(String type, I18nDictionary t) {
    if (type == 'anime') return t.tr('navigation.anime');
    switch (type) {
      case 'manga':
        return t.tr('types.manga');
      case 'tvshow':
        return t.tr('types.tvshow');
      case 'movie':
        return t.tr('types.movie');
      case 'game':
        return t.tr('types.game');
      case 'book':
        return t.tr('types.book');
      default:
        return type;
    }
  }

  String? _formatBacklogBehind(BacklogDeadlineDto item, Locale locale) {
    if (item.behindCount == null || item.behindCount! <= 0) return null;
    final unit = _backlogUnit(item, locale);
    return locale == Locale.ru
        ? 'Осталось ${item.behindCount} $unit'
        : '${item.behindCount} $unit left';
  }

  String? _formatBacklogPace(BacklogDeadlineDto item, Locale locale) {
    if (item.behindCount == null ||
        item.behindCount! <= 0 ||
        item.daysLeft <= 0) {
      return null;
    }
    final unit = _backlogUnit(item, locale);
    final ru = locale == Locale.ru;
    final pacePerDay = item.behindCount! / item.daysLeft;
    if (pacePerDay >= 1) {
      final perDay = (pacePerDay * 10).ceil() / 10;
      final formatted =
          perDay.toStringAsFixed(perDay.truncateToDouble() == perDay ? 0 : 1);
      return ru
          ? 'Темп: ~$formatted $unit в день'
          : 'Pace: ~$formatted $unit/day';
    }
    final daysPerUnit = (item.daysLeft / item.behindCount!).ceil();
    if (ru) {
      final mod10 = daysPerUnit % 10;
      final mod100 = daysPerUnit % 100;
      final word = (mod100 >= 11 && mod100 <= 19)
          ? 'дней'
          : mod10 == 1
              ? 'день'
              : (mod10 >= 2 && mod10 <= 4)
                  ? 'дня'
                  : 'дней';
      return 'Темп: 1 $unit в $daysPerUnit $word';
    }
    return 'Pace: 1 $unit every $daysPerUnit ${daysPerUnit == 1 ? "day" : "days"}';
  }

  String? _formatBlockerProgress(BacklogDeadlineDto item) {
    if (item.blockerProgress == null) return null;
    return item.blockerTotalCount != null
        ? '${item.blockerProgress} / ${item.blockerTotalCount}'
        : item.blockerProgress.toString();
  }

  Widget _buildBacklogSubtitle(
    BacklogDeadlineDto item,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    if (item.kind == CalendarEventKind.airDate) {
      final behind = _formatBacklogBehind(item, locale);
      final pace = _formatBacklogPace(item, locale);
      final hasEpisode = item.seasonNumber != null && item.episodeNumber != null;

      final spans = <InlineSpan>[];
      if (behind != null) {
        spans.add(TextSpan(text: behind));
        if (pace != null) {
          spans.add(TextSpan(
            text: ' • ',
            style: TextStyle(color: tokens.textMuted.withAlpha(128)),
          ));
          spans.add(TextSpan(
            text: pace,
            style: const TextStyle(color: Color(0xFF6EE7B7)),
          ));
        }
      }
      if (hasEpisode) {
        spans.add(TextSpan(
          text: ' · S${item.seasonNumber}E${item.episodeNumber}',
          style: TextStyle(color: tokens.textMuted.withAlpha(153)),
        ));
      }
      return Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 11, color: tokens.textMuted),
          children: spans,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      final blockerTitle = item.blockerTitle;
      if (blockerTitle != null) {
        final progress = _formatBlockerProgress(item);
        final prefix = locale == Locale.ru ? 'Сначала: ' : 'Finish first: ';
        return Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11, color: tokens.textMuted),
            children: [
              TextSpan(text: '$prefix$blockerTitle'),
              if (progress != null)
                TextSpan(
                  text: ' · $progress',
                  style: TextStyle(color: tokens.textMuted.withAlpha(153)),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      } else {
        return Text(
          _backlogTypeLabel(item.type, t),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: tokens.textMuted),
        );
      }
    }
  }

  String _formatEventsCount(int count, Locale locale) {
    if (locale == Locale.ru) {
      final mod10 = count % 10;
      final mod100 = count % 100;
      if (mod100 >= 11 && mod100 <= 19) return '$count событий';
      if (mod10 == 1) return '$count событие';
      if (mod10 >= 2 && mod10 <= 4) return '$count события';
      return '$count событий';
    }
    return count == 1 ? '1 event' : '$count events';
  }

  String? _formatItemProgress(CalendarItemDto item, Locale locale) {
    if (item.currentProgress == null) return null;
    final cur = item.currentProgress.toString();
    final unit = item.type == 'manga'
        ? (locale == Locale.ru ? 'гл.' : 'ch.')
        : (item.type == 'tvshow' || item.isAnime == true)
            ? (locale == Locale.ru ? 'сер.' : 'ep.')
            : (item.type == 'book')
                ? (locale == Locale.ru ? 'стр.' : 'p.')
                : '';

    if (item.totalCount != null && item.totalCount! > 0) {
      if (item.currentProgress! > item.totalCount!) {
        return unit.isNotEmpty ? '$cur $unit' : cur;
      }
      final tot = item.totalCount.toString();
      return unit.isNotEmpty ? '$cur / $tot $unit' : '$cur / $tot';
    }
    return unit.isNotEmpty ? '$cur $unit' : cur;
  }

  String _formatEventShortLabel(CalendarItemDto item, Locale locale) {
    if (item.kind == CalendarEventKind.release) {
      return locale == Locale.ru ? 'Релиз' : 'Release';
    }
    if (item.kind == CalendarEventKind.airDate) {
      return item.details ??
          (item.seasonNumber != null && item.episodeNumber != null
              ? 'S${item.seasonNumber} E${item.episodeNumber}'
              : (locale == Locale.ru ? 'Серия' : 'Ep.'));
    }
    final match = RegExp(r'\d+').firstMatch(item.details ?? '');
    final days = match?.group(0) ?? '7';
    return locale == Locale.ru ? 'раз в $days дн.' : 'every $days d.';
  }

  List<({String date, int dayOfMonth, bool inMonth})> _computeGridCells() {
    final first = DateTime(_viewYear, _viewMonthIndex + 1, 1);
    final mondayOffset = (first.weekday - 1) % 7;
    final start = first.subtract(Duration(days: mondayOffset));

    final lastOfMonth = DateTime(_viewYear, _viewMonthIndex + 2, 0);
    final lastMondayOffset = (lastOfMonth.weekday - 1) % 7;
    final daysToSunday = (6 - lastMondayOffset) % 7;
    final end = lastOfMonth.add(Duration(days: daysToSunday));

    final totalDays = end.difference(start).inDays + 1;
    final cells = <({String date, int dayOfMonth, bool inMonth})>[];
    for (var i = 0; i < totalDays; i++) {
      final date = start.add(Duration(days: i));
      cells.add((
        date: DateFormat('yyyy-MM-dd').format(date),
        dayOfMonth: date.day,
        inMonth: date.month == (_viewMonthIndex + 1),
      ));
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final tokens = Theme.of(context).extension<TsundokuTheme>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Backlog Deadlines (if any) ──────────────────────────────
        if (_backlogItems.isNotEmpty) ...[
          _buildBacklogSection(t, locale, tokens),
          const SizedBox(height: 24),
        ],

        // ── Control Panel ───────────────────────────────────────────
        _buildControlPanel(t, locale, tokens),
        const SizedBox(height: 24),

        // ── Content ─────────────────────────────────────────────────
        if (_isLoading)
          _buildLoadingSkeleton(tokens)
        else if (_loadError != null)
          _buildErrorBox(t, locale, tokens)
        else if (_mode == 'feed' && _visibleDays.isEmpty)
          _buildEmptyBox(t, tokens)
        else if (_mode == 'grid')
          _buildGridMode(t, locale, tokens)
        else
          _buildFeedMode(t, locale, tokens),
      ],
    );
  }

  // ── Backlog Deadlines Section ─────────────────────────────────────────────
  Widget _buildBacklogSection(
      I18nDictionary t, Locale locale, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withAlpha(10), // amber-500/4%
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFBBF24).withAlpha(51), // amber-500/20%
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.clock3,
                  size: 16, color: Color(0xFFFCD34D)),
              const SizedBox(width: 8),
              Text(
                t.tr('views.backlogTitle'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: tokens.textPrimary,
                ),
              ),
              Text(
                ' · ${t.tr('views.backlogSubtitle')}',
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withAlpha(38),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withAlpha(76),
                  ),
                ),
                child: Text(
                  _backlogItems.length.toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFCD34D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1536 // 2xl:grid-cols-3
                  ? 3
                  : constraints.maxWidth >= 1024 // lg:grid-cols-2
                      ? 2
                      : 1;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _backlogItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 3.8,
                ),
                itemBuilder: (context, index) {
                  final item = _backlogItems[index];
                  return InkWell(
                    onTap: () => widget.onOpenMedia?.call(item.mediaId),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withAlpha(15),
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 40,
                              height: 60,
                              child: item.coverUrl != null &&
                                      !_brokenCovers.contains(item.coverUrl)
                                  ? TsundokuImage(
                                      src: item.coverUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const MediaCoverPlaceholder(),
                                      placeholder: const MediaCoverPlaceholder(),
                                    )
                                  : const MediaCoverPlaceholder(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFBBF24)
                                            .withAlpha(38),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFFFBBF24)
                                              .withAlpha(76),
                                        ),
                                      ),
                                      child: Text(
                                        _formatDaysLeft(
                                            item.daysLeft, locale),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFCD34D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                _buildBacklogSubtitle(
                                    item, t, locale, tokens),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Control Panel ─────────────────────────────────────────────────────────
  Widget _buildControlPanel(
      I18nDictionary t, Locale locale, TsundokuTheme tokens) {
    final categoryOptions = [
      PopoverOption(
          value: 'all', label: t.tr('views.calendarFilterAllCategories')),
      PopoverOption(value: 'manga', label: t.tr('types.manga')),
      PopoverOption(value: 'anime', label: t.tr('navigation.anime')),
      PopoverOption(value: 'tvshow', label: t.tr('types.tvshow')),
      PopoverOption(value: 'movie', label: t.tr('types.movie')),
      PopoverOption(value: 'game', label: t.tr('types.game')),
      PopoverOption(value: 'book', label: t.tr('types.book')),
    ];

    final eventKindOptions = [
      PopoverOption(
          value: 'all', label: t.tr('views.calendarFilterAllEvents')),
      PopoverOption(
          value: 'no_auto_refresh',
          label: t.tr('views.calendarFilterNoAutoRefresh')),
      PopoverOption(
          value: 'auto_refresh',
          label: t.tr('views.calendarFilterOnlyAutoRefresh')),
      PopoverOption(
          value: 'air_date',
          label: t.tr('views.calendarFilterOnlyAirDate')),
      PopoverOption(
          value: 'release', label: t.tr('views.calendarFilterOnlyRelease')),
    ];

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          // Left: Month Navigation + Category + Event Filter + Reset
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              // Month navigation
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: IconButton(
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(LucideIcons.chevronLeft, size: 17),
                      tooltip: t.tr('views.calendarPrevMonth'),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 36,
                    child: TextButton(
                      onPressed: _goToday,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _monthLabel(locale),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: IconButton(
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(LucideIcons.chevronRight, size: 17),
                      tooltip: t.tr('views.calendarNextMonth'),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),

              // Category select
              TsundokuSelect<String>(
                id: 'calendar-category',
                options: categoryOptions,
                value: _typeFilter,
                onChange: (v) => setState(() => _typeFilter = v),
                width: 160,
                height: 36,
              ),

              // Event kind select
              TsundokuSelect<String>(
                id: 'calendar-kind',
                options: eventKindOptions,
                value: _kindFilter,
                onChange: (v) => setState(() => _kindFilter = v),
                width: 175,
                height: 36,
              ),

              // Reset filters
              if (_hasActiveFilters)
                InkWell(
                  onTap: _resetFilters,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(26)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.rotateCcw, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          t.tr('views.calendarReset'),
                          style: TextStyle(
                              fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Right: ICS Export + Cell Mode (if grid) + View Mode
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              // Export ICS
              ElevatedButton.icon(
                onPressed: _isExportingIcs ? null : _handleExportIcs,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.bgCard,
                  foregroundColor: tokens.textPrimary,
                  minimumSize: const Size(0, 36),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.white.withAlpha(20)),
                  ),
                ),
                icon: const Icon(LucideIcons.download, size: 15),
                label: Text(
                  t.tr('views.calendarExportIcs'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),

            // Cell Mode toggle (Posters / Icons)
            if (_mode == 'grid')
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: tokens.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconToggleOption(
                      active: _cellMode == 'posters',
                      icon: LucideIcons.image,
                      label: t.tr('views.calendarCellModePosters'),
                      onTap: () => setState(() => _cellMode = 'posters'),
                      tokens: tokens,
                    ),
                    _IconToggleOption(
                      active: _cellMode == 'icons',
                      icon: LucideIcons.layers,
                      label: t.tr('views.calendarCellModeIcons'),
                      onTap: () => setState(() => _cellMode = 'icons'),
                      tokens: tokens,
                    ),
                  ],
                ),
              ),

            // View Mode toggle (Grid / Feed)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: tokens.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconToggleOption(
                    active: _mode == 'grid',
                    icon: LucideIcons.layoutGrid,
                    label: t.tr('views.calendarViewMonth'),
                    onTap: () => _setMode('grid'),
                    tokens: tokens,
                  ),
                  _IconToggleOption(
                    active: _mode == 'feed',
                    icon: LucideIcons.list,
                    label: t.tr('views.calendarViewFeed'),
                    onTap: () => _setMode('feed'),
                    tokens: tokens,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  // ── Feed Mode ─────────────────────────────────────────────────────────────
  Widget _buildFeedMode(
      I18nDictionary t, Locale locale, TsundokuTheme tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _visibleDays.map((entry) {
        final date = entry.key;
        final items = entry.value;

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header of day
              Row(
                children: [
                  Text(
                    _dayHeading(date, locale),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (date == _todayStr)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        t.tr('views.calendarToday'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else if (date == _tomorrowStr)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.accent.withAlpha(26),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: tokens.accent.withAlpha(76)),
                      ),
                      child: Text(
                        t.tr('views.calendarTomorrow'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: tokens.accentSoft,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '· ${_formatEventsCount(items.length, locale)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedDay != null)
                    TextButton(
                      onPressed: () => setState(() => _selectedDay = null),
                      child: Text('✕ ${t.tr('views.calendarAllDays')}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Cards grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width >= 1500
                      ? 7
                      : width >= 1200
                          ? 6
                          : width >= 900
                              ? 5
                              : width >= 700
                                  ? 4
                                  : width >= 500
                                      ? 3
                                      : 2;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.62,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _FeedCard(
                        item: item,
                        typeAndProgress:
                            '${_typeLabel(item, t)}${_formatItemProgress(item, locale) != null ? ' · ${_formatItemProgress(item, locale)}' : ''}',
                        eventLabel: _formatEventShortLabel(item, locale),
                        kindLabel: item.kind == CalendarEventKind.autoRefresh
                            ? (locale == Locale.ru ? 'Проверка' : 'Check')
                            : item.kind == CalendarEventKind.airDate
                                ? (locale == Locale.ru
                                    ? 'Эпизод'
                                    : 'Episode')
                                : (locale == Locale.ru
                                    ? 'Событие'
                                    : 'Event'),
                        isChecking: _checkingIds.contains(item.mediaId),
                        onCheckNow: () => _checkNow(item),
                        onOpenMedia: () =>
                            widget.onOpenMedia?.call(item.mediaId),
                        tokens: tokens,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Grid Mode ─────────────────────────────────────────────────────────────
  Widget _buildGridMode(
      I18nDictionary t, Locale locale, TsundokuTheme tokens) {
    final cells = _computeGridCells();
    final weekdays = _weekdays(locale);
    final selectedItems =
        _selectedDay != null ? (_itemsByDate[_selectedDay!] ?? const <CalendarItemDto>[]) : const <CalendarItemDto>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1000;

        final calendarSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Weekday headers
            Row(
              children: weekdays.map((day) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      day.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),

            // Days grid (7 columns)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final cell = cells[index];
                final cellItems = _itemsByDate[cell.date] ?? const [];
                final isSelected = _selectedDay == cell.date;
                final isToday = cell.date == _todayStr;

                if (!cell.inMonth) {
                  return Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12151C).withAlpha(51),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha(8)),
                    ),
                    child: Text(
                      cell.dayOfMonth.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textMuted.withAlpha(102),
                      ),
                    ),
                  );
                }

                return InkWell(
                  onTap: () => setState(() => _selectedDay = cell.date),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tokens.accent.withAlpha(26)
                          : cellItems.isNotEmpty
                              ? Colors.white.withAlpha(8)
                              : const Color(0xFF12151C).withAlpha(102),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? tokens.accent.withAlpha(153)
                            : cellItems.isNotEmpty
                                ? Colors.white.withAlpha(26)
                                : Colors.white.withAlpha(10),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top row of cell: Day number + overflow count
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (isToday)
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: tokens.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  cell.dayOfMonth.toString(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else
                              Text(
                                cell.dayOfMonth.toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? tokens.accentSoft
                                      : tokens.textPrimary,
                                ),
                              ),
                            if (cellItems.length > 3)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: tokens.accent.withAlpha(38),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '+${cellItems.length - 3}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: tokens.accentSoft,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),

                        // Cell content: Posters or Icons
                        if (cellItems.isNotEmpty)
                          if (_cellMode == 'icons')
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              children:
                                  cellItems.take(3).map((item) {
                                return _buildMiniIcon(item);
                              }).toList(),
                            )
                          else
                            Center(
                              child: SizedBox(
                                height: 46,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    for (var i = 0;
                                        i < cellItems.take(3).length;
                                        i++)
                                      Positioned(
                                        left: i * 16.0,
                                        child: _buildMiniPoster(
                                            cellItems[i]),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );

        final selectedDayPanel = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedDay != null) ...[
                // Day panel header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dayHeading(_selectedDay!, locale),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedItems.isEmpty
                                ? (locale == Locale.ru
                                    ? 'Нет событий'
                                    : 'No events')
                                : _formatEventsCount(
                                    selectedItems.length, locale),
                            style: TextStyle(
                                fontSize: 12, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedDay == _todayStr)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t.tr('views.calendarToday'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else if (_selectedDay == _tomorrowStr)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.accent.withAlpha(26),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: tokens.accent.withAlpha(76)),
                        ),
                        child: Text(
                          t.tr('views.calendarTomorrow'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: tokens.accentSoft,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Grouped items
                if (selectedItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      locale == Locale.ru
                          ? 'В этот день нет запланированных событий'
                          : 'No scheduled events on this date',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: tokens.textMuted),
                    ),
                  )
                else
                  _buildGroupedDayItems(selectedItems, t, locale, tokens),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    locale == Locale.ru
                        ? 'Выберите день в календаре'
                        : 'Select a day in the calendar',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                ),
            ],
          ),
        );

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: calendarSection),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: selectedDayPanel),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            calendarSection,
            const SizedBox(height: 24),
            selectedDayPanel,
          ],
        );
      },
    );
  }

  Widget _buildGroupedDayItems(
    List<CalendarItemDto> items,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    final releases =
        items.where((i) => i.kind == CalendarEventKind.release).toList();
    final airDates =
        items.where((i) => i.kind == CalendarEventKind.airDate).toList();
    final autoRefresh =
        items.where((i) => i.kind == CalendarEventKind.autoRefresh).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (releases.isNotEmpty) ...[
          _buildGroupHeader(
            LucideIcons.sparkles,
            t.tr('views.calendarFilterOnlyRelease'),
            releases.length,
            const Color(0xFFFBBF24),
          ),
          const SizedBox(height: 8),
          for (final item in releases) ...[
            _buildItemCard(item, t, locale, tokens),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        if (airDates.isNotEmpty) ...[
          _buildGroupHeader(
            LucideIcons.play,
            t.tr('views.calendarFilterOnlyAirDate'),
            airDates.length,
            const Color(0xFF34D399),
          ),
          const SizedBox(height: 8),
          for (final item in airDates) ...[
            _buildItemCard(item, t, locale, tokens),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        if (autoRefresh.isNotEmpty) ...[
          _buildGroupHeader(
            LucideIcons.refreshCw,
            t.tr('views.calendarFilterOnlyAutoRefresh'),
            autoRefresh.length,
            const Color(0xFF818CF8),
          ),
          const SizedBox(height: 8),
          for (final item in autoRefresh) ...[
            _buildItemCard(item, t, locale, tokens),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildGroupHeader(
      IconData icon, String title, int count, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(
    CalendarItemDto item,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    final typeAndProgress =
        '${_typeLabel(item, t)}${_formatItemProgress(item, locale) != null ? ' · ${_formatItemProgress(item, locale)}' : ''}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => widget.onOpenMedia?.call(item.mediaId),
            borderRadius: BorderRadius.circular(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 72,
                child: item.coverUrl != null &&
                        !_brokenCovers.contains(item.coverUrl)
                    ? TsundokuImage(
                        src: item.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const MediaCoverPlaceholder(),
                        placeholder: const MediaCoverPlaceholder(),
                      )
                    : const MediaCoverPlaceholder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => widget.onOpenMedia?.call(item.mediaId),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeAndProgress,
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
                if (item.details != null && item.details!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.details!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: tokens.textMuted.withAlpha(204)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.kind == CalendarEventKind.autoRefresh)
            IconButton(
              onPressed: _checkingIds.contains(item.mediaId)
                  ? null
                  : () => _checkNow(item),
              icon: _checkingIds.contains(item.mediaId)
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 15),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.kind == CalendarEventKind.airDate
                    ? const Color(0xFF34D399).withAlpha(26)
                    : const Color(0xFFFBBF24).withAlpha(26),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: item.kind == CalendarEventKind.airDate
                      ? const Color(0xFF34D399).withAlpha(76)
                      : const Color(0xFFFBBF24).withAlpha(76),
                ),
              ),
              child: Text(
                _kindLabel(item.kind, t),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: item.kind == CalendarEventKind.airDate
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFCD34D),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniIcon(CalendarItemDto item) {
    IconData icon;
    Color color;

    if (item.isAnime == true || item.type == 'anime') {
      icon = LucideIcons.clapperboard;
      color = const Color(0xFFC084FC);
    } else {
      switch (item.type) {
        case 'manga':
          icon = LucideIcons.library;
          color = const Color(0xFF34D399);
          break;
        case 'tvshow':
          icon = LucideIcons.tv;
          color = const Color(0xFF38BDF8);
          break;
        case 'movie':
          icon = LucideIcons.film;
          color = const Color(0xFFFBBF24);
          break;
        case 'game':
          icon = LucideIcons.gamepad2;
          color = const Color(0xFF818CF8);
          break;
        case 'book':
          icon = LucideIcons.bookOpen;
          color = const Color(0xFFFB7185);
          break;
        default:
          icon = LucideIcons.sparkles;
          color = const Color(0xFF94A3B8);
      }
    }

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(76)),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }

  Widget _buildMiniPoster(CalendarItemDto item) {
    return Container(
      width: 28,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withAlpha(51)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(102),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: item.coverUrl != null &&
                !_brokenCovers.contains(item.coverUrl)
            ? TsundokuImage(
                src: item.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const MediaCoverPlaceholder(),
                placeholder: const MediaCoverPlaceholder(),
              )
            : const MediaCoverPlaceholder(),
      ),
    );
  }

  Widget _buildLoadingSkeleton(TsundokuTheme tokens) {
    return Column(
      children: List.generate(
        4,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 96,
          decoration: BoxDecoration(
            color: tokens.bgCard,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBox(
      I18nDictionary t, Locale locale, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFB7185).withAlpha(13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Text(
              errorMessage(_loadError!, locale),
              style: const TextStyle(fontSize: 14, color: Color(0xFFFECDD3)),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadSchedule,
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text(t.tr('common.retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBox(I18nDictionary t, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: tokens.bgCard.withAlpha(128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(LucideIcons.calendarDays, size: 24, color: tokens.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            t.tr('views.calendarEmptyTitle'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.tr('views.calendarEmptyHint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Feed Card ────────────────────────────────────────────────────────────────
class _FeedCard extends StatelessWidget {
  final CalendarItemDto item;
  final String typeAndProgress;
  final String eventLabel;
  final String kindLabel;
  final bool isChecking;
  final VoidCallback onCheckNow;
  final VoidCallback onOpenMedia;
  final TsundokuTheme tokens;

  const _FeedCard({
    required this.item,
    required this.typeAndProgress,
    required this.eventLabel,
    required this.kindLabel,
    required this.isChecking,
    required this.onCheckNow,
    required this.onOpenMedia,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenMedia,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poster with auto-refresh button on top-right
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                        ? TsundokuImage(
                            src: item.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const MediaCoverPlaceholder(),
                            placeholder: const MediaCoverPlaceholder(),
                          )
                        : const MediaCoverPlaceholder(),
                  ),
                  if (item.kind == CalendarEventKind.autoRefresh)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xCC0D0F14),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: Colors.white.withAlpha(38)),
                        ),
                        child: IconButton(
                          onPressed: isChecking ? null : onCheckNow,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          icon: isChecking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(LucideIcons.refreshCw,
                                  size: 14, color: Color(0xFFA5B4FC)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Title & Info
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              typeAndProgress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            // Event tag banner at bottom
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kindLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.textMuted,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      eventLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.kind == CalendarEventKind.autoRefresh
                            ? const Color(0xFFA5B4FC)
                            : item.kind == CalendarEventKind.airDate
                                ? const Color(0xFF34D399)
                                : const Color(0xFFFCD34D),
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon Toggle Option ───────────────────────────────────────────────────────
class _IconToggleOption extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final TsundokuTheme tokens;

  const _IconToggleOption({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? tokens.accent.withAlpha(38) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? tokens.accentSoft : tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? tokens.accentSoft : tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
