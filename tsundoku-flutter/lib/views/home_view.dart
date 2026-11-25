/// 1:1 port of `mediatracker-ui/src/views/HomeView.svelte`.
///
/// Главная: три секции (inProgress/planned/completed из getMedia), панель
/// управления (группировка status/type/none, категории + вынесенные,
/// фильтр времени с кастомным вводом, 🎲-рандомайзер, поиск, лимит секций,
/// сортировка updated/created/oldest/rating/title), чипы активных фильтров,
/// сводка времени, stale-бейдж → StaleBacklogModal (Фаза 5 — колбек
/// onOpenStaleBacklog, решение #40).
///
/// Секции — слайверы (решение #37): вью возвращает список слайверов.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../entities/media/model/media_labels.dart';
import '../entities/media/model/stale_triage.dart';
import '../entities/media/model/time_budget.dart';
import '../features/prefetch-details/media_detail_prefetch.dart';
import '../features/update-progress/optimistic_progress.dart';
import '../shared/api/api.dart';
import '../shared/api/jobs_client.dart';
import '../shared/api/navigation_categories.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';
import '../shared/ui/popover_menu.dart';
import '../shared/ui/text_field.dart';
import '../shared/ui/toast.dart';
import '../shared/ui/total_badge.dart';
import '../shared/utils/swr_cache.dart';
import '../shared/utils/ui_settings.dart';
import '../views/category_model.dart' show LibrarySort;
import '../views/category_view.dart' show categoryCache;
import '../widgets/media-grid/media_grid.dart';

class HomePayload {
  final List<MediaItem> inProgress;
  final List<MediaItem> upNext;
  final List<MediaItem> recentlyCompleted;

  const HomePayload({
    required this.inProgress,
    required this.upNext,
    required this.recentlyCompleted,
  });
}

const String homeKey = 'home';
final SwrCache<HomePayload> homeCache = SwrCache<HomePayload>();

/// window-событие tsundoku:random-pick → сигнал-шина: App (контекст-меню
/// desktop) инкрементит, смонтированный HomeView слушает и отвечает пулом
/// экрана (решение #41).
final ValueNotifier<int> homeRandomPickSignal = ValueNotifier<int>(0);

/// Home-local sort: `updated` leads with last activity.
typedef HomeSort = String;

typedef HomeCategoryFilter = String;
typedef HomeGroupingMode = String;

const String homeGroupStatus = 'status';
const String homeGroupType = 'type';
const String homeGroupNone = 'none';

IconData homeSortIcon(String sort) {
  switch (sort) {
    case 'updated':
      return LucideIcons.history;
    case 'created':
      return LucideIcons.calendarDays;
    case 'oldest':
      return LucideIcons.arrowUp;
    case 'rating':
      return LucideIcons.star;
    case 'title':
      return LucideIcons.type;
    default:
      return LucideIcons.history;
  }
}

IconData groupModeIcon(String mode) {
  switch (mode) {
    case homeGroupStatus:
      return LucideIcons.listChecks;
    case homeGroupType:
      return LucideIcons.layers;
    default:
      return LucideIcons.layoutGrid;
  }
}

class HomeView extends ConsumerStatefulWidget {
  final int refreshKey;
  final void Function(MediaItem item) onOpen;
  final VoidCallback onMediaChanged;
  final void Function(MediaItem item)? onEdit;

  /// StaleBacklogModal (Фаза 5) — App подключит (решение #40).
  final VoidCallback? onOpenStaleBacklog;
  final bool initiallyOpenTimeBudget;

  const HomeView({
    super.key,
    required this.refreshKey,
    required this.onOpen,
    required this.onMediaChanged,
    this.onEdit,
    this.onOpenStaleBacklog,
    this.initiallyOpenTimeBudget = false,
  });

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  List<MediaItem> _inProgress = const <MediaItem>[];
  List<MediaItem> _upNext = const <MediaItem>[];
  List<MediaItem> _recentlyCompleted = const <MediaItem>[];
  bool _loading = homeCache.peek(homeKey) == null;
  Object? _loadError;
  LibrarySort _sort = 'newest'; // persisted 'newest' → home 'updated'
  HomeGroupingMode _groupByMode = homeGroupStatus;
  int? _timeBudget;
  bool _showAll = false;
  String _searchQuery = '';
  String _debouncedSearch = '';
  HomeCategoryFilter _selectedCategory = 'all';
  int _requestSequence = 0;
  bool _hasLoaded = homeCache.peek(homeKey) != null;
  Timer? _searchDebounce;
  Timer? _skeletonTimer;
  Timer? _stuckReloadTimer;
  int? _prevRefreshKey;
  int _stuckReloadRevision = -1;
  String? _lastFetchEffectKey;

  void _randomPickListener() => _pickRandomTitle();

  @override
  void initState() {
    super.initState();
    homeRandomPickSignal.addListener(_randomPickListener);
    final cached = homeCache.peek(homeKey);
    if (cached != null) {
      _inProgress = cached.inProgress;
      _upNext = cached.upNext;
      _recentlyCompleted = cached.recentlyCompleted;
    }
    // The persisted library value "newest" maps to home's "updated".
    _sort = ref.read(uiSettingsProvider).sortOption == 'newest'
        ? 'updated'
        : ref.read(uiSettingsProvider).sortOption;
    _groupByMode = ref.read(uiSettingsProvider).groupByType
        ? homeGroupType
        : homeGroupStatus;
  }

  @override
  void dispose() {
    homeRandomPickSignal.removeListener(_randomPickListener);
    _searchDebounce?.cancel();
    _skeletonTimer?.cancel();
    _stuckReloadTimer?.cancel();
    super.dispose();
  }

  TimeFitResult _evaluateItem(MediaItem item, int budget) {
    final settings = ref.read(uiSettingsProvider);
    return evaluateTimeFit(
      item,
      budget,
      settings.bookPageMinutes,
      settings.mangaChapterMinutes,
      locale: ref.read(i18nProvider).wire,
    );
  }

