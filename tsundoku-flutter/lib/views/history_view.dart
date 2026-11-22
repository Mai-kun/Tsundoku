/// 1:1 port of `mediatracker-ui/src/views/HistoryView.svelte`.
///
/// Экран истории: две вкладки — «Хроника» (интерактивный таймлайн завершённых и
/// текущих тайтлов с фильтрами, шкалой месяцы/годы, якорями по годам,
/// карточками с постерами и оценками, блоком тайтлов без даты) и «Активность»
/// (лента событий getHistoryEvents с фильтром по дате, кнопками удаления и полной
/// очистки через confirmAction).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../entities/media/model/chronicle_timeline.dart';
import '../shared/api/api.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';
import '../shared/ui/confirm_dialog.dart';
import '../shared/ui/toast.dart';
import '../shared/utils/history_formatters.dart';

class HistoryView extends ConsumerStatefulWidget {
  final int refreshKey;
  final ValueChanged<String>? onOpenMedia;

  const HistoryView({
    super.key,
    required this.refreshKey,
    this.onOpenMedia,
  });

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  // ── Tab state ──────────────────────────────────────────────────────────
  String _activeTab = 'chronicle'; // 'chronicle' | 'activity'

  // ── Activity tab state ─────────────────────────────────────────────────
  String _selectedDate = ''; // 'yyyy-MM-dd' or ''
  List<HistoryEvent> _events = const [];
  bool _loadingEvents = true;
  Object? _loadEventsError;
  bool _clearing = false;
  String? _deletingId;
  int _eventsSequence = 0;

  // ── Chronicle tab state ────────────────────────────────────────────────
  TimelineScale _scale = 'months'; // 'months' | 'years'
  TimelineCategoryFilter _categoryFilter = 'all';
  bool _includeInProgress = false;

  List<MediaItem> _allItems = const [];
  bool _loadingItems = true;
  Object? _loadItemsError;
  int _itemsSequence = 0;

  bool _undatedExpanded = false;
  final Map<int, GlobalKey> _yearKeys = {};

  @override
  void initState() {
    super.initState();
    _loadAllItems(++_itemsSequence);
  }

