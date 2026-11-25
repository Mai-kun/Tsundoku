/// 1:1 port of `mediatracker-ui/src/app/App.svelte`.
///
/// Роутер приложения (AppView-стейт вместо window.history — решение #10):
/// home + категории (портированы) рендерят живые вью; stats/lists/history/
/// calendar/goals/settings/detail/seasons (Фазы 4/5) — заглушки-вью с
/// заголовком (решение #42). Модалки Search/Create/BackgroundJobs/
/// StaleBacklog/FirstRun — Фаза 4/5: триггеры запоминают состояние, рендер
/// появится при портировании (openSearch/openCreate — no-op-хуки).
///
/// Жизненный цикл: loadNavigationCategories + восстановление lastView,
/// offline init, jobsClient.onJobSettled → mediaRevision, глобальные
/// хоткеи (Ctrl+K/Esc), desktop context-menu (random-pick → сигнал-шина).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../features/create-media/create_modal.dart';
import '../features/drop-reason/drop_reason_modal.dart';
import '../features/drop-reason/drop_reason_prompt.dart';
import '../features/import-media/import_modal.dart';
import '../features/lists/create_list_modal.dart';
import '../features/prefetch-details/media_detail_prefetch.dart';
import '../features/search-external/search_modal.dart';
import '../features/settings/first_run_storage_modal.dart';
import '../features/stale-triage/stale_backlog_modal.dart';
import '../shared/api/api.dart';
import '../shared/api/jobs_client.dart';
import '../shared/api/navigation_categories.dart';
import '../shared/i18n/index.dart';
import '../shared/api/offline_mode.dart';
import '../shared/platform/platform.dart';
import '../shared/theme/tsundoku_theme.dart' show buildTsundokuTheme;
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/enums.dart' hide SettingsTab;
import '../shared/types/models.dart';
import '../shared/ui/confirm_modal.dart';
import '../shared/ui/context_menu_controller.dart';
import '../shared/ui/tsundoku_scroll.dart';
import '../shared/ui/toast.dart';
import '../shared/utils/app_exit.dart';
import '../shared/utils/ui_settings.dart';
import '../views/calendar_view.dart';
import '../views/category_model.dart';
import '../views/category_view.dart';
import '../views/goals_view.dart';
import '../views/history_view.dart';
import '../views/home_view.dart';
import '../views/lists_view.dart';
import '../views/media_detail_view.dart';
import '../views/settings_view.dart';
import '../views/show_seasons_view.dart';
import '../views/stats_view.dart';
import '../widgets/media-detail/detail_types.dart';
import '../widgets/layout/app_shell.dart';
import '../widgets/layout/background_jobs_modal.dart';
import '../widgets/layout/close_app_modal.dart';
import '../widgets/layout/header.dart';
import '../widgets/layout/sidebar.dart';

/// Вью, которые уже портированы (все вью приложения).
bool isPortedView(AppView view) => true;

/// Приложение: MaterialApp + роутер + каркас + глобальные оверлеи.
/// ProviderScope создаётся внутри (main.dart оборачивает внешним — вложенные
/// scope поддерживаются Riverpod'ом), поэтому `const TsundokuApp()` работает
/// и в тестах.
class TsundokuApp extends StatelessWidget {
  /// Тестовые overrides внутреннего ProviderScope (стаб-адаптер dio и т.п.).
  final List<dynamic>? providerOverrides;

  /// Опциональный debug-only `MaterialApp.builder` (например, Flutter Agentation).
  /// В тестах и release-сборке равен `null`.
  final TransitionBuilder? debugOverlayBuilder;

  const TsundokuApp({
    super.key,
    this.providerOverrides,
    this.debugOverlayBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tsundoku',
      debugShowCheckedModeBanner: false,
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      builder: (context, child) {
        Widget built = child ?? const SizedBox.shrink();
        if (kDebugMode && debugOverlayBuilder != null) {
          built = debugOverlayBuilder!(context, built);
        }
        return built;
      },
      home: ProviderScope(
        overrides: (providerOverrides ?? const <dynamic>[]).cast(),
        child: const _AppRouter(),
      ),
    );
  }
}

class _AppRouter extends ConsumerStatefulWidget {
  const _AppRouter();