  // TYPE_ORDER: вынесенная категория идёт сразу после родительской
  // (book 6 → comics 6.5).
  double _typeOrder(String key) {
    const typeOrder = <String, double>{
      'game': 1,
      'anime': 2,
      'manga': 3,
      'movie': 4,
      'tvshow': 5,
      'book': 6,
    };
    final base = typeOrder[key];
    if (base != null) return base;
    final sub = ref
        .read(navigationCategoriesProvider.notifier)
        .promotedCategoryById(key);
    return sub != null
        ? (typeOrder[sub.parentType.toLowerCase()] ?? 99) + 0.5
        : 99;
  }

  int _compareItems(MediaItem a, MediaItem b, String currentSort) {
    int parse(String? value) =>
        DateTime.tryParse(value ?? '')?.millisecondsSinceEpoch ?? 0;
    if (currentSort == 'rating') {
      return ((b.score ?? 0) - (a.score ?? 0)).round();
    }
    if (currentSort == 'title') {
      return a.title.compareTo(b.title); // localeCompare ≈ lexicographic
    }
    if (currentSort == 'created') {
      return parse(b.createdAt) - parse(a.createdAt);
    }
    if (currentSort == 'oldest') {
      return parse(a.createdAt) - parse(b.createdAt);
    }
    // updated = «по недавней активности».
    final aTime = parse(a.lastActivityAt ?? a.updatedAt ?? a.createdAt);
    final bTime = parse(b.lastActivityAt ?? b.updatedAt ?? b.createdAt);
    return bTime - aTime;
  }

  List<MediaItem> _sortItems(List<MediaItem> list, bool byType, String currentSort) {
    final sorted = [...list]..sort((a, b) {
        if (byType) {
          final typeA = _typeOrder(a.type.wire);
          final typeB = _typeOrder(b.type.wire);
          if (typeA != typeB) return typeA.compareTo(typeB);
        }
        return _compareItems(a, b, currentSort);
      });
    return sorted;
  }

  List<MediaItem> _sortBudgetItems(
      List<MediaItem> list, int budget, bool byType, String currentSort) {
    final sorted = [...list]..sort((a, b) {
        final finishA = _evaluateItem(a, budget).canFinishNow ? 1 : 0;
        final finishB = _evaluateItem(b, budget).canFinishNow ? 1 : 0;
        if (finishA != finishB) return finishB - finishA;
        if (byType) {
          final typeA = _typeOrder(a.type.wire);
          final typeB = _typeOrder(b.type.wire);
          if (typeA != typeB) return typeA.compareTo(typeB);
        }
        return _compareItems(a, b, currentSort);
      });
    return sorted;
  }

  /// Компактный per-section slice: columns × полных строк (3 на десктопе,
  /// 5 на планшете/мобайле) — как grid-математика Svelte.
  int get _sectionColumns =>
      columnsForWidth(MediaQuery.sizeOf(context).width);
  int get _sectionRows => MediaQuery.sizeOf(context).width < 1024 ? 5 : 3;
  int get _sectionLimit => _sectionColumns * _sectionRows;

  bool _matchesSearch(MediaItem item, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final romaji = item.romajiTitle ?? '';
    final original =
        (item is MediaDetail ? item.originalTitle : null) ?? '';
    return [item.title, romaji, original]
        .any((value) => value.toLowerCase().contains(needle));
  }

  bool _matchesCategory(MediaItem item) {
    if (_selectedCategory == 'all') return true;
    // "anime" покрывает оба анимированных вида; вынесенная категория
    // забирает элемент из родительской группы.
    if (_selectedCategory == 'anime') return _typeKey(item) == 'anime';
    return item.type.wire == _selectedCategory;
  }

  String _typeKey(MediaItem media) {
    // Вынесенная категория забирает элемент из родительской группы.
    final categories = ref.read(navigationCategoriesProvider);
    return promotedCategoryOfItem(media, categories)?.id ??
        (media.type == MediaType.tvshow && (media.isAnime ?? false)
            ? 'anime'
            : media.type.wire);
  }