  @override
  void didUpdateWidget(covariant HistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      if (_activeTab == 'chronicle') {
        _loadAllItems(++_itemsSequence);
      } else {
        _loadEvents(++_eventsSequence);
      }
    }
  }

  // ── Network: Chronicle items ───────────────────────────────────────────
  Future<void> _loadAllItems(int sequence) async {
    setState(() {
      _loadingItems = true;
      _loadItemsError = null;
    });

    try {
      final data = await ref.read(apiClientProvider).getMedia();
      if (!mounted) return;
      if (sequence == _itemsSequence) {
        setState(() {
          _allItems = data;
          _loadingItems = false;
        });
      }
    } catch (err) {
      if (!mounted) return;
      if (sequence == _itemsSequence) {
        setState(() {
          _loadItemsError = err;
          _loadingItems = false;
        });
      }
    }
  }

  void _retryItems() {
    _loadAllItems(++_itemsSequence);
  }

  // ── Network: Activity events ───────────────────────────────────────────
  Future<void> _loadEvents(int sequence) async {
    setState(() {
      _loadingEvents = true;
      _loadEventsError = null;
    });

    try {
      final nextEvents = await ref.read(apiClientProvider).getHistoryEvents(
            date: _selectedDate.isNotEmpty ? _selectedDate : null,
          );
      if (!mounted) return;
      if (sequence == _eventsSequence) {
        setState(() {
          _events = nextEvents;
          _loadingEvents = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (sequence == _eventsSequence) {
        setState(() {
          _loadEventsError = error;
          _loadingEvents = false;
        });
      }
    }
  }

  void _retryEvents() {
    _loadEvents(++_eventsSequence);
  }

  void _switchTab(String tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    if (tab == 'activity') {
      _loadEvents(++_eventsSequence);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────
  Future<void> _handleDeleteEvent(HistoryEvent event) async {
    if (_deletingId != null) return;
    final t = ref.read(tProvider);
    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-history-entry',
        title: t.tr('views.confirmDeleteHistoryEntry'),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    );
    if (!confirmed) return;

    final prevEvents = List<HistoryEvent>.from(_events);
    setState(() {
      _deletingId = event.id;
      _events = _events.where((x) => x.id != event.id).toList();
    });

    final locale = ref.read(i18nProvider);
    try {
      await ref.read(apiClientProvider).deleteHistoryEvent(event.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('views.historyEntryDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _events = prevEvents);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(err, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _handleClearAll() async {
    if (_events.isEmpty) return;
    final t = ref.read(tProvider);
    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'clear-history',
        title: t.tr('views.confirmClearHistory'),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    );
    if (!confirmed) return;

    setState(() => _clearing = true);
    final prevEvents = List<HistoryEvent>.from(_events);
    setState(() => _events = const []);

    final locale = ref.read(i18nProvider);
    try {
      await ref.read(apiClientProvider).clearAllHistory();
      showToast(
        ref,
        ToastOptions(
          title: t.tr('views.historyCleared'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _events = prevEvents);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(err, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _scrollToYear(int year) {
    final key = _yearKeys[year];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  // ── Formatters ─────────────────────────────────────────────────────────
  String _formatDate(String value, Locale locale) {
    try {
      initializeDateFormatting(locale.wire, null);
      final dt = DateTime.parse(value).toLocal();
      final loc = locale.wire;
      final dateStr = DateFormat.yMMMd(loc).format(dt);
      final timeStr = DateFormat.Hm(loc).format(dt);
      return '$dateStr, $timeStr';
    } catch (_) {
      return value;
    }
  }

  String _monthName(int month, Locale locale) {
    initializeDateFormatting(locale.wire, null);
    final loc = locale.wire;
    return DateFormat.MMMM(loc).format(DateTime(2000, month + 1, 1));
  }

  String _shortDate(DateTime date, Locale locale) {
    initializeDateFormatting(locale.wire, null);
    final loc = locale.wire;
    return DateFormat.MMMd(loc).format(date);
  }

  String _typeLabel(MediaItem item, I18nDictionary t) {
    final isAnime = item.isAnime == true;
    if (isAnime &&
        (item.type == MediaType.tvshow || item.type == MediaType.movie)) {
      return t.tr('navigation.anime');
    }
    return t.tr('types.${item.type.wire}');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final tokens = Theme.of(context).extension<TsundokuTheme>()!;

    final chronicle = buildChronicle(
      _allItems,
      category: _categoryFilter,
      includeInProgress: _includeInProgress,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1024), // max-w-5xl
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              // ── Header + Activity Controls ──────────────────────────────
              _buildHeader(context, t, tokens),
              const SizedBox(height: 24),

              // ── Tab switcher pills ──────────────────────────────────────
              _buildTabSwitcher(t, tokens),
              const SizedBox(height: 24),

              // ── Tab content ─────────────────────────────────────────────
              if (_activeTab == 'chronicle')
                _buildChronicleTab(t, locale, tokens, chronicle)
              else
                _buildActivityTab(t, locale, tokens),
            ],
          ),
        ),
      );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context, I18nDictionary t, TsundokuTheme tokens) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tr('library.collectionLabel').toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
                color: tokens.accentSoft,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('views.historyTitle'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: tokens.textPrimary,
              ),
            ),
          ],
        ),

        // Activity-only controls (date filter + clear all)
        if (_activeTab == 'activity')
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              // Date picker button
              InkWell(
                onTap: () async {
                  DateTime initial = DateTime.now();
                  if (_selectedDate.isNotEmpty) {
                    try {
                      initial = DateTime.parse(_selectedDate);
                    } catch (_) {}
                  }
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
                    });
                    _loadEvents(++_eventsSequence);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withAlpha(26)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.calendar,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        _selectedDate.isNotEmpty
                            ? _selectedDate
                            : t.tr('views.filterByDate'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Reset date button
              if (_selectedDate.isNotEmpty)
                InkWell(
                  onTap: () {
                    setState(() => _selectedDate = '');
                    _loadEvents(++_eventsSequence);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(26)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      t.tr('views.resetDate'),
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),

              // Clear all button
              if (_events.isNotEmpty)
                InkWell(
                  onTap: _clearing ? null : _handleClearAll,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withAlpha(26)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.trash2,
                          size: 13,
                          color: Color(0xFFFB7185), // rose-400
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.tr('views.clearHistory'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFB7185), // rose-400
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ── Tab switcher pills ────────────────────────────────────────────────────
  Widget _buildTabSwitcher(I18nDictionary t, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabPill(
            active: _activeTab == 'chronicle',
            icon: LucideIcons.calendarDays,
            label: t.tr('views.tabChronicle'),
            onTap: () => _switchTab('chronicle'),
            tokens: tokens,
          ),
          const SizedBox(width: 4),
          _TabPill(
            active: _activeTab == 'activity',
            icon: LucideIcons.history,
            label: t.tr('views.tabActivity'),
            onTap: () => _switchTab('activity'),
            tokens: tokens,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHRONICLE TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildChronicleTab(
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
    ChronicleResult chronicle,
  ) {
    if (_loadingItems) {
      return Column(
        children: List.generate(
          3,
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 160,
            decoration: BoxDecoration(
              color: tokens.bgCard,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (_loadItemsError != null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 288),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFB7185).withAlpha(13), // rose-400/5
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                errorMessage(_loadItemsError!, locale),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFFECDD3), // rose-200
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _retryItems,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: Text(t.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    final categoryChips = <({TimelineCategoryFilter key, String label})>[
      (key: 'all', label: t.tr('status.all')),
      (key: 'game', label: t.tr('navigation.game')),
      (key: 'anime', label: t.tr('navigation.anime')),
      (key: 'manga', label: t.tr('navigation.manga')),
      (key: 'movie', label: t.tr('navigation.movie')),
      (key: 'tvshow', label: t.tr('navigation.tvshow')),
      (key: 'book', label: t.tr('navigation.book')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chronicle controls (Scale toggle + Category chips + In-progress toggle)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            // Scale toggle
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: tokens.bgCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ScaleOption(
                    active: _scale == 'months',
                    label: t.tr('views.scaleMonths'),
                    onTap: () => setState(() => _scale = 'months'),
                    tokens: tokens,
                  ),
                  _ScaleOption(
                    active: _scale == 'years',
                    label: t.tr('views.scaleYears'),
                    onTap: () => setState(() => _scale = 'years'),
                    tokens: tokens,
                  ),
                ],
              ),
            ),

            // Category chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: categoryChips.map((chip) {
                final isSelected = _categoryFilter == chip.key;
                return InkWell(
                  onTap: () => setState(() => _categoryFilter = chip.key),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tokens.accent.withAlpha(38)
                          : tokens.bgSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? tokens.accent.withAlpha(128)
                            : Colors.white.withAlpha(26),
                      ),
                    ),
                    child: Text(
                      chip.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? tokens.accentSoft : tokens.textMuted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // In-progress toggle
            InkWell(
              onTap: () =>
                  setState(() => _includeInProgress = !_includeInProgress),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _includeInProgress,
                        onChanged: (v) =>
                            setState(() => _includeInProgress = v ?? false),
                        activeColor: tokens.accent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.tr('views.includeInProgress'),
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Year anchors
        if (chronicle.years.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chronicle.years.map((yg) {
              return InkWell(
                onTap: () => _scrollToYear(yg.year),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withAlpha(26)),
                  ),
                  child: Text(
                    yg.year.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: tokens.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Empty state
        if (chronicle.years.isEmpty && chronicle.undatedCompleted.isEmpty)
          Container(
            constraints: const BoxConstraints(minHeight: 288),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tokens.bgCard,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(LucideIcons.calendarDays,
                        size: 22, color: tokens.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.tr('views.emptyChronicleTitle'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.tr('views.emptyChronicleHint'),
                    style: TextStyle(
                      fontSize: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // Timeline
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.only(left: 20),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: tokens.accent.withAlpha(76), // border-accent/30
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final yg in chronicle.years) ...[
                  _buildYearSection(yg, t, locale, tokens),
                  const SizedBox(height: 40),
                ],

                // Undated completed section
                if (chronicle.undatedCompleted.isNotEmpty)
                  _buildUndatedSection(
                      chronicle.undatedCompleted, t, tokens),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildYearSection(
    ChronicleYearGroup yg,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    final key = _yearKeys.putIfAbsent(yg.year, () => GlobalKey());

    return Container(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Year heading + summary stats
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                yg.year.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withAlpha(26)),
                ),
                child: Text(
                  t.tf('views.yearSummaryCount', [yg.totalCount]),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              if (yg.averageScore != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withAlpha(26), // amber-400/10
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withAlpha(51),
                    ),
                  ),
                  child: Text(
                    t.tf('views.yearAvgScore', [yg.averageScore.toString()]),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFCD34D), // amber-300
                    ),
                  ),
                ),
              if (yg.topRatedItem != null)
                InkWell(
                  onTap: () =>
                      widget.onOpenMedia?.call(yg.topRatedItem!.id),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withAlpha(26)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.trophy,
                          size: 11,
                          color: Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            t.tf('views.yearFavorite',
                                [yg.topRatedItem!.title]),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (_scale == 'months')
            // By-month view
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: yg.months.map((mg) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Month label + count
                      Row(
                        children: [
                          Text(
                            _monthName(mg.month, locale),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: tokens.textPrimary.withAlpha(204),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.bgSurface,
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: Colors.white.withAlpha(26)),
                            ),
                            child: Text(
                              mg.entries.length.toString(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: tokens.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Month cards grid
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = width >= 900
                              ? 6
                              : width >= 650
                                  ? 4
                                  : width >= 450
                                      ? 3
                                      : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: mg.entries.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 2 / 3.8,
                            ),
                            itemBuilder: (context, index) {
                              final entry = mg.entries[index];
                              return _ChronicleCard(
                                entry: entry,
                                typeLabel: _typeLabel(entry.item, t),
                                shortDate: _shortDate(entry.date, locale),
                                inProgressText: t.tr('status.inProgress'),
                                onTap: () => widget.onOpenMedia
                                    ?.call(entry.item.id),
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
            )
          else
            // By-year mosaic view
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 900
                    ? 9
                    : width >= 700
                        ? 7
                        : width >= 500
                            ? 5
                            : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: yg.entries.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2 / 3,
                  ),
                  itemBuilder: (context, index) {
                    final entry = yg.entries[index];
                    return _MiniCard(
                      item: entry.item,
                      onTap: () =>
                          widget.onOpenMedia?.call(entry.item.id),
                      tokens: tokens,
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Undated completed section ─────────────────────────────────────────────
  Widget _buildUndatedSection(
    List<MediaItem> undated,
    I18nDictionary t,
    TsundokuTheme tokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _undatedExpanded = !_undatedExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _undatedExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Text('▶', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text(
                  t.tf('views.undatedCompletedTitle', [undated.length]),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_undatedExpanded) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 900
                  ? 9
                  : width >= 700
                      ? 7
                      : width >= 500
                          ? 5
                          : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: undated.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2 / 3,
                ),
                itemBuilder: (context, index) {
                  final item = undated[index];
                  return _MiniCard(
                    item: item,
                    onTap: () => widget.onOpenMedia?.call(item.id),
                    tokens: tokens,
                  );
                },
              );
            },
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVITY TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildActivityTab(
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    if (_loadingEvents) {
      return Column(
        children: List.generate(
          4,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 64,
            decoration: BoxDecoration(
              color: tokens.bgCard,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }

    if (_loadEventsError != null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 288),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFB7185).withAlpha(13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                errorMessage(_loadEventsError!, locale),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFFECDD3),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _retryEvents,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: Text(t.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_events.isEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 288),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tokens.bgCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(LucideIcons.history,
                    size: 22, color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              Text(
                _selectedDate.isNotEmpty
                    ? t.tr('views.noActivityForDate')
                    : t.tr('common.noData'),
                style: TextStyle(
                  fontSize: 14,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _events.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = _events[index];
        final icon = historyEventIcons[event.type] ?? LucideIcons.flag;
        final isDeleted = event.type == HistoryEventType.deleted;
        final hasMedia = event.title != null && !isDeleted;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.bgCard,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Event icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.accent.withAlpha(38), // bg-accent/15
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 17, color: tokens.accentSoft),
              ),
              const SizedBox(width: 16),

              // Title and event label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasMedia)
                      InkWell(
                        onTap: () => widget.onOpenMedia
                            ?.call(event.mediaId),
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                event.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.arrowUpRight,
                              size: 13,
                              color: tokens.accentSoft,
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        event.title ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.textMuted,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      formatHistoryEventLabel(event, t),
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Date + Delete button
              Text(
                _formatDate(event.createdAt, locale),
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _deletingId != null
                    ? null
                    : () => _handleDeleteEvent(event),
                iconSize: 13,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: _deletingId == event.id
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(LucideIcons.trash2, color: tokens.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tab Pill ────────────────────────────────────────────────────────────────
class _TabPill extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final TsundokuTheme tokens;

  const _TabPill({
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? tokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : tokens.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scale Option ─────────────────────────────────────────────────────────────
class _ScaleOption extends StatelessWidget {
  final bool active;
  final String label;
  final VoidCallback onTap;
  final TsundokuTheme tokens;

  const _ScaleOption({
    required this.active,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? tokens.accent.withAlpha(51) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? tokens.accentSoft : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Chronicle Card (Months scale) ───────────────────────────────────────────
class _ChronicleCard extends StatelessWidget {
  final ChronicleEntry entry;
  final String typeLabel;
  final String shortDate;
  final String inProgressText;
  final VoidCallback onTap;
  final TsundokuTheme tokens;

  const _ChronicleCard({
    required this.entry,
    required this.typeLabel,
    required this.shortDate,
    required this.inProgressText,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poster
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (entry.item.coverUrl != null &&
                      entry.item.coverUrl!.isNotEmpty)
                    Image.network(
                      entry.item.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) =>
                          _fallbackCover(),
                    )
                  else
                    _fallbackCover(),

                  // Badge: score or in-progress
                  Positioned(
                    top: 6,
                    left: 6,
                    child: !entry.isCompleted
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6)
                                  .withAlpha(204), // blue-500/80
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              inProgressText,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : (entry.item.score != null && entry.item.score! > 0)
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(178),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '★ ${entry.item.score}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFCD34D), // amber-300
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Title
          Text(
            entry.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary.withAlpha(230),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),

          // Footer info
          Text(
            '$typeLabel · $shortDate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: tokens.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgElevated,
      ),
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      child: Text(
        entry.item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}

// ── Mini Card (Years scale & Undated mosaic) ─────────────────────────────────
class _MiniCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final TsundokuTheme tokens;

  const _MiniCard({
    required this.item,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.coverUrl != null && item.coverUrl!.isNotEmpty)
              Image.network(
                item.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => _fallbackCover(),
              )
            else
              _fallbackCover(),

            if (item.score != null && item.score! > 0)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(178),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '★${item.score}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFCD34D), // amber-300
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgElevated,
      ),
      padding: const EdgeInsets.all(2),
      alignment: Alignment.center,
      child: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}