  @override
  ConsumerState<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<_AppRouter> {
  AppView _activeView = AppViews.home;
  AppView _renderedView = AppViews.home;
  // ignore: unused_field
  Category? _activeCategory; // switchView пишет; читается в категорийной ветке роутинга
  String? _selectedMediaId; // MediaDetailView — Фаза 4
  MediaItem? _selectedMediaItem;
  AppView _previousView = AppViews.home;
  int _mediaRevision = 0;
  bool _isExitModalOpen = false; // CloseAppModal ✓
  bool _firstRunSetupRequired = false; // FirstRunStorageModal ✓
  final Map<String, SmoothScrollController> _viewScrollControllers =
      <String, SmoothScrollController>{};
  final SmoothScrollController _detailScroll = createTsundokuScrollController();
  final List<String> _cachedViewKeys = <String>[AppViews.home];
  late final AppExit _appExit;

  bool _isCreateOpen = false; // CreateModal ✓
  MediaItem? _editingItem;
  bool _isSearchOpen = false; // SearchModal ✓
  String _initialSearchType = 'all';
  String _initialSearchQuery = '';
  String _initialSearchSource = '';
  bool _initialSearchByCreator = false;
  bool _isStaleBacklogOpen = false; // StaleBacklogModal ✓
  String _settingsTabRequest = 'sources'; // SettingsView ✓
  String _detailTabRequest = 'overview';
  bool _initiallyOpenTimeBudget = false;

  List<String> get _categories => <String>[
        ...baseCategories,
        ...ref.read(navigationCategoriesProvider).map((c) => c.id),
      ];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      try {
        final params = Uri.base.queryParameters;
        if (params.containsKey('view')) {
          final v = params['view']!;
          _activeView = v;
          _renderedView = v;
          if (_isCategory(v)) _activeCategory = v;
          if (!_isTransientView(v) && !_cachedViewKeys.contains(v)) {
            _cachedViewKeys.add(v);
          }
        }
        if (params.containsKey('mediaId')) {
          _selectedMediaId = params['mediaId'];
        }
        if (params.containsKey('tab')) {
          final t = params['tab']!;
          _settingsTabRequest = t;
          _detailTabRequest = t;
        }
        if (params.containsKey('search') && (params['search'] == 'true' || params['search'] == '1')) {
          _isSearchOpen = true;
          _initialSearchQuery = params['query'] ?? 'Frieren';
        }
        if (params.containsKey('edit') && (params['edit'] == 'true' || params['edit'] == '1')) {
          _isCreateOpen = true;
          if (_selectedMediaId != null) {
            _editingItem = MediaItem.fromJson(<String, dynamic>{
              'id': _selectedMediaId!,
              'type': 'tvshow',
              'title': 'Провожающая в последний путь Фрирен',
              'status': 1,
              'createdAt': '',
            });
          }
        }
        if (params.containsKey('popover') && params['popover'] == 'time') {
          _initiallyOpenTimeBudget = true;
        }
      } catch (_) {}
    }
    // Провайдер-модификации (offline init) — после монтирования.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(offlineModeProvider.notifier).init();
    });
    // appExit: биндинги окна/тостов.
    _appExit = AppExit(ref.read(apiClientProvider));
    // Конфиг вынесенных категорий до первого рендера роутинга + восстановление
    // последнего вынесенного view (readRoute откатил его на home).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(uiSettingsProvider.notifier).loadPersisted());
      ref
          .read(navigationCategoriesProvider.notifier)
          .loadNavigationCategories()
          .then((list) {
        if (!mounted) return;
        final saved = ref.read(uiSettingsProvider).lastView;
        if (_activeView == AppViews.home && list.any((c) => c.id == saved)) {
          navigate(saved);
        }
      });
      // Запуск фоновой очереди (SSE) — api прикреплён в apiClientProvider.
      ref
          .read(jobsClientProvider.notifier)
          .attachApi(ref.read(apiClientProvider));
      ref.read(jobsClientProvider.notifier).connect();
      // jobsClient.onJobSettled → invalidate detail cache + mediaRevision (рефетч грида).
      ref.read(jobsClientProvider.notifier).onJobSettled((job) {
        if (job.mediaId != null) {
          ref.read(mediaDetailCacheProvider).invalidate(job.mediaId!);
        }
        if (mounted) setState(() => _mediaRevision += 1);
      });
      // FirstRun storage wizard (Фаза 5): флаг готовности.
      ref
          .read(apiClientProvider)
          .getStorageSettings()
          .then((settings) {
        if (!mounted) return;
        setState(() => _firstRunSetupRequired =
            settings.isFirstRunSetupRequired);
      }).catchError((Object _) {});
    });
  }

  @override
  void dispose() {
    for (final ctrl in _viewScrollControllers.values) {
      ctrl.dispose();
    }
    _detailScroll.dispose();
    super.dispose();
  }

  SmoothScrollController _controllerFor(String viewKey) {
    return _viewScrollControllers.putIfAbsent(
      viewKey,
      () => createTsundokuScrollController(),
    );
  }

  bool _isTransientView(AppView view) =>
      view == AppViews.detail || view == AppViews.seasons;

  // ------------------------------------------------------------------
  // Роутинг.
  // ------------------------------------------------------------------

  bool _isCategory(AppView view) => _categories.contains(view);

  /// Single entry point for changing views.
  void switchView(AppView view) {
    if (_isCategory(view)) {
      _activeCategory = view;
    }
    if (!_isTransientView(view) && !_cachedViewKeys.contains(view)) {
      _cachedViewKeys.add(view);
    }
    _renderedView = view;
  }

  void navigate(AppView view) {
    setState(() {
      _activeView = view;
      _selectedMediaId = null;
      _selectedMediaItem = null;
      switchView(view);
    });
    ref.read(uiSettingsProvider.notifier).setLastView(view);
  }

  /// Every caller (card click, related tile, search result) lands here.
  void openDetail(MediaItem item) {
    if (_activeView != 'detail') {
      _previousView = _activeView;
    }
    setState(() {
      _activeView = 'detail';
      _selectedMediaId = item.id;
      _selectedMediaItem = item;
      switchView('detail');
    });
    _resetDetailScroll();
  }

  void openDetailById(String id) {
    if (_activeView != 'detail') {
      _previousView = _activeView;
    }
    setState(() {
      _activeView = 'detail';
      _selectedMediaId = id;
      _selectedMediaItem = null;
      switchView('detail');
    });
    _resetDetailScroll();
  }

  void mediaChanged() {
    setState(() => _mediaRevision += 1);
  }

  /// closeDetail (App.svelte): назад к previousView (позиция скролла сохранена в IndexedStack).
  void _closeDetail() {
    navigate(_previousView);
  }

  /// deleteFromDetail (App.svelte): удалить тайтл и рефрешнуть грид.
  Future<void> _deleteFromDetail(String id) async {
    await ref.read(apiClientProvider).deleteMedia(id);
    mediaChanged();
  }

  void _resetDetailScroll() {
    if (_detailScroll.hasClients) {
      _detailScroll.jumpTo(0);
    }
  }

  // ------------------------------------------------------------------
  // Модалки Фаз 4/5 (см. решение #42).
  // ------------------------------------------------------------------

  void openCreate([MediaItem? item]) {
    setState(() {
      _editingItem = item;
      _isCreateOpen = true;
    });
  }

  void openSearch([Object? context]) {
    setState(() {
      if (context is String) {
        _initialSearchType = 'all';
        _initialSearchQuery = context;
        _initialSearchSource = '';
        _initialSearchByCreator = false;
      } else if (context is Map<String, dynamic>) {
        _initialSearchType = context['type']?.toString() ?? 'all';
        _initialSearchQuery = context['query']?.toString() ?? '';
        _initialSearchSource = context['source']?.toString() ?? '';
        _initialSearchByCreator = context['byCreator'] == true;
      } else {
        _initialSearchType = 'all';
        _initialSearchQuery = '';
        _initialSearchSource = '';
        _initialSearchByCreator = false;
      }
      _isSearchOpen = true;
    });
  }

  void openSettings([String tab = 'sources']) {
    setState(() => _settingsTabRequest = tab);
    navigate('settings');
  }

  // ------------------------------------------------------------------
  // Exit flow.
  // ------------------------------------------------------------------

  Future<void> handleExitClick() async {
    final action = ref.read(uiSettingsProvider).onCloseAction;
    if (action == OnCloseActionPref.ask) {
      setState(() => _isExitModalOpen = true);
      return;
    }
    if (action == OnCloseActionPref.exit) {
      await _appExit.exitApp(
        closeWindow: () => platformService.closeWindow(),
        showStoppedScreen: (_) {},
      );
      return;
    }
    _appExit.closeToTray(
      closeWindow: () => platformService.closeWindow(),
      showToast: ({required title, required description}) {
        showToast(
          ref,
          ToastOptions(title: title, description: description),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Хоткеи + контекст-меню.
  // ------------------------------------------------------------------

  KeyEventResult _handleKeydown(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if ((HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      openSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_isCreateOpen) {
        setState(() {
          _isCreateOpen = false;
          _editingItem = null;
        });
        return KeyEventResult.handled;
      }
      if (_activeView == 'detail') {
        navigate(_previousView);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _showAppContextMenu(Offset position) {
    final t = ref.read(tProvider);
    final api = ref.read(apiClientProvider);
    openContextMenu(ref, position.dx, position.dy, <MenuItem>[
      MenuItem(
        id: 'search',
        label: t.tr('header.searchButton'),
        icon: 'search',
        action: openSearch,
      ),
      MenuItem(
        id: 'logs',
        label: t.tr('contextMenu.consoleLogs'),
        icon: 'logs',
        action: () => unawaited(api
            .requestVoid('/api/system/open-logs', method: 'POST')
            .catchError((Object _) {})),
      ),
      MenuItem(
        id: 'open-data-dir',
        label: t.tr('contextMenu.openDataDir'),
        icon: 'folder',
        action: () => unawaited(api
            .requestVoid('/api/system/open-data-dir', method: 'POST')
            .catchError((Object _) {})),
      ),
      MenuItem(id: 'separator0', kind: 'separator'),
      MenuItem(
        id: 'random-title',
        label: t.tr('contextMenu.randomTitle'),
        icon: 'dices',
        action: () => homeRandomPickSignal.value += 1,
      ),
      MenuItem(
        id: 'background-jobs',
        label: t.tr('contextMenu.backgroundJobs'),
        icon: 'status',
        action: () =>
            ref.read(jobsClientProvider.notifier).openModal(),
      ),
      MenuItem(id: 'separator1', kind: 'separator'),
      MenuItem(
        id: 'settings',
        label: t.tr('navigation.settings'),
        icon: 'settings',
        action: () => openSettings(),
      ),
      MenuItem(
        id: 'exit',
        label: t.tr('header.exit'),
        icon: 'power',
        kind: 'danger',
        action: () => unawaited(handleExitClick()),
      ),
    ]);
  }

  // ------------------------------------------------------------------
  // Заголовки вью.
  // ------------------------------------------------------------------

  String _titleForView(AppView view) {
    final t = ref.read(tProvider);
    switch (view) {
      case AppViews.home:
        return t.tr('views.homeTitle');
      case 'stats':
        return t.tr('stats.title');
      case 'lists':
        return t.tr('views.listsTitle');
      case 'history':
        return t.tr('views.historyTitle');
      case 'calendar':
        return t.tr('views.calendarTitle');
      case 'goals':
        return t.tr('views.goalsTitle');
      case 'seasons':
        return t.tr('navigation.seasons');
      case 'detail':
        return t.tr('detail.eyebrow');
      case 'settings':
        return t.tr('navigation.settings');
      default:
        // Вынесенная категория — Label из конфигурации; базовые — из i18n.
        return ref
                .read(navigationCategoriesProvider.notifier)
                .promotedCategoryById(view)
                ?.label ??
            t.tr('navigation.$view');
    }
  }

  Widget _buildCachedSection(String viewKey, TsundokuTheme th) {
    if (viewKey == AppViews.home) {
      return CustomScrollView(
        key: const ValueKey('scroll-home'),
        controller: _controllerFor(viewKey),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: HomeView(
              key: const ValueKey('home'),
              refreshKey: _mediaRevision,
              onOpen: openDetail,
              onMediaChanged: mediaChanged,
              onOpenStaleBacklog: () =>
                  setState(() => _isStaleBacklogOpen = true),
              initiallyOpenTimeBudget: _initiallyOpenTimeBudget,
            ),
          ),
        ],
      );
    }
    if (_isCategory(viewKey)) {
      return CustomScrollView(
        key: ValueKey('scroll-cat-$viewKey'),
        controller: _controllerFor(viewKey),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: CategoryView(
              key: ValueKey(viewKey),
              category: viewKey,
              active: true,
              refreshKey: _mediaRevision,
              onOpen: openDetail,
              onMediaChanged: mediaChanged,
              onEdit: (item) => openCreate(item),
            ),
          ),
        ],
      );
    }
    if (viewKey == AppViews.settings) {
      return LayoutBuilder(
        key: const ValueKey('scroll-settings'),
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight,
          child: SettingsView(
            key: const ValueKey('settings'),
            initialTab: SettingsTab.fromWire(_settingsTabRequest),
            onImportCompleted: mediaChanged,
            onNavigateToList: (listId) => navigate(AppViews.lists),
            onTestSearch: (source, type) => openSearch(<String, dynamic>{
              'query': '',
              'source': source,
              'type': type == 'movie' || type == 'anime' || type == 'game'
                  ? type
                  : 'all',
            }),
          ),
        ),
      );
    }

    final Widget inner;
    if (viewKey == AppViews.stats) {
      inner = StatsView(
        key: const ValueKey('stats'),
        refreshKey: _mediaRevision,
        onOpenMedia: (mediaId) => openDetailById(mediaId),
        onOpenStaleBacklog: () => setState(() => _isStaleBacklogOpen = true),
      );
    } else if (viewKey == AppViews.lists) {
      inner = ListsView(
        key: const ValueKey('lists'),
        onOpen: openDetail,
        onImportCompleted: mediaChanged,
        createListModalBuilder: (context, editing, onClose, onSaved) =>
            CreateListModal(
          isOpen: true,
          list: editing,
          onClose: onClose,
          onSaved: onSaved,
        ),
        importModalBuilder:
            (context, onClose, onImportCompleted, onNavigateToList) =>
                ImportModal(
          isOpen: true,
          onClose: onClose,
          onImportCompleted: onImportCompleted,
          onNavigateToList: onNavigateToList,
        ),
      );
    } else if (viewKey == AppViews.history) {
      inner = HistoryView(
        key: const ValueKey('history'),
        refreshKey: _mediaRevision,
        onOpenMedia: (mediaId) => openDetailById(mediaId),
      );
    } else if (viewKey == AppViews.calendar) {
      inner = CalendarView(
        key: const ValueKey('calendar'),
        onOpenMedia: (mediaId) => openDetailById(mediaId),
      );
    } else if (viewKey == AppViews.goals) {
      inner = GoalsView(
        key: const ValueKey('goals'),
        refreshKey: _mediaRevision,
        onOpenMedia: (mediaId) => openDetailById(mediaId),
        onMediaChanged: mediaChanged,
      );
    } else {
      inner = _PlaceholderView(title: _titleForView(viewKey), th: th);
    }

    return SingleChildScrollView(
      key: ValueKey('scroll-$viewKey'),
      controller: _controllerFor(viewKey),
      padding: const EdgeInsets.all(24),
      child: inner,
    );
  }

  Widget? _buildTransientView(AppView rendered) {
    if (rendered == AppViews.detail && _selectedMediaId != null) {
      return SingleChildScrollView(
        key: ValueKey('scroll-detail-$_selectedMediaId'),
        controller: _detailScroll,
        padding: const EdgeInsets.all(24),
        child: MediaDetailView(
          key: ValueKey('detail-$_selectedMediaId'),
          mediaId: _selectedMediaId!,
          initialItem: _selectedMediaItem,
          refreshKey: _mediaRevision,
          onBack: _closeDetail,
          onUpdate: mediaChanged,
          onDelete: _deleteFromDetail,
          onEdit: (item) => openCreate(item),
          onOpenRelated: openDetail,
          onSearch: openSearch,
          onOpenLists: () => navigate(AppViews.lists),
          initialSubTab: _detailTabRequest == 'episodes'
              ? SubTab.episodes
              : _detailTabRequest == 'gallery'
                  ? SubTab.gallery
                  : _detailTabRequest == 'related'
                      ? SubTab.related
                      : _detailTabRequest == 'recommendations'
                          ? SubTab.recommendations
                          : SubTab.overview,
        ),
      );
    }
    if (rendered == AppViews.seasons && _selectedMediaId != null) {
      return SingleChildScrollView(
        key: ValueKey('scroll-seasons-$_selectedMediaId'),
        controller: _detailScroll,
        padding: const EdgeInsets.all(24),
        child: ShowSeasonsView(
          key: ValueKey('seasons-$_selectedMediaId'),
          mediaId: _selectedMediaId!,
          refreshKey: _mediaRevision,
          onBack: _closeDetail,
          onMediaChanged: mediaChanged,
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final rendered = _renderedView;
    final title = _titleForView(_activeView);
    final jobsModalOpen =
        ref.watch(jobsClientProvider.select((s) => s.isModalOpen));
    final dropPrompt = ref.watch(dropPromptStateProvider);

    final Widget? transientView = _buildTransientView(rendered);
    final int activeIndex = _cachedViewKeys.indexOf(rendered);
    final Widget mainContent = Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: transientView != null,
          child: IndexedStack(
            index: activeIndex >= 0 ? activeIndex : 0,
            children: [
              for (final key in _cachedViewKeys) _buildCachedSection(key, th),
            ],
          ),
        ),
        ?transientView,
      ],
    );

    return Material(
      color: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeydown,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (details) =>
                    _showAppContextMenu(details.globalPosition),
                child: AppShell(
                  noPadding: rendered == 'settings',
                  sidebar: Sidebar(
                    activeView: _activeView,
                    onNavigate: navigate,
                    onCreate: openCreate,
                  ),
                  header: Header(
                    title: title,
                    onSearch: () => openSearch(),
                    onExitClick: () => unawaited(handleExitClick()),
                  ),
                  bodyOverride: mainContent,
                ),
              ),
            ),
            // Глобальные оверлеи (1-в-1 с хвостом App.svelte):
            const ConfirmModal(),
            if (jobsModalOpen)
              BackgroundJobsModal(onMediaChanged: mediaChanged),
            if (_isExitModalOpen)
              CloseAppModal(
                onClose: () => setState(() => _isExitModalOpen = false),
                closeWindow: () => platformService.closeWindow(),
                showToast: ({required title, required description}) {
                  showToast(
                    ref,
                    ToastOptions(title: title, description: description),
                  );
                },
                appExit: _appExit,
              ),
            if (_isCreateOpen)
              CreateModal(
                isOpen: _isCreateOpen,
                editingItem: _editingItem,
                onClose: () => setState(() {
                  _isCreateOpen = false;
                  _editingItem = null;
                }),
                onCreated: (item) {
                  setState(() {
                    _isCreateOpen = false;
                    _editingItem = null;
                  });
                  mediaChanged();
                },
              ),
            if (_isSearchOpen)
              SearchModal(
                isOpen: _isSearchOpen,
                initialType: _initialSearchType,
                initialQuery: _initialSearchQuery,
                initialSource: _initialSearchSource,
                byCreator: _initialSearchByCreator,
                onClose: () => setState(() => _isSearchOpen = false),
                onMediaAdded: (media) {
                  mediaChanged();
                },
                onNavigateToMedia: (id) {
                  setState(() => _isSearchOpen = false);
                  openDetailById(id);
                },
              ),
            if (dropPrompt != null)
              const DropReasonModal(),
            if (_isStaleBacklogOpen)
              StaleBacklogModal(
                isOpen: _isStaleBacklogOpen,
                onClose: () => setState(() => _isStaleBacklogOpen = false),
                onMediaChanged: mediaChanged,
              ),
            if (_firstRunSetupRequired)
              FirstRunStorageModal(
                isOpen: _firstRunSetupRequired,
                onSaved: () => setState(() => _firstRunSetupRequired = false),
              ),
          ],
        ),
      ),
    );
  }
}

/// Заглушка вью Фаз 4/5 (решение #42): заголовок + иконка «в разработке».
class _PlaceholderView extends ConsumerWidget {
  final String title;
  final TsundokuTheme th;

  const _PlaceholderView({required this.title, required this.th});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.625,
              color: th.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            LucideIcons.construction,
            size: 32,
            color: th.textMuted,
          ),
        ],
      ),
    );
  }
}