  String _typeLabel(String key) {
    final promoted = ref
        .read(navigationCategoriesProvider.notifier)
        .promotedCategoryById(key);
    if (promoted != null) return promoted.label;
    final t = ref.read(tProvider);
    switch (key) {
      case 'game':
        return t.tr('navigation.game');
      case 'anime':
        return t.tr('navigation.anime');
      case 'manga':
        return t.tr('navigation.manga');
      case 'movie':
        return t.tr('navigation.movie');
      case 'tvshow':
        return t.tr('navigation.tvshow');
      default:
        return t.tr('navigation.book');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);

    // 200ms debounce поиска.
    ref.listen(_homeSearchDebounceProvider, (_, _) {});

    // Реактивный тихий рефетч при завершении фоновых задач (в т.ч. в IndexedStack).
    ref.listen<JobsState>(jobsClientProvider, (previous, next) {
      final prevActive = previous?.jobs.any(isActiveJob) ?? false;
      final nextActive = next.jobs.any(isActiveJob);
      final settledChanged =
          previous != null && next.settledVersion != previous.settledVersion;
      final activeDropped = prevActive && !nextActive;
      if (settledChanged || activeDropped) {
        _stuckReloadTimer?.cancel();
        _stuckReloadTimer = null;
        homeCache.invalidate(homeKey);
        categoryCache.clear();
        ref.read(mediaDetailCacheProvider).clear();
        _refresh();
      }
    });

    // $effect(fetch) — гвард ключом зависимостей (решение #39).
    _runFetchEffect();
    _runStuckReloadEffect();

    List<MediaItem> filtered(List<MediaItem> list) => list
        .where((item) =>
            _matchesSearch(item, _debouncedSearch) &&
            _matchesCategory(item))
        .toList();

    final filteredInProgress = filtered(_inProgress);
    final filteredUpNext = filtered(_upNext);
    final filteredRecentlyCompleted = filtered(_recentlyCompleted);
    final filteredTotal = filteredInProgress.length +
        filteredUpNext.length +
        filteredRecentlyCompleted.length;

    final hasActiveFilters = _debouncedSearch.trim().isNotEmpty ||
        _selectedCategory != 'all' ||
        _timeBudget != null;

    final inProgressFitting = _timeBudget == null
        ? const <MediaItem>[]
        : filteredInProgress
            .where((item) => _evaluateItem(item, _timeBudget!).fits)
            .toList();
    final upNextFitting = _timeBudget == null
        ? const <MediaItem>[]
        : filteredUpNext
            .where((item) => _evaluateItem(item, _timeBudget!).fits)
            .toList();
    final totalFitting = inProgressFitting.length + upNextFitting.length;
    var totalFinishable = 0;
    if (_timeBudget != null) {
      for (final item in inProgressFitting) {
        if (_evaluateItem(item, _timeBudget!).canFinishNow) totalFinishable++;
      }
      for (final item in upNextFitting) {
        if (_evaluateItem(item, _timeBudget!).canFinishNow) totalFinishable++;
      }
    }

    final limit = _showAll ? 1 << 31 : _sectionLimit;
    List<MediaItem> clamp(List<MediaItem> list) =>
        list.length > limit ? list.sublist(0, limit) : list;

    final displayInProgress = clamp(_timeBudget != null
        ? _sortBudgetItems(inProgressFitting, _timeBudget!, false, _sort)
        : _sortItems(filteredInProgress, false, _sort));
    final displayUpNext = clamp(_timeBudget != null
        ? _sortBudgetItems(upNextFitting, _timeBudget!, false, _sort)
        : _sortItems(filteredUpNext, false, _sort));
    final displayRecentlyCompleted = _timeBudget == null
        ? clamp(_sortItems(filteredRecentlyCompleted, false, _sort))
        : const <MediaItem>[];

    // "type" mode: одна секция на вид медиа.
    final typeGroups = <({String key, String label, List<MediaItem> items})>[];
    if (_groupByMode == homeGroupType) {
      final pool = _timeBudget != null
          ? [...inProgressFitting, ...upNextFitting]
          : [...filteredInProgress, ...filteredUpNext, ...filteredRecentlyCompleted];
      final buckets = <String, List<MediaItem>>{};
      for (final item in _sortItems(pool, false, _sort)) {
        buckets.putIfAbsent(_typeKey(item), () => <MediaItem>[]).add(item);
      }
      final entries = buckets.entries.toList()
        ..sort((a, b) => _typeOrder(a.key).compareTo(_typeOrder(b.key)));
      for (final entry in entries) {
        final items = entry.value.length > limit
            ? entry.value.sublist(0, limit)
            : entry.value;
        typeGroups.add((
          key: entry.key,
          label: _typeLabel(entry.key),
          items: items,
        ));
      }
    }

    // "none" mode: единый поток без заголовков.
    List<MediaItem> unifiedList = const <MediaItem>[];
    if (_groupByMode == homeGroupNone) {
      final pool = _timeBudget != null
          ? [...inProgressFitting, ...upNextFitting]
          : [...filteredInProgress, ...filteredUpNext, ...filteredRecentlyCompleted];
      unifiedList = clamp(_sortItems(pool, false, _sort));
    }

    final staleCount =
        _inProgress.where((item) => isStaleInProgress(item)).length;

    return SliverMainAxisGroup(slivers: [
      // Панель управления.
      if ((!_loading && _loadError == null) ||
          _hasLoaded ||
          _inProgress.isNotEmpty ||
          _upNext.isNotEmpty ||
          _recentlyCompleted.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _ControlPanel(
            state: this,
            t: t,
            th: TsundokuTheme.of(context),
            filteredTotal: filteredTotal,
            hasActiveFilters: hasActiveFilters,
            staleCount: staleCount,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],

      // Сводка при активном фильтре времени.
      if (!_loading &&
          _loadError == null &&
          _timeBudget != null &&
          totalFitting > 0) ...[
        SliverToBoxAdapter(
          child: _TimeBudgetSummary(
            t: t,
            th: TsundokuTheme.of(context),
            totalFitting: totalFitting,
            totalFinishable: totalFinishable,
            onReset: () => setState(() => _timeBudget = null),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],

      // Состояния + секции.
      if (_loading &&
          _inProgress.isEmpty &&
          _upNext.isEmpty &&
          _recentlyCompleted.isEmpty)
        MediaGrid(items: const <MediaItem>[], loading: true)
      else if (_loadError != null &&
          _inProgress.isEmpty &&
          _upNext.isEmpty &&
          _recentlyCompleted.isEmpty)
        MediaGrid(
            items: const <MediaItem>[], error: _loadError, onRetry: _refresh)
      else if (filteredTotal == 0)
        MediaGrid(items: const <MediaItem>[])
      else if (_timeBudget != null && totalFitting == 0)
        SliverToBoxAdapter(
          child: _TimeBudgetEmpty(
            t: t,
            th: TsundokuTheme.of(context),
            label: _activeBudgetLabel(t),
            onReset: () => setState(() => _timeBudget = null),
          ),
        )
      else if (_groupByMode == homeGroupType)
        for (var i = 0; i < typeGroups.length; i++) ...[
          if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 16)),
          _homeSectionSliver(typeGroups[i].items, typeGroups[i].label,
              t: t, staleCount: staleCount),
        ]
      else if (_groupByMode == homeGroupNone)
        MediaGrid(
          items: unifiedList,
          timeBudget: _timeBudget,
          onOpen: widget.onOpen,
          onProgress: _updateProgress,
          onProgressCommitted: widget.onMediaChanged,
          onStatusChange: _handleStatusChange,
          onDelete: _removeItem,
          onEdit: widget.onEdit,
          onEpisodeStep: _stepEpisode,
        )
      else ...[
        if (displayInProgress.isNotEmpty)
          _homeSectionSliver(
              displayInProgress, statusLabel(MediaStatus.inProgress, t),
              isProgressSection: true, t: t, staleCount: staleCount),
        if (displayInProgress.isNotEmpty &&
            (displayUpNext.isNotEmpty ||
                (_timeBudget == null && displayRecentlyCompleted.isNotEmpty)))
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (displayUpNext.isNotEmpty)
          _homeSectionSliver(displayUpNext, statusLabel(MediaStatus.planned, t),
              t: t, staleCount: staleCount),
        if (displayUpNext.isNotEmpty &&
            (_timeBudget == null && displayRecentlyCompleted.isNotEmpty))
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (_timeBudget == null && displayRecentlyCompleted.isNotEmpty)
          _homeSectionSliver(displayRecentlyCompleted,
              statusLabel(MediaStatus.completed, t),
              t: t, staleCount: staleCount),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ]);
  }

  Widget _homeSectionSliver(
    List<MediaItem> items,
    String title, {
    bool isProgressSection = false,
    required I18nDictionary t,
    required int staleCount,
  }) {
    final th = TsundokuTheme.of(context);
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16), // space-y-4
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 25, // text-[25px]
                      fontWeight: FontWeight.w700, // font-bold
                      letterSpacing: 0.625, // tracking-wide
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12), // gap-3
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 2), // px-2.5 py-0.5
                    decoration: BoxDecoration(
                      color: th.bgCard, // bg-card-hover ≈ bg-card
                      borderRadius: BorderRadius.circular(999), // rounded-full
                    ),
                    child: Text(
                      '${items.length}',
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        color: th.textMuted, // text-muted
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (isProgressSection && staleCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _StaleBadge(
                        t: t,
                        th: th,
                        count: staleCount,
                        onTap: widget.onOpenStaleBacklog,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      MediaGrid(
        items: items,
        timeBudget: _timeBudget,
        forceFlat: _showAll,
        onOpen: widget.onOpen,
        onProgress: _updateProgress,
        onProgressCommitted: widget.onMediaChanged,
        onStatusChange: _handleStatusChange,
        onDelete: _removeItem,
        onEdit: widget.onEdit,
        onEpisodeStep: _stepEpisode,
      ),
    ]);
  }

