/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "search").
///
/// Вкладка «Поиск»:
/// - Порядок категорий в общем поиске (drag-and-drop / кнопки вверх-вниз + сохранение).
/// - Вынесенные категории навигации: быстрые пресеты (Комиксы, Ранобэ), форма кастомной категории,
///   список активных подкатегорий с удалением.
/// - Приоритет источников поиска по категориям: упорядочивание провайдеров (Основной / Резервный N).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/api/navigation_categories.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/dtos.dart';
import '../../../shared/ui/badge.dart';
import '../../../shared/ui/popover_menu.dart';
import '../../../shared/ui/toast.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  // Category Order State
  List<String> _categoryOrder = ['anime', 'manga', 'movie', 'tvshow', 'game', 'book'];
  bool _orderLoading = false;
  bool _orderSaving = false;
  bool _orderSuccess = false;

  // Promoted Categories State
  bool _showPromotedForm = false;
  String _promotedSaving = '';
  final TextEditingController _promotedLabelController = TextEditingController();
  final TextEditingController _promotedValueController = TextEditingController();
  String _newPromotedIcon = 'bookmark';
  String _newPromotedParent = 'Book';
  String _newPromotedKind = 'format'; // 'format' | 'genre' | 'tag'

  // Source Priority State
  Map<String, List<String>> _sourcePriority = {};
  bool _priorityLoading = false;
  bool _prioritySaving = false;

  // Sources cache for labels and disabled badges
  List<SourceInfo> _sources = [];

  static const List<String> _defaultCategories = [
    'anime',
    'manga',
    'movie',
    'tvshow',
    'game',
    'book',
  ];

  static const Map<String, List<String>> _defaultPriority = {
    'anime': ['shikimori', 'anilist', 'mal'],
    'manga': ['mangalib', 'anilist', 'mal'],
    'movie': ['tmdb', 'kinopoisk'],
    'tvshow': ['tmdb', 'kinopoisk'],
    'game': ['rawg'],
    'book': ['googlebooks', 'openlibrary'],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _promotedLabelController.dispose();
    _promotedValueController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadOrder(),
      _loadPromotedCategories(),
      _loadPriority(),
      _loadSources(),
    ]);
  }

  void _toast({required String title, required String description, ToastType type = ToastType.info}) {
    ref.read(toastStoreProvider.notifier).show(
          ToastOptions(title: title, description: description, type: type),
        );
  }

  // ── Category Order ──────────────────────────────────────────────────────────

  Future<void> _loadOrder() async {
    setState(() => _orderLoading = true);
    try {
      final res = await ref.read(apiClientProvider).getCategoryOrder();
      if (mounted) {
        setState(() {
          _categoryOrder = res.isNotEmpty ? res : [..._defaultCategories];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _categoryOrder = [..._defaultCategories]);
      }
    } finally {
      if (mounted) {
        setState(() => _orderLoading = false);
      }
    }
  }

  Future<void> _moveCategory(int index, String direction, I18nDictionary t) async {
    if (_orderSaving) return;
    final nextList = [..._categoryOrder];
    final targetIndex = direction == 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= nextList.length) return;

    final temp = nextList[index];
    nextList[index] = nextList[targetIndex];
    nextList[targetIndex] = temp;

    setState(() {
      _categoryOrder = nextList;
      _orderSaving = true;
      _orderSuccess = false;
    });

    try {
      await ref.read(apiClientProvider).saveCategoryOrder(_categoryOrder);
      if (mounted) {
        setState(() => _orderSuccess = true);
      }
      _toast(
        title: t.tr('settingsModal.search.saved'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _orderSaving = false);
      }
    }
  }

  // ── Promoted Categories ─────────────────────────────────────────────────────

  Future<void> _loadPromotedCategories() async {
    try {
      await ref.read(navigationCategoriesProvider.notifier).loadNavigationCategories();
    } catch (_) {
      // Handled silently
    }
  }

  bool _isPresetAdded(String presetId, List<PromotedSubcategory> categories) {
    return categories.any((c) => c.id == presetId);
  }

  Future<void> _handleAddPromotedPreset(PromotedSubcategory preset, I18nDictionary t) async {
    setState(() => _promotedSaving = preset.id);
    final current = ref.read(navigationCategoriesProvider);
    final next = [...current, preset];
    try {
      await ref.read(navigationCategoriesProvider.notifier).saveNavigationCategories(next);
      _toast(
        title: t.tr('settingsModal.search.saved'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _promotedSaving = '');
      }
    }
  }

  Future<void> _handleAddCustomPromoted(I18nDictionary t) async {
    final label = _promotedLabelController.text.trim();
    final value = _promotedValueController.text.trim();
    if (label.isEmpty || value.isEmpty) return;

    final id = 'cat-${DateTime.now().millisecondsSinceEpoch}';
    final newSub = PromotedSubcategory(
      id: id,
      label: label,
      icon: _newPromotedIcon,
      parentType: _newPromotedParent,
      matchKind: _newPromotedKind,
      matchValue: value,
    );

    setState(() => _promotedSaving = id);
    final current = ref.read(navigationCategoriesProvider);
    final next = [...current, newSub];

    try {
      await ref.read(navigationCategoriesProvider.notifier).saveNavigationCategories(next);
      if (mounted) {
        setState(() {
          _showPromotedForm = false;
          _promotedLabelController.clear();
          _promotedValueController.clear();
        });
      }
      _toast(
        title: t.tr('settingsModal.search.saved'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _promotedSaving = '');
      }
    }
  }

  Future<void> _handleRemovePromoted(String id, I18nDictionary t) async {
    setState(() => _promotedSaving = id);
    final current = ref.read(navigationCategoriesProvider);
    final next = current.where((c) => c.id != id).toList();

    try {
      await ref.read(navigationCategoriesProvider.notifier).saveNavigationCategories(next);
      _toast(
        title: t.tr('toast.descDeleted'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _promotedSaving = '');
      }
    }
  }

  // ── Source Priority ─────────────────────────────────────────────────────────

  Future<void> _loadPriority() async {
    setState(() => _priorityLoading = true);
    try {
      final res = await ref.read(apiClientProvider).getSourcePriority();
      if (mounted) {
        setState(() {
          _sourcePriority = res.isNotEmpty ? res : Map.of(_defaultPriority);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sourcePriority = Map.of(_defaultPriority));
      }
    } finally {
      if (mounted) {
        setState(() => _priorityLoading = false);
      }
    }
  }

  Future<void> _loadSources() async {
    try {
      final res = await ref.read(apiClientProvider).getSources();
      if (mounted) {
        setState(() => _sources = res);
      }
    } catch (_) {}
  }

  Future<void> _moveSourcePriority(String mediaType, int index, String direction, I18nDictionary t) async {
    if (_prioritySaving) return;
    final currentList = [...(_sourcePriority[mediaType] ?? const <String>[])];
    final targetIndex = direction == 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= currentList.length) return;

    final temp = currentList[index];
    currentList[index] = currentList[targetIndex];
    currentList[targetIndex] = temp;

    final nextMap = Map<String, List<String>>.from(_sourcePriority);
    nextMap[mediaType] = currentList;

    setState(() {
      _sourcePriority = nextMap;
      _prioritySaving = true;
    });

    try {
      await ref.read(apiClientProvider).saveSourcePriority(nextMap);
      _toast(
        title: t.tr('settingsModal.search.saved'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _prioritySaving = false);
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _categoryLabel(String key, I18nDictionary t) {
    return switch (key.toLowerCase()) {
      'anime' => t.tr('navigation.anime'),
      'manga' => t.tr('types.manga'),
      'movie' => t.tr('types.movie'),
      'tvshow' => t.tr('types.tvshow'),
      'game' => t.tr('types.game'),
      'book' => t.tr('types.book'),
      _ => key,
    };
  }

  String _getSourceName(String provId) {
    final match = _sources.where((s) => s.id == provId).firstOrNull;
    if (match != null) return match.name;
    return switch (provId) {
      'shikimori' => 'Shikimori',
      'anilist' => 'AniList',
      'mal' => 'MyAnimeList',
      'mangalib' => 'MangaLib',
      'tmdb' => 'TMDB',
      'kinopoisk' => 'Кинопоиск',
      'rawg' => 'RAWG',
      'googlebooks' => 'Google Books',
      'openlibrary' => 'Open Library',
      'sociallib' => 'SocialLib',
      'simkl' => 'Simkl',
      _ => provId,
    };
  }

  bool _isSourceDisabled(String provId) {
    final match = _sources.where((s) => s.id == provId).firstOrNull;
    return match != null && !match.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final promoted = ref.watch(navigationCategoriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Category Order in All Search ───────────────────────────────
          _buildCategoryOrderSection(t, theme),
          const SizedBox(height: 28),

          // ── 2. Promoted Navigation Categories ─────────────────────────────
          _buildPromotedCategoriesSection(t, theme, promoted),
          const SizedBox(height: 28),

          // ── 3. Source Search Priority by Category ─────────────────────────
          _buildSourcePrioritySection(t, theme),
        ],
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────────────────────

  Widget _buildCategoryOrderSection(I18nDictionary t, TsundokuTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.tr('settingsModal.search.orderTitle'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          t.tr('settingsModal.search.orderHint'),
          style: TextStyle(fontSize: 12, color: theme.textMuted),
        ),
        const SizedBox(height: 12),
        if (_orderLoading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categoryOrder.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final cat = _categoryOrder[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x05FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: Row(
                  children: [
                    // Position number
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFFFFF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Category title
                    SizedBox(
                      width: 140,
                      child: Text(
                        _categoryLabel(cat, t),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Icon(LucideIcons.gripVertical, size: 16, color: theme.textMuted.withAlpha(100)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Up/Down action buttons
                    IconButton(
                      icon: const Icon(LucideIcons.chevronUp, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: index == 0 || _orderSaving ? theme.textMuted.withAlpha(60) : theme.textMuted,
                      onPressed: index == 0 || _orderSaving ? null : () => _moveCategory(index, 'up', t),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.chevronDown, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: index == _categoryOrder.length - 1 || _orderSaving
                          ? theme.textMuted.withAlpha(60)
                          : theme.textMuted,
                      onPressed:
                          index == _categoryOrder.length - 1 || _orderSaving ? null : () => _moveCategory(index, 'down', t),
                    ),
                  ],
                ),
              );
            },
          ),
        if (_orderSuccess)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.tr('settingsModal.search.saved'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF34D399)),
            ),
          ),
      ],
    );
  }

  Widget _buildPromotedCategoriesSection(
    I18nDictionary t,
    TsundokuTheme theme,
    List<PromotedSubcategory> promoted,
  ) {
    return Container(
      padding: const EdgeInsets.only(top: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.tr('settingsModal.search.navCategories.title'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            t.tr('settingsModal.search.navCategories.hint'),
            style: TextStyle(fontSize: 12, color: theme.textMuted),
          ),
          const SizedBox(height: 12),

          // Quick Preset Buttons + Add Custom button
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...promotedPresets.map((preset) {
                final added = _isPresetAdded(preset.id, promoted);
                if (added) return const SizedBox.shrink();
                return OutlinedButton.icon(
                  onPressed: _promotedSaving.isNotEmpty ? null : () => _handleAddPromotedPreset(preset, t),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0x1A0284C7),
                    side: const BorderSide(color: Color(0x4D0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 13, color: Color(0xFF38BDF8)),
                  label: Text(
                    preset.label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showPromotedForm = !_showPromotedForm),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0x05FFFFFF),
                  side: const BorderSide(color: Color(0x1AFFFFFF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: Icon(_showPromotedForm ? LucideIcons.x : LucideIcons.plus, size: 13, color: theme.textMuted),
                label: Text(
                  t.tr('settingsModal.search.navCategories.customOpen'),
                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                ),
              ),
            ],
          ),

          // Custom Subcategory Form
          if (_showPromotedForm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promotedLabelController,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          decoration: InputDecoration(
                            labelText: t.tr('settingsModal.search.navCategories.titleLabel'),
                            hintText: t.tr('settingsModal.search.navCategories.titleLabelPlaceholder'),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0x0FFFFFFF),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('settingsModal.search.navCategories.iconLabel'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            TsundokuSelect<String>(
                              id: 'promoted-icon',
                              width: double.infinity,
                              height: 36,
                              value: _newPromotedIcon,
                              options: promotedIcons.keys.map((k) => PopoverOption(value: k, label: k)).toList(),
                              onChange: (val) => setState(() => _newPromotedIcon = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('settingsModal.search.navCategories.parentLabel'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            TsundokuSelect<String>(
                              id: 'promoted-parent',
                              width: double.infinity,
                              height: 36,
                              value: _newPromotedParent,
                              options: [
                                PopoverOption(value: 'Book', label: t.tr('types.book')),
                                PopoverOption(value: 'Manga', label: t.tr('types.manga')),
                                PopoverOption(value: 'Game', label: t.tr('types.game')),
                                PopoverOption(value: 'TvShow', label: t.tr('types.tvshow')),
                                PopoverOption(value: 'Movie', label: t.tr('types.movie')),
                              ],
                              onChange: (val) => setState(() => _newPromotedParent = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('settingsModal.search.navCategories.kindLabel'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            TsundokuSelect<String>(
                              id: 'promoted-kind',
                              width: double.infinity,
                              height: 36,
                              value: _newPromotedKind,
                              options: [
                                PopoverOption(value: 'format', label: t.tr('settingsModal.search.navCategories.kindFormat')),
                                PopoverOption(value: 'genre', label: t.tr('settingsModal.search.navCategories.kindGenre')),
                                PopoverOption(value: 'tag', label: t.tr('settingsModal.search.navCategories.kindTag')),
                              ],
                              onChange: (val) => setState(() => _newPromotedKind = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _promotedValueController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: t.tr('settingsModal.search.navCategories.valueLabel'),
                      hintText: t.tr('settingsModal.search.navCategories.valuePlaceholder'),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0x0FFFFFFF),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _promotedSaving.isNotEmpty ? null : () => _handleAddCustomPromoted(t),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(LucideIcons.plus, size: 13),
                        label: Text(
                          t.tr('settingsModal.search.navCategories.addBtn'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _showPromotedForm = false),
                        child: Text(t.tr('common.cancel'), style: TextStyle(fontSize: 12, color: theme.textMuted)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Active Promoted Categories List
          const SizedBox(height: 12),
          if (promoted.isEmpty)
            Text(
              t.tr('settingsModal.search.navCategories.emptyText'),
              style: TextStyle(fontSize: 12, color: theme.textMuted),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: promoted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final sub = promoted[index];
                final iconData = promotedIcon(sub.icon);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x05FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0x260284C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0x4D0284C7)),
                        ),
                        alignment: Alignment.center,
                        child: Icon(iconData, size: 14, color: const Color(0xFF38BDF8)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              sub.label,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x0DFFFFFF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _categoryLabel(promotedParentType(sub), t),
                                style: TextStyle(fontSize: 10, color: theme.textMuted),
                              ),
                            ),
                            TsundokuBadge(
                              tone: BadgeTone.info,
                              size: BadgeSize.xs,
                              child: Text('${sub.matchKind}: ${sub.matchValue}'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash2, size: 15),
                        color: const Color(0xFFFB7185),
                        onPressed: _promotedSaving.isNotEmpty ? null : () => _handleRemovePromoted(sub.id, t),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSourcePrioritySection(I18nDictionary t, TsundokuTheme theme) {
    return Container(
      padding: const EdgeInsets.only(top: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.tr('settingsModal.search.sourcePriorityTitle'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            t.tr('settingsModal.search.sourcePriorityHint'),
            style: TextStyle(fontSize: 12, color: theme.textMuted),
          ),
          const SizedBox(height: 12),
          if (_priorityLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sourcePriority.entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final entry = _sourcePriority.entries.elementAt(index);
                final mediaType = entry.key;
                final providers = entry.value;
                if (providers.length <= 1) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x05FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _categoryLabel(mediaType, t).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Color(0xFFA5B4FC),
                            ),
                          ),
                          Text(
                            t.tf('settingsModal.sources.providersCount', [providers.length]),
                            style: TextStyle(fontSize: 11, color: theme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: providers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, pIdx) {
                          final provId = providers[pIdx];
                          final isPrimary = pIdx == 0;
                          final disabled = _isSourceDisabled(provId);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: disabled ? const Color(0x05FFFFFF) : const Color(0x0FFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0x14FFFFFF)),
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.gripVertical, size: 14, color: theme.textMuted.withAlpha(100)),
                                const SizedBox(width: 8),
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: const Color(0x1AFFFFFF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${pIdx + 1}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: theme.sourceTheme(provId).accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getSourceName(provId),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: disabled ? theme.textMuted : Colors.white,
                                  ),
                                ),
                                if (disabled) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0x2671717A), // zinc-500/15
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      t.tr('settingsModal.sources.disabledBadge'),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFA1A1AA), // zinc-400
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                if (isPrimary)
                                  TsundokuBadge(
                                    tone: BadgeTone.success,
                                    size: BadgeSize.xs,
                                    child: Text(t.tr('settingsModal.search.primary')),
                                  )
                                else
                                  TsundokuBadge(
                                    tone: BadgeTone.neutral,
                                    size: BadgeSize.xs,
                                    child: Text(t.tf('settingsModal.search.fallback', [pIdx + 1])),
                                  ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(LucideIcons.chevronUp, size: 14),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  color: pIdx == 0 || _prioritySaving ? theme.textMuted.withAlpha(60) : theme.textMuted,
                                  onPressed: pIdx == 0 || _prioritySaving
                                      ? null
                                      : () => _moveSourcePriority(mediaType, pIdx, 'up', t),
                                ),
                                IconButton(
                                  icon: const Icon(LucideIcons.chevronDown, size: 14),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  color: pIdx == providers.length - 1 || _prioritySaving
                                      ? theme.textMuted.withAlpha(60)
                                      : theme.textMuted,
                                  onPressed: pIdx == providers.length - 1 || _prioritySaving
                                      ? null
                                      : () => _moveSourcePriority(mediaType, pIdx, 'down', t),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
