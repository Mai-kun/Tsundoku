/// 1:1 port of `mediatracker-ui/src/views/CategoryView.svelte`.
///
/// Вью категории: FilterBar (статус/сортировка/группировка/поиск с
/// пер-категориальным сохранением состояния), SWR-кэш с ремоунтом,
/// sequence-загрузка (500ms delay при поиске), статус-секции/франшизные
/// группы/одна сетка, stuck-reload «Синхронизации», optimistic
/// прогресс/удаление/статус.
///
/// MediaGrid/SectionRow — слайверы (решение #37) → вью тоже возвращает
/// СПИСОК СЛАЙВЕРОВ; страница собирает их в общий CustomScrollView
/// (#main-scroll).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/filter-and-sort/filter_bar.dart';
import '../shared/api/api.dart';
import '../shared/api/jobs_client.dart';
import '../shared/api/navigation_categories.dart';
import '../shared/i18n/index.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';
import '../shared/ui/toast.dart';
import '../shared/utils/swr_cache.dart';
import '../shared/utils/ui_settings.dart';
import '../features/update-progress/optimistic_progress.dart';
import '../widgets/media-grid/media_grid.dart';
import '../widgets/media-grid/section_row.dart';
import 'category_model.dart';

/// Модульное состояние (script module): переживает ремоунты вью.
final Map<String, SavedCategoryState> savedCategoryState =
    <String, SavedCategoryState>{};
final SwrCache<List<MediaItem>> categoryCache = SwrCache<List<MediaItem>>();

class SavedCategoryState {
  final StatusFilter status;
  final LibrarySort sort;
  final GroupBy groupBy;
  final String search;

  const SavedCategoryState({
    required this.status,
    required this.sort,
    required this.groupBy,
    required this.search,
  });
}

/// Франшизная группа (derived-структура).
class FranchiseGroup {
  final String name;
  final List<MediaItem> items;

  const FranchiseGroup({required this.name, required this.items});
}

/// Строка статус-секции 1-в-1 со statusSections.
class _CategoryViewSections {
  final I18nDictionary t;
  _CategoryViewSections(this.t);

  List<StatusSection> build() => [
        StatusSection(
            status: MediaStatus.inProgress, title: t.tr('status.inProgress')),
        StatusSection(
            status: MediaStatus.planned, title: t.tr('status.planned')),
        StatusSection(
            status: MediaStatus.completed, title: t.tr('status.completed')),
        StatusSection(
            status: MediaStatus.onHold, title: t.tr('status.paused')),
        StatusSection(
            status: MediaStatus.dropped, title: t.tr('status.dropped')),
      ];
}

class CategoryView extends ConsumerStatefulWidget {
  final Category category;
  final bool active;
  final int refreshKey;
  final void Function(MediaItem item) onOpen;
  final VoidCallback onMediaChanged;
  final void Function(MediaItem item)? onEdit;

  const CategoryView({
    super.key,
    required this.category,
    this.active = true,
    required this.refreshKey,
    required this.onOpen,
    required this.onMediaChanged,
    this.onEdit,
  });

  @override
  ConsumerState<CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends ConsumerState<CategoryView> {
  StatusFilter _status = const StatusFilter.all();
  LibrarySort _sort = 'newest';
  GroupBy _groupBy = groupByStatus;
  String _search = '';
  List<MediaItem> _allItems = const <MediaItem>[];
  int _totalCount = 0;
  bool _loading = true;
  // ignore: unused_field
  bool _refreshing = false; // фоновый refetch: дим грида + спиннер (см. Пояснения)
  Object? _loadError;
  int _requestSequence = 0;

  Category? _lastLoadedCategory;
  int? _prevRefreshKey;
  int _stuckReloadKey = 0;

  /// таймер 500ms-дебаунса поиска ($effect cleanup).
  Timer? _loadDebounce;

  @override
  void initState() {
    super.initState();
    final initial = categoryCache.peek(widget.category) ?? const <MediaItem>[];
    _allItems = initial;
    _totalCount = initial.length;
    _loading = initial.isEmpty;
    _applySavedState(isInitialMount: true);
  }

  /// $effect.pre: смена категории → сохранить состояние + подставить
  /// кэш/сохранённые фильтры (до отрисовки — stale-список не рендерится).
  void _applySavedState({required bool isInitialMount}) {
    final saved = savedCategoryState[widget.category];
    final settings = ref.read(uiSettingsProvider);
    // statusFilter — строка ('all' | '0'..'4'); 'all' → int.tryParse null.
    final parsedStatus = int.tryParse(settings.statusFilter);
    setState(() {
      _status = saved?.status ??
          (parsedStatus == null
              ? const StatusFilter.all()
              : StatusFilter.status(parsedStatus));
      _sort = saved?.sort ?? settings.sortOption;
      _groupBy = saved?.groupBy ?? groupByStatus;
      _search = saved?.search ?? '';
      final cached = categoryCache.peek(widget.category);
      if (cached != null) {
        _allItems = cached;
        _loading = false;
      } else if (!isInitialMount) {
        // Live-переключение без кэша: loading=false — серый placeholder не
        // мигает, контент встанет после loadItems.
        _loading = false;
      }
    });
  }

  @override
  void didUpdateWidget(CategoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category != oldWidget.category) {
      _applySavedState(isInitialMount: false);
      _lastLoadedCategory = null; // форс перезагрузки ниже
    }
  }