  String _activeBudgetLabel(I18nDictionary t) {
    final budget = _timeBudget;
    if (budget == null) return '';
    const options = <int?>[null, 15, 30, 45, 60, 90, 120];
    final labels = <String>[
      t.tr('timeBudget.options.all'),
      t.tr('timeBudget.options.m15'),
      t.tr('timeBudget.options.m30'),
      t.tr('timeBudget.options.m45'),
      t.tr('timeBudget.options.h1'),
      t.tr('timeBudget.options.h1_5'),
      t.tr('timeBudget.options.h2_plus'),
    ];
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      if (o != null && o == budget) return labels[i];
    }
    return formatTimeBudgetChip(budget, locale: ref.read(i18nProvider).wire);
  }

  // ------------------------------------------------------------------
  // Эффекты.
  // ------------------------------------------------------------------

  /// $effect(fetch) — гвард ключом (решение #39).
  void _runFetchEffect() {
    final promoted = ref.read(navigationCategoriesProvider);
    final key = '${widget.refreshKey}|$_sort|$_groupByMode|'
        '${promoted.map((p) => p.id).join(',')}';
    if (key == _lastFetchEffectKey) return;
    _lastFetchEffectKey = key;

    if (_prevRefreshKey != null && widget.refreshKey != _prevRefreshKey) {
      homeCache.invalidate(homeKey);
    }
    _prevRefreshKey = widget.refreshKey;
    final isInitial = !_hasLoaded;
    unawaited(_loadSections(++_requestSequence, isInitial));
  }

  /// Страховка «Синхронизации» без активных задач: тихий контрольный рефетч через 2 секунды.
  void _runStuckReloadEffect() {
    final jobs = ref.read(jobsClientProvider);
    final hasActiveJobs = jobs.jobs.any(isActiveJob);
    final hasStuck = [_inProgress, _upNext, _recentlyCompleted]
        .any((list) => list.any((item) => item.syncStatus == SyncStatus.syncing));
    if (hasActiveJobs || !hasStuck) {
      _stuckReloadTimer?.cancel();
      _stuckReloadTimer = null;
      return;
    }
    final revisionKey = widget.refreshKey * 100000 + jobs.settledVersion;
    if (_stuckReloadRevision == revisionKey || _stuckReloadTimer != null) return;
    _stuckReloadTimer = Timer(const Duration(seconds: 2), () {
      _stuckReloadTimer = null;
      if (!mounted) return;
      final currentJobs = ref.read(jobsClientProvider);
      if (currentJobs.jobs.any(isActiveJob)) return;
      final stillStuck = [_inProgress, _upNext, _recentlyCompleted]
          .any((list) => list.any((item) => item.syncStatus == SyncStatus.syncing));
      if (!stillStuck) return;
      _stuckReloadRevision = revisionKey;
      homeCache.invalidate(homeKey);
      _refresh();
    });
  }

  Future<void> _loadSections(int sequence, bool showLoading) async {
    _skeletonTimer?.cancel();
    if (showLoading &&
        homeCache.peek(homeKey) == null &&
        _inProgress.isEmpty &&
        _upNext.isEmpty &&
        _recentlyCompleted.isEmpty) {
      _skeletonTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted &&
            sequence == _requestSequence &&
            homeCache.peek(homeKey) == null &&
            _inProgress.isEmpty &&
            _upNext.isEmpty &&
            _recentlyCompleted.isEmpty) {
          setState(() => _loading = true);
        }
      });
    }
    setState(() => _loadError = null);

    try {
      // Compact: фиксированный щедрый пул (60) — resize не рефетчит; All —
      // до серверного потолка (500).
      final fetchLimit = _showAll ? 500 : 60;
      final sortParams = _sortQuery(_sort);
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.getMedia(MediaFilters(
            status: MediaStatus.inProgress,
            limit: fetchLimit,
            sortBy: sortParams.$1,
            sortOrder: sortParams.$2)),
        api.getMedia(MediaFilters(
            status: MediaStatus.planned,
            limit: fetchLimit,
            sortBy: sortParams.$1,
            sortOrder: sortParams.$2)),
        api.getMedia(MediaFilters(
            status: MediaStatus.completed,
            limit: fetchLimit,
            sortBy: sortParams.$1,
            sortOrder: sortParams.$2)),
      ]);

      if (!mounted) return;
      if (sequence == _requestSequence) {
        _skeletonTimer?.cancel();
        _hasLoaded = true;
        final active = results[0];
        final planned = results[1];
        final completed = results[2];
        final container = ProviderScope.containerOf(context, listen: false);
        // Anti-stale: pending optimistic значения штампуются на входящие.
        reconcileListProgress(container, active);
        reconcileListProgress(container, planned);
        reconcileListProgress(container, completed);
        // recentlyCompleted сортируется локально (rating/title/oldest/finish).
        completed.sort((left, right) {
          if (_sort == 'rating') {
            return ((right.score ?? 0) - (left.score ?? 0)).round();
          }
          if (_sort == 'title') {
            return left.title.compareTo(right.title);
          }
          if (_sort == 'oldest') {
            final leftTime = DateTime.tryParse(left.finishedAt ?? '') ??
                DateTime.tryParse(left.createdAt) ??
                DateTime(0);
            final rightTime = DateTime.tryParse(right.finishedAt ?? '') ??
                DateTime.tryParse(right.createdAt) ??
                DateTime(0);
            return leftTime.millisecondsSinceEpoch -
                rightTime.millisecondsSinceEpoch;
          }
          final leftTime =
              DateTime.tryParse(left.finishedAt ?? '')?.millisecondsSinceEpoch ?? 0;
          final rightTime =
              DateTime.tryParse(right.finishedAt ?? '')?.millisecondsSinceEpoch ?? 0;
          return rightTime - leftTime;
        });
        setState(() {
          _inProgress = active;
          _upNext = planned;
          _recentlyCompleted = completed;
          homeCache.set(
              homeKey,
              HomePayload(
                  inProgress: _inProgress,
                  upNext: _upNext,
                  recentlyCompleted: _recentlyCompleted));
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (sequence == _requestSequence) {
        _skeletonTimer?.cancel();
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  /// sortFilters: сервер знает плоские колонки; клиент досортировывает.
  (SortBy, SortOrder) _sortQuery(String value) {
    switch (value) {
      case 'oldest':
        return (SortBy.createdAt, SortOrder.asc);
      case 'rating':
        return (SortBy.score, SortOrder.desc);
      case 'title':
        return (SortBy.title, SortOrder.asc);
      default: // updated/created → newest-first shape
        return (SortBy.createdAt, SortOrder.desc);
    }
  }

  void _refresh() {
    unawaited(_loadSections(++_requestSequence, false));
  }

  Future<void> _updateProgress(String id, int currentProgress) async {
    List<MediaItem> updateInList(List<MediaItem> list) => list.map((item) {
          if (item.id != id) return item;
          if (item.type == MediaType.game) {
            return item.copyWithFields(hoursPlayed: currentProgress);
          }
          if (item.type == MediaType.book) {
            final isNovel =
                item.format == 'light_novel' || item.format == 'web_novel';
            return isNovel
                ? item.copyWithFields(currentChapter: currentProgress)
                : item.copyWithFields(currentPage: currentProgress);
          }
          if (item.type == MediaType.manga) {
            return item.copyWithFields(currentChapter: currentProgress);
          }
          return item;
        }).toList();
    setState(() {
      _inProgress = updateInList(_inProgress);
      _upNext = updateInList(_upNext);
      _recentlyCompleted = updateInList(_recentlyCompleted);
      homeCache.set(
          homeKey,
          HomePayload(
              inProgress: _inProgress,
              upNext: _upNext,
              recentlyCompleted: _recentlyCompleted));
    });
    await ref.read(apiClientProvider).setProgress(id, currentProgress);
  }

  Future<void> _removeItem(MediaItem item) async {
    final prevInProgress = _inProgress;
    final prevUpNext = _upNext;
    final prevCompleted = _recentlyCompleted;

    setState(() {
      _inProgress = _inProgress.where((i) => i.id != item.id).toList();
      _upNext = _upNext.where((i) => i.id != item.id).toList();
      _recentlyCompleted =
          _recentlyCompleted.where((i) => i.id != item.id).toList();
      homeCache.set(
          homeKey,
          HomePayload(
              inProgress: _inProgress,
              upNext: _upNext,
              recentlyCompleted: _recentlyCompleted));
    });

    final t = ref.read(tProvider);
    try {
      await ref.read(apiClientProvider).deleteMedia(item.id);
      widget.onMediaChanged();
    } catch (_) {
      setState(() {
        _inProgress = prevInProgress;
        _upNext = prevUpNext;
        _recentlyCompleted = prevCompleted;
        homeCache.set(
            homeKey,
            HomePayload(
                inProgress: _inProgress,
                upNext: _upNext,
                recentlyCompleted: _recentlyCompleted));
      });
      showToast(
        ref,
        ToastOptions(
          title: t.tr('errors.unexpected'),
          description: t.tr('toast.descRetry'),
          type: ToastType.error,
        ),
      );
    }
  }

  void _stepEpisode(MediaItem item, int newWatched) {
    if (item.type != MediaType.tvshow) return;
    // Только рефреш идентичности секций (optimistic-стор владеет значением).
    setState(() {
      _inProgress = [..._inProgress];
    });
  }

  void _handleStatusChange(MediaItem item, MediaStatus newStatus) {
    setState(() {
      _inProgress = _inProgress.where((x) => x.id != item.id).toList();
      _upNext = _upNext.where((x) => x.id != item.id).toList();
      _recentlyCompleted =
          _recentlyCompleted.where((x) => x.id != item.id).toList();

      final updated = item.copyWithFields(status: newStatus);
      if (newStatus == MediaStatus.inProgress) {
        _inProgress = [updated, ..._inProgress];
      } else if (newStatus == MediaStatus.planned) {
        _upNext = [updated, ..._upNext];
      } else if (newStatus == MediaStatus.completed) {
        _recentlyCompleted = [updated, ..._recentlyCompleted];
      }
      homeCache.set(
          homeKey,
          HomePayload(
              inProgress: _inProgress,
              upNext: _upNext,
              recentlyCompleted: _recentlyCompleted));
    });
  }

  // ------------------------------------------------------------------
  // Публичные апдейтеры для панели (setState — protected, вызовы идут из
  // _ControlPanel).
  // ------------------------------------------------------------------
  void updateGroupingMode(String value) {
    setState(() => _groupByMode = value);
  }

  void updateCategory(String value) {
    setState(() => _selectedCategory = value);
  }

  void updateTimeBudget(int? value) {
    setState(() => _timeBudget = value);
  }

  void toggleShowAll() {
    setState(() => _showAll = !_showAll);
  }

  void updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _debouncedSearch = value; // поиск главной без debounce в чипах
    });
    // 200ms debounce обновляет debouncedSearch (как $effect в Svelte).
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _debouncedSearch = value);
    });
  }

  void updateSort(String value) {
    setState(() => _sort = value);
    if (value == 'oldest' || value == 'rating' || value == 'title') {
      unawaited(ref.read(uiSettingsProvider.notifier).setSortOption(value));
    }
  }

  void resetFilters() {
    setState(() {
      _searchQuery = '';
      _debouncedSearch = '';
      _selectedCategory = 'all';
      _timeBudget = null;
    });
  }

  /// 🎲 «Что выбрать?»: случайный тайтл с экрана.
  void _pickRandomTitle() {
    final pool = [..._displayInProgressSafe(), ..._upNextSafe()];
    final source = pool.isNotEmpty ? pool : _recentlyCompleted;
    if (source.isEmpty) {
      showToast(
        ref,
        ToastOptions(
          title: ref.read(tProvider).tr('home.randomEmpty'),
          description: ref.read(tProvider).tr('toast.descNoItems'),
          type: ToastType.warning,
        ),
      );
      return;
    }
    final pick = source[math.Random().nextInt(source.length)];
    showToast(
      ref,
      ToastOptions(
        title: ref
            .read(tProvider)
            .tf('home.randomPickToast', [pick.title]),
        description: ref.read(tProvider).tr('toast.descActionDone'),
      ),
    );
    widget.onOpen(pick);
  }

  // display-списки для рандомайзера (без пересортировки — берём текущие).
  List<MediaItem> _displayInProgressSafe() => _inProgress
      .where((item) =>
          _matchesSearch(item, _debouncedSearch) && _matchesCategory(item))
      .toList();
  List<MediaItem> _upNextSafe() => _upNext
      .where((item) =>
          _matchesSearch(item, _debouncedSearch) && _matchesCategory(item))
      .toList();

  /// window-событие tsundoku:random-pick → в Dart вызывает App (контекст-меню
  /// desktop) через GlobalKey/state — колбек [randomPick] публичный.
  void randomPick() => _pickRandomTitle();
}

/// Провайдер-триггер поискового дебаунса (ref.listen в build — заглушка,
/// реальный debounce в _SearchDelegate ниже).
final _homeSearchDebounceProvider = Provider<int>((ref) => 0);

/// 🕸 stale-бейдж: amber-кнопка «N устаревших».
class _StaleBadge extends StatelessWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final int count;
  final VoidCallback? onTap;

  const _StaleBadge({
    required this.t,
    required this.th,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 4), // px-2.5 py-1
          decoration: BoxDecoration(
            color: const Color(0x1AF59E0B), // bg-amber-500/10
            borderRadius: BorderRadius.circular(999), // rounded-full
            border: Border.all(
                color: const Color(0x4DF59E0B)), // border-amber-500/30
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🕸'),
              const SizedBox(width: 6), // gap-1.5
              Text(
                '$count ${t.tr('staleTriage.staleBadge')}',
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xFFFBBF24), // text-amber-400
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сводка времени: accent-рамка + reset.
class _TimeBudgetSummary extends StatelessWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final int totalFitting;
  final int totalFinishable;
  final VoidCallback onReset;

  const _TimeBudgetSummary({
    required this.t,
    required this.th,
    required this.totalFitting,
    required this.totalFinishable,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // px-4 py-2.5
        decoration: BoxDecoration(
          color: th.accent.withAlpha(26), // bg-accent/10
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(
              color: th.accent.withAlpha(77)), // border-accent/30
        ),
        child: Row(
          children: [
            Container(
              width: 24, // h-6 w-6
              height: 24,
              decoration: BoxDecoration(
                color: th.accent.withAlpha(51), // bg-accent/20
                borderRadius: BorderRadius.circular(8), // rounded-lg
              ),
              child: const Icon(LucideIcons.clock3,
                  size: 14, color: Color(0xFFA5B4FC)),
            ),
            const SizedBox(width: 8), // gap-2
            Expanded(
              child: Text(
                t.tf('timeBudget.summary', [totalFitting, totalFinishable]),
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: th.textPrimary, // text-ink
                ),
              ),
            ),
            GestureDetector(
              onTap: onReset,
              child: Text(
                t.tr('timeBudget.reset'),
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: th.textMuted, // text-muted
                  decoration: TextDecoration.underline, // underline
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пустой экран бюджета времени.
class _TimeBudgetEmpty extends StatelessWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final String label;
  final VoidCallback onReset;

  const _TimeBudgetEmpty({
    required this.t,
    required this.th,
    required this.label,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 240), // min-h-60
      decoration: BoxDecoration(
        color: th.bgSurface.withAlpha(153), // bg-surface/60
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
      ),
      padding: const EdgeInsets.all(32), // p-8
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48, // h-12 w-12
            height: 48,
            decoration: BoxDecoration(
              color: th.bgCard, // bg-card
              borderRadius: BorderRadius.circular(12), // rounded-xl
            ),
            child: Icon(
              LucideIcons.clock3, // Clock3 size={24}
              size: 24,
              color: th.accentSoft, // text-accent-soft
            ),
          ),
          const SizedBox(height: 12), // gap-3
          Text(
            t.tr('timeBudget.emptyTitle'),
            style: TextStyle(
              fontWeight: FontWeight.w600, // font-semibold
              color: th.textPrimary, // text-ink
            ),
          ),
          const SizedBox(height: 4), // mt-1
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
            child: Text(
              t.tf('timeBudget.emptyHint', [label]),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14, // text-sm
                color: th.textMuted, // text-muted
              ),
            ),
          ),
          const SizedBox(height: 8), // mt-2
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6), // px-4 py-1.5
              decoration: BoxDecoration(
                color: th.accent, // bg-accent
                borderRadius: BorderRadius.circular(8), // rounded-lg
              ),
              child: Text(
                t.tr('timeBudget.reset'),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Панель управления главной: группировка/категории/время/рандом + счётчик +
/// поиск/лимит/сортировка + чипы фильтров.
class _ControlPanel extends ConsumerWidget {
  final _HomeViewState state;
  final I18nDictionary t;
  final TsundokuTheme th;
  final int filteredTotal;
  final bool hasActiveFilters;
  final int staleCount;

  const _ControlPanel({
    required this.state,
    required this.t,
    required this.th,
    required this.filteredTotal,
    required this.hasActiveFilters,
    required this.staleCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = this.state;

    final groupingOptions = <PopoverOption<String>>[
      PopoverOption(
          value: homeGroupStatus,
          label: t.tr('home.groupByStatus'),
          leading: groupModeIcon(homeGroupStatus)),
      PopoverOption(
          value: homeGroupType,
          label: t.tr('home.groupByType'),
          leading: groupModeIcon(homeGroupType)),
      PopoverOption(
          value: homeGroupNone,
          label: t.tr('home.groupNone'),
          leading: groupModeIcon(homeGroupNone)),
    ];

    final promoted = ref.watch(navigationCategoriesProvider);
    final categoryOptions = <PopoverOption<String>>[
      PopoverOption(value: 'all', label: t.tr('home.allCategories')),
      for (final sub in promoted
          .where((s) => promotedParentType(s) == 'anime'))
        PopoverOption(value: sub.id, label: sub.label),
      PopoverOption(value: 'anime', label: t.tr('navigation.anime')),
      PopoverOption(value: 'manga', label: t.tr('navigation.manga')),
      PopoverOption(value: 'game', label: t.tr('navigation.game')),
      PopoverOption(value: 'movie', label: t.tr('navigation.movie')),
      PopoverOption(value: 'tvshow', label: t.tr('navigation.tvshow')),
      PopoverOption(value: 'book', label: t.tr('navigation.book')),
      for (final sub in promoted.where((s) =>
          ['book', 'manga', 'game', 'movie', 'tvshow']
              .contains(promotedParentType(s))))
        PopoverOption(value: sub.id, label: sub.label),
    ];

    final timeBudgetOptions = <PopoverOption<int?>>[
      PopoverOption(value: null, label: t.tr('timeBudget.options.all')),
      PopoverOption(value: 15, label: t.tr('timeBudget.options.m15')),
      PopoverOption(value: 30, label: t.tr('timeBudget.options.m30')),
      PopoverOption(value: 45, label: t.tr('timeBudget.options.m45')),
      PopoverOption(value: 60, label: t.tr('timeBudget.options.h1')),
      PopoverOption(value: 90, label: t.tr('timeBudget.options.h1_5')),
      PopoverOption(value: 120, label: t.tr('timeBudget.options.h2_plus')),
    ];

    final sortOptions = <PopoverOption<String>>[
      PopoverOption(value: 'updated', label: t.tr('sort.updated'), leading: homeSortIcon('updated')),
      PopoverOption(value: 'created', label: t.tr('sort.created'), leading: homeSortIcon('created')),
      PopoverOption(value: 'oldest', label: t.tr('sort.oldest'), leading: homeSortIcon('oldest')),
      PopoverOption(value: 'rating', label: t.tr('sort.rating'), leading: homeSortIcon('rating')),
      PopoverOption(value: 'title', label: t.tr('sort.title'), leading: homeSortIcon('title')),
    ];

    String categoryLabel(String value) {
      for (final option in categoryOptions) {
        if (option.value == value) return option.label;
      }
      return value;
    }

    final pad = MediaQuery.sizeOf(context).width >= 640 ? 14.0 : 12.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: th.bgSurface, // #12151c
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(color: th.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.slidersHorizontal,
                      size: 16,
                      color: th.textMuted,
                    ),
                    const SizedBox(width: 8),
                    // Группировка.
                    TsundokuPopoverMenu<String>(
                      id: 'home-grouping',
                      options: groupingOptions,
                      selected: state._groupByMode,
                      onSelect: (value) {
                        state.updateGroupingMode(value);
                        unawaited(ref
                            .read(uiSettingsProvider.notifier)
                            .setGroupByType(value == homeGroupType));
                      },
                      label: t.tr('home.grouping'),
                      placement: PopoverPlacement.bottomStart,
                      openOnHover: true,
                      closeDelay: 220,
                      trigger: (context, ctx) => _PanelIconButton(
                        tooltip: t.tr('home.grouping'),
                        icon: groupModeIcon(state._groupByMode),
                        th: th,
                        showTooltip: !ctx.isOpen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Категории.
                    TsundokuPopoverMenu<String>(
                      id: 'home-category',
                      options: categoryOptions,
                      selected: state._selectedCategory,
                      onSelect: (value) => state.updateCategory(value),
                      label: t.tr('home.categories'),
                      placement: PopoverPlacement.bottomStart,
                      openOnHover: true,
                      closeDelay: 220,
                      trigger: (context, ctx) => _PanelTextButton(
                        label: categoryLabel(state._selectedCategory),
                        th: th,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Фильтр времени.
                    TsundokuPopoverMenu<int?>(
                      id: 'home-time-budget',
                      options: timeBudgetOptions,
                      selected: state._timeBudget,
                      onSelect: (value) => state.updateTimeBudget(value),
                      label: t.tr('timeBudget.filterTitle'),
                      placement: PopoverPlacement.bottomStart,
                      openOnHover: true,
                      closeDelay: 220,
                      initiallyOpen: state.widget.initiallyOpenTimeBudget,
                      trigger: (context, ctx) => state._timeBudget != null
                          ? _PanelTextButton(
                              label: formatTimeBudgetChip(state._timeBudget!,
                                  locale: ref.watch(i18nProvider).wire),
                              icon: LucideIcons.clock3,
                              th: th,
                            )
                          : _PanelIconButton(
                              tooltip: t.tr('timeBudget.filterTitle'),
                              icon: LucideIcons.clock3,
                              th: th,
                              showTooltip: !ctx.isOpen,
                            ),
                    ),
                    const SizedBox(width: 8),
                    // 🎲 Случайный тайтл.
                    Tooltip(
                      message: t.tr('home.randomPick'),
                      child: GestureDetector(
                        onTap: state.randomPick,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: th.bgElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withAlpha(26)), // white/10
                          ),
                          child: Icon(
                            LucideIcons.dices,
                            size: 16,
                            color: th.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Счётчик по центру.
              if (!state._loading && state._loadError == null)
                TsundokuTotalBadge(total: filteredTotal)
              else
                const SizedBox.shrink(),
              // Поиск + лимит + сортировка.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: _HomeSearchField(state: state, th: th),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Лимит секций: role="switch".
                    Tooltip(
                      message: t.tr('home.limitTooltip'),
                      child: GestureDetector(
                        onTap: state.toggleShowAll,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: state._showAll
                                ? const Color(0x336366F1) // bg-indigo-500/20
                                : th.bgElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: state._showAll
                                  ? const Color(0x996366F1) // indigo-500/60
                                  : Colors.white.withAlpha(26), // white/10
                            ),
                          ),
                          child: Center(
                            child: Text(
                              state._showAll
                                  ? t.tr('home.limitAll')
                                  : '${state._sectionLimit}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: state._showAll
                                    ? const Color(0xFFA5B4FC) // indigo-300
                                    : th.textPrimary, // text-ink
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TsundokuPopoverMenu<String>(
                      id: 'home-sort',
                      options: sortOptions,
                      selected: state._sort,
                      onSelect: (value) => state.updateSort(value),
                      label: t.tr('sort.label'),
                      placement: PopoverPlacement.bottomEnd,
                      openOnHover: true,
                      closeDelay: 220,
                      trigger: (context, ctx) => _PanelIconButton(
                        tooltip: t.tr('sort.label'),
                        icon: homeSortIcon(state._sort),
                        th: th,
                        showTooltip: !ctx.isOpen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Чипы активных фильтров.
          if (hasActiveFilters)
            Container(
              margin: const EdgeInsets.only(top: 8), // pt-2
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0x0DFFFFFF))), // white/5
              ),
              child: Wrap(
                spacing: 8, // gap-2
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (state._debouncedSearch.isNotEmpty)
                    _FilterChip(
                      th: th,
                      icon: LucideIcons.search,
                      label: '"${state._debouncedSearch}"',
                      onRemove: () => state.resetFilters(),
                    ),
                  if (state._selectedCategory != 'all')
                    _FilterChip(
                      th: th,
                      label: categoryLabel(state._selectedCategory),
                      accent: true,
                      onRemove: () => state.updateCategory('all'),
                    ),
                  if (state._timeBudget != null)
                    _FilterChip(
                      th: th,
                      label:
                          '⏱ ${formatTimeBudgetChip(state._timeBudget!, locale: ref.watch(i18nProvider).wire)}',
                      indigo: true,
                      onRemove: () => state.updateTimeBudget(null),
                    ),
                  GestureDetector(
                    onTap: state.resetFilters,
                    child: Text(
                      t.tr('home.resetFilters'),
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        color: th.textMuted, // text-muted
                        decoration: TextDecoration.underline, // underline
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Панельные кнопки: bg-field border-white/10 rounded-lg h-9 (icon 18 /
/// text-xs font-semibold + ChevronDown).
class _PanelIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final TsundokuTheme th;
  final bool showTooltip;

  const _PanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.th,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = IgnorePointer(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: th.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(26)), // white/10
        ),
        child: Icon(icon, size: 16, color: th.textMuted),
      ),
    );
    if (showTooltip && tooltip.isNotEmpty) {
      return Tooltip(
        message: tooltip,
        child: body,
      );
    }
    return body;
  }
}

class _PanelTextButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final TsundokuTheme th;

  const _PanelTextButton({required this.label, this.icon, required this.th});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: th.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(26)), // white/10
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: th.textPrimary),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: th.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 14, color: th.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Чип фильтра с ✕.
class _FilterChip extends StatelessWidget {
  final TsundokuTheme th;
  final String label;
  final IconData? icon;
  final bool accent;
  final bool indigo;
  final VoidCallback onRemove;

  const _FilterChip({
    required this.th,
    required this.label,
    required this.onRemove,
    this.icon,
    this.accent = false,
    this.indigo = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = indigo
        ? const Color(0x4D6366F1) // indigo-500/30
        : accent
            ? th.accent.withAlpha(77) // accent/30
            : Colors.white.withAlpha(26); // white/10
    final bg = indigo
        ? const Color(0x266366F1) // indigo-500/15
        : accent
            ? th.accent.withAlpha(38) // accent/15
            : Colors.white.withAlpha(13); // white/5
    final fg = indigo
        ? const Color(0xFFA5B4FC) // indigo-300
        : accent
            ? th.accentSoft // text-accent-soft
            : const Color(0xFFCBD5E1); // text-slate-300

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // px-2.5 py-1
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6), // rounded-md
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4), // gap-1
          ],
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Text(
              '✕',
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле поиска главной: 200ms debounce → debouncedSearch.
class _HomeSearchField extends StatefulWidget {
  final _HomeViewState state;
  final TsundokuTheme th;

  const _HomeSearchField({required this.state, required this.th});

  @override
  State<_HomeSearchField> createState() => _HomeSearchFieldState();
}

class _HomeSearchFieldState extends State<_HomeSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.state._searchQuery);
  Timer? _debounce;

  @override
  void didUpdateWidget(_HomeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state._searchQuery != oldWidget.state._searchQuery &&
        widget.state._searchQuery != _controller.text) {
      _controller.text = widget.state._searchQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    final hint =
        widget.state.ref.read(tProvider).tr('home.searchPlaceholder');
    return TsundokuTextField(
      controller: _controller,
      height: 36,
      onChanged: widget.state.updateSearchQuery,
      placeholder: hint,
      prefixIcon: Icon(
        LucideIcons.search,
        size: 16,
        color: th.textMuted,
      ),
    );
  }
}