  /// Вью не активна — эффекты не гоняются (Svelte рендерит только active).
  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SliverToBoxAdapter(child: SizedBox.shrink());

    // $effect (fetch): смена категории/refreshKey → invalidate; search/sort
    // пересобирают; promotedCategories() — пересборка при смене снимка.
    ref.listen(navigationCategoriesProvider, (_, _) {});
    _runFetchEffect();
    _runStuckReloadEffect();

    final filteredItems = filterByStatus(
        _allItems, _status.isAll ? 'all' : '${_status.status}');

    return SliverMainAxisGroup(slivers: [
      // FilterBar (только активная категория).
      if (widget.active)
        SliverToBoxAdapter(
          child: FilterBar(
            status: _status,
            sort: _sort,
            groupBy: _groupBy,
            search: _search,
            counts: _countStatuses(_allItems),
            totalCount: _totalCount,
            shownCount: filteredItems.length,
            onStatusChange: _updateStatus,
            onSortChange: _updateSort,
            onGroupByChange: _updateGroupBy,
            onSearchChange: _updateSearch,
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)), // space-y-4
      ..._contentSlivers(filteredItems),
    ]);
  }

  List<Widget> _contentSlivers(List<MediaItem> filteredItems) {
    final t = ref.watch(tProvider);
    // SECTION_ROW_LIMIT: франшизная группировка сворачивается в одну сетку.
    const sectionRowLimit = 40;
    final useSingleGrid =
        filteredItems.length > sectionRowLimit && _groupBy == groupByFranchise;

    Widget mediaGridSliver(List<MediaItem> gridItems) {
      return MediaGrid(
        items: gridItems,
        loading: _loading,
        error: _loadError,
        onRetry: _refresh,
        onOpen: widget.onOpen,
        onProgress: _updateProgress,
        onProgressCommitted: widget.onMediaChanged,
        onStatusChange: _handleItemStatusChange,
        onEpisodeStep: _stepEpisode,
        onDelete: _removeItem,
        onEdit: widget.onEdit,
      );
    }

    if (_loadError != null && _allItems.isEmpty) {
      return [mediaGridSliver(const <MediaItem>[])];
    }
    if (useSingleGrid) {
      return [mediaGridSliver(filteredItems)];
    }
    if (_groupBy == groupByStatus) {
      final sections = _CategoryViewSections(t).build();
      final statusGroups =
          buildStatusGroups(filteredItems, _statusKey(), sections);
      if (statusGroups.isEmpty && !_loading) {
        return [mediaGridSliver(const <MediaItem>[])];
      }
      return [
        for (final group in statusGroups)
          SectionRow(
            key: ValueKey(group.status.value),
            title: group.title,
            items: group.items,
            onRetry: _refresh,
            onOpen: widget.onOpen,
            onProgress: _updateProgress,
            onProgressCommitted: widget.onMediaChanged,
            onStatusChange: _handleItemStatusChange,
            onEpisodeStep: _stepEpisode,
            onDelete: _removeItem,
            onEdit: widget.onEdit,
          ),
      ];
    }
    if (_groupBy == groupByFranchise) {
      final franchiseGroups = _franchiseGroups(filteredItems);
      if (franchiseGroups.isEmpty && !_loading) {
        return [mediaGridSliver(const <MediaItem>[])];
      }
      return [
        for (final group in franchiseGroups)
          SectionRow(
            key: ValueKey(group.name),
            title: group.name,
            items: group.items,
            onRetry: _refresh,
            onOpen: widget.onOpen,
            onProgress: _updateProgress,
            onProgressCommitted: widget.onMediaChanged,
            onStatusChange: _handleItemStatusChange,
            onEpisodeStep: _stepEpisode,
            onDelete: _removeItem,
            onEdit: widget.onEdit,
          ),
      ];
    }
    return [mediaGridSliver(filteredItems)];
  }

  String _statusKey() => _status.isAll ? 'all' : '${_status.status}';

  /// Ключ зависимостей fetch-эффекта (аналог $effect-трекинга: эффект
  /// перезапускается только при реальном изменении входов, не на каждом
  /// rebuild — иначе sequence растёт и ответы отбрасываются).
  String? _lastFetchEffectKey;

  /// $effect: загрузка/инвалидация кэша.
  void _runFetchEffect() {
    final promoted = ref.read(navigationCategoriesProvider);
    final key = '${widget.category}|${widget.refreshKey}|$_search|$_sort|'
        '${promoted.map((p) => p.id).join(',')}';
    if (key == _lastFetchEffectKey) return;
    _lastFetchEffectKey = key;

    final categoryChanged = _lastLoadedCategory != widget.category;
    final revisionChanged =
        _prevRefreshKey != null && widget.refreshKey != _prevRefreshKey;
    _lastLoadedCategory = widget.category;
    _prevRefreshKey = widget.refreshKey;
    if (categoryChanged || revisionChanged) {
      categoryCache.invalidate(widget.category);
    }
    final sequence = ++_requestSequence;
    _loadDebounce?.cancel();
    final delay = _search.trim().isEmpty ? Duration.zero : const Duration(milliseconds: 500);
    _loadDebounce = Timer(delay, () => unawaited(_loadItems(sequence)));
  }

  /// Страховка: «Синхронизация» без активных задач → перезагрузка один раз.
  void _runStuckReloadEffect() {
    final jobs = ref.read(jobsClientProvider);
    if (jobs.jobs.where(isActiveJob).isNotEmpty) return;
    final stuck = _allItems
        .any((item) => item.syncStatus == SyncStatus.syncing);
    if (!stuck) return;
    if (_stuckReloadKey == widget.refreshKey) return;
    _stuckReloadKey = widget.refreshKey;
    _refresh();
  }

  Future<void> _loadItems(int sequence) async {
    // Cached fast-path: кэш уже отрисован pre-эффектом.
    final cached = categoryCache.peek(widget.category);
    if (_search.trim().isEmpty &&
        cached != null &&
        cached.isNotEmpty &&
        identical(_allItems, cached)) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      if (_allItems.isEmpty) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _loadError = null;
    });

    try {
      final filters = categoryFilters(
        widget.category,
        _search,
        _sort,
        promoted: ref.read(navigationCategoriesProvider),
      ).copyWithFields(limit: 500);
      final page = await ref.read(apiClientProvider).getMediaWithCount(filters);
      if (!mounted) return;
      if (sequence == _requestSequence) {
        final found = page.items;
        setState(() {
          _loading = false;
          _refreshing = false;
          _totalCount = page.totalCount;
          // O(1) snapshot check.
          final sameSnapshot = _allItems.length == found.length &&
              (_allItems.isEmpty ||
                  (_allItems.first.updatedAt == found.first.updatedAt &&
                      _allItems.last.updatedAt == found.last.updatedAt));
          if (sameSnapshot) return;
          // Anti-stale: pending optimistic значения штампуются на новые items.
          reconcileListProgress(
              ProviderScope.containerOf(context, listen: false), found);
          _allItems = found;
          if (_search.trim().isEmpty) {
            categoryCache.set(widget.category, found);
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (sequence == _requestSequence) {
        setState(() {
          _loadError = error;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _refresh() {
    categoryCache.invalidate(widget.category);
    unawaited(_loadItems(++_requestSequence));
  }

  Future<void> _updateProgress(String id, int currentProgress) async {
    setState(() {
      _allItems = _allItems.map((item) {
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
      categoryCache.set(widget.category, _allItems);
    });
    await ref.read(apiClientProvider).setProgress(id, currentProgress);
  }

  Map<StatusFilter, int> _countStatuses(List<MediaItem> list) {
    final counts = <StatusFilter, int>{
      const StatusFilter.all(): list.length,
    };
    for (final value in const [
      MediaStatus.planned,
      MediaStatus.inProgress,
      MediaStatus.completed,
      MediaStatus.onHold,
      MediaStatus.dropped,
    ]) {
      counts[StatusFilter.status(value.value)] =
          list.where((item) => item.status == value).length;
    }
    return counts;
  }

  Future<void> _removeItem(MediaItem item) async {
    final prevItems = _allItems;
    setState(() {
      _allItems = _allItems.where((i) => i.id != item.id).toList();
      categoryCache.set(widget.category, _allItems);
    });
    final t = ref.read(tProvider);
    try {
      await ref.read(apiClientProvider).deleteMedia(item.id);
      widget.onMediaChanged();
    } catch (_) {
      setState(() {
        _allItems = prevItems;
        categoryCache.set(widget.category, prevItems);
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

  void _updateStatus(StatusFilter value) {
    setState(() {
      _status = value;
      savedCategoryState[widget.category] = SavedCategoryState(
          status: value, sort: _sort, groupBy: _groupBy, search: _search);
    });
    // uiSettings.setStatusFilter — persist (fire-and-forget).
    unawaited(
        ref.read(uiSettingsProvider.notifier).setStatusFilter(_statusKey()));
  }

  void _updateSort(LibrarySort value) {
    setState(() {
      _sort = value;
      savedCategoryState[widget.category] = SavedCategoryState(
          status: _status, sort: value, groupBy: _groupBy, search: _search);
    });
    unawaited(ref.read(uiSettingsProvider.notifier).setSortOption(value));
  }

  void _updateGroupBy(GroupBy value) {
    setState(() {
      _groupBy = value;
      savedCategoryState[widget.category] = SavedCategoryState(
          status: _status, sort: _sort, groupBy: value, search: _search);
    });
  }

  void _updateSearch(String value) {
    setState(() {
      _search = value;
      savedCategoryState[widget.category] = SavedCategoryState(
          status: _status, sort: _sort, groupBy: _groupBy, search: value);
    });
  }

  void _stepEpisode(MediaItem item, int newWatched) {
    if (item.type != MediaType.tvshow) return;
    // Контроллер владеет optimistic-значением и PUT; зеркало на прокси-
    // объект грида — абсолют, не дельта (иначе двойной счёт кликов).
    ref
        .read(optimisticProgressProvider.notifier)
        .reconcile(item.id, newWatched);
  }

  void _handleItemStatusChange(MediaItem item, MediaStatus newStatus) {
    setState(() {
      _allItems = _allItems
          .map((x) => x.id == item.id ? x.copyWithFields(status: newStatus) : x)
          .toList();
      categoryCache.set(widget.category, _allItems);
    });
  }

  /// Франшизная группировка: franchiseName → префикс по :\-/ → noFranchise.
  List<FranchiseGroup> _franchiseGroups(List<MediaItem> filteredItems) {
    if (_groupBy != groupByFranchise) return const <FranchiseGroup>[];

    final map = <String, List<MediaItem>>{};
    final noFranchise = <MediaItem>[];
    final t = ref.read(tProvider);

    bool hasPrefixSibling(MediaItem item, String prefix) => filteredItems.any(
        (other) =>
            other.id != item.id &&
            other.title
                .trim()
                .toLowerCase()
                .startsWith(prefix.toLowerCase()));

    for (final item in filteredItems) {
      String? name = item.franchiseName?.trim();
      if (name == null || name.isEmpty) {
        final title = item.title.trim();
        final colonIdx = title.indexOf(RegExp(r'[:\-\/]'));
        if (colonIdx > 2) {
          final prefix = title.substring(0, colonIdx).trim();
          if (prefix.length >= 3 &&
              filteredItems.any((other) =>
                  other.id != item.id &&
                  other.title
                      .trim()
                      .toLowerCase()
                      .startsWith(prefix.toLowerCase()))) {
            name = prefix;
          }
        } else if (title.length >= 3) {
          final hasSibling = hasPrefixSibling(item, '$title:');
          if (hasSibling) {
            name = title;
          }
        }
      }

      if (name != null && name.isNotEmpty) {
        map.putIfAbsent(name, () => <MediaItem>[]).add(item);
      } else {
        noFranchise.add(item);
      }
    }

    final groups = <FranchiseGroup>[
      for (final entry in map.entries)
        FranchiseGroup(name: entry.key, items: entry.value),
    ];

    if (noFranchise.isNotEmpty) {
      groups.add(FranchiseGroup(
          name: t.tr('grouping.noFranchise'), items: noFranchise));
    }

    return groups;
  }
}
