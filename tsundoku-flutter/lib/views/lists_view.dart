import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../entities/media/model/cover_url.dart';
import '../entities/media/model/media_labels.dart';
import '../features/lists/create_list_modal.dart';
import '../shared/api/api.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/dtos.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';
import '../shared/ui/button.dart';
import '../shared/ui/confirm_dialog.dart';
import '../shared/ui/media_cover_placeholder.dart';
import '../shared/ui/toast.dart';
import '../shared/ui/tsundoku_image.dart';
import '../widgets/media-grid/media_grid.dart';

class _SmartQueryData {
  final List<String> categories;
  final List<int> statuses;
  final int? maxEpisodes;
  final int? maxDurationMinutes;
  final int? maxPages;
  final num? minScore;

  const _SmartQueryData({
    required this.categories,
    required this.statuses,
    this.maxEpisodes,
    this.maxDurationMinutes,
    this.maxPages,
    this.minScore,
  });

  static _SmartQueryData? tryParse(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      return _SmartQueryData(
        categories: (decoded['categories'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        statuses: (decoded['statuses'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        maxEpisodes: (decoded['maxEpisodes'] as num?)?.toInt(),
        maxDurationMinutes: (decoded['maxDurationMinutes'] as num?)?.toInt(),
        maxPages: (decoded['maxPages'] as num?)?.toInt(),
        minScore: decoded['minScore'] as num?,
      );
    } catch (_) {
      return null;
    }
  }
}

class ListsView extends ConsumerStatefulWidget {
  final ValueChanged<MediaItem>? onOpen;
  final VoidCallback? onImportCompleted;
  final void Function(CustomListSummary? list)? onOpenCreateList;
  final VoidCallback? onOpenImport;
  final Widget Function(
    BuildContext context,
    CustomListSummary? editing,
    VoidCallback onClose,
    VoidCallback onSaved,
  )? createListModalBuilder;
  final Widget Function(
    BuildContext context,
    VoidCallback onClose,
    VoidCallback onImportCompleted,
    ValueChanged<String>? onNavigateToList,
  )? importModalBuilder;

  const ListsView({
    super.key,
    this.onOpen,
    this.onImportCompleted,
    this.onOpenCreateList,
    this.onOpenImport,
    this.createListModalBuilder,
    this.importModalBuilder,
  });

  @override
  ConsumerState<ListsView> createState() => ListsViewState();
}

class ListsViewState extends ConsumerState<ListsView> {
  List<CustomListSummary> _lists = const [];
  CustomListDetail? _selected;
  bool _loading = true;
  String _error = '';
  bool _modalOpen = false;
  bool _importOpen = false;
  CustomListSummary? _editing;
  final Set<String> _brokenCovers = {};

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  void _markBroken(String url) {
    _brokenCovers.add(url);
  }

  IconData _listIcon(String? icon) {
    switch (icon) {
      case 'bookmark':
        return LucideIcons.bookmark;
      case 'heart':
        return LucideIcons.heart;
      case 'star':
        return LucideIcons.star;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'flame':
        return LucideIcons.flame;
      case 'list':
      default:
        return LucideIcons.list;
    }
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  static const _ruMonths = [
    'янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.',
    'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'
  ];
  static const _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatUpdatedDate(String value, Locale locale) {
    try {
      final dt = DateTime.parse(value);
      if (locale == Locale.ru) {
        return '${dt.day} ${_ruMonths[dt.month - 1]} ${dt.year} г.';
      } else {
        return '${_enMonths[dt.month - 1]} ${dt.day}, ${dt.year}';
      }
    } catch (_) {
      return value;
    }
  }

  Future<void> _loadLists() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final locale = ref.read(i18nProvider);

    try {
      final lists = await ref.read(apiClientProvider).getLists();
      if (!mounted) return;

      CustomListDetail? selected = _selected;
      if (selected != null) {
        try {
          selected = await ref
              .read(apiClientProvider)
              .getListDetail(selected.id);
        } catch (_) {
          selected = null;
        }
      }

      setState(() {
        _lists = lists;
        _selected = selected;
        _loading = false;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(caught, locale);
        _loading = false;
      });
    }
  }

  Future<void> refreshLists() => _loadLists();

  Future<void> openList(CustomListSummary list) async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final locale = ref.read(i18nProvider);

    try {
      final detail =
          await ref.read(apiClientProvider).getListDetail(list.id);
      if (!mounted) return;
      setState(() {
        _selected = detail;
        _loading = false;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(caught, locale);
        _loading = false;
      });
    }
  }

  void closeList() {
    setState(() => _selected = null);
  }

  void openCreate([CustomListSummary? list]) {
    if (widget.onOpenCreateList != null) {
      widget.onOpenCreateList!(list);
      return;
    }
    setState(() {
      _editing = list;
      _modalOpen = true;
    });
  }

  void openImport() {
    if (widget.onOpenImport != null) {
      widget.onOpenImport!();
      return;
    }
    setState(() => _importOpen = true);
  }

  Future<void> removeList(CustomListSummary list) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);

    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-list',
        title: t.tf('views.listConfirmDelete', [list.name]),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    );

    if (!confirmed) return;

    try {
      await ref.read(apiClientProvider).deleteList(list.id);
      if (!mounted) return;

      if (_selected?.id == list.id) {
        setState(() => _selected = null);
      }

      showToast(
        ref,
        ToastOptions(
          title: t.tr('views.listDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );

      await _loadLists();
    } catch (caught) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(caught, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  Future<void> removeItem(MediaItem item) async {
    final active = _selected;
    if (active == null) return;

    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);

    // Optimistic remove
    setState(() {
      _selected = CustomListDetail(
        id: active.id,
        name: active.name,
        description: active.description,
        icon: active.icon,
        color: active.color,
        createdAt: active.createdAt,
        items: active.items.where((v) => v.id != item.id).toList(),
        isSmart: active.isSmart,
        smartQueryJson: active.smartQueryJson,
      );
    });

    try {
      await ref
          .read(apiClientProvider)
          .removeMediaFromList(active.id, item.id);
      if (!mounted) return;

      showToast(
        ref,
        ToastOptions(
          title: t.tf('views.listRemoved', [active.name]),
          description: t.tr('toast.descDeleted'),
        ),
      );

      await _loadLists();
    } catch (caught) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(caught, locale),
          type: ToastType.error,
        ),
      );

      // Revert from server
      try {
        final reloaded =
            await ref.read(apiClientProvider).getListDetail(active.id);
        if (mounted) setState(() => _selected = reloaded);
      } catch (_) {}
    }
  }

  Future<void> showImportedList(String id) async {
    await _loadLists();
    if (!mounted) return;
    try {
      final detail = await ref.read(apiClientProvider).getListDetail(id);
      if (mounted) setState(() => _selected = detail);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final tokens = TsundokuTheme.of(context);

    Widget content;
    if (_selected != null) {
      content = _buildSelectedView(_selected!, t, locale, tokens);
    } else {
      content = _buildListsView(t, locale, tokens);
    }

    return Stack(
      children: [
        content,
        if (_modalOpen)
          widget.createListModalBuilder != null
              ? widget.createListModalBuilder!(
                  context,
                  _editing,
                  () => setState(() => _modalOpen = false),
                  () {
                    setState(() => _modalOpen = false);
                    _loadLists();
                  },
                )
              : CreateListModal(
                  isOpen: true,
                  list: _editing,
                  onClose: () => setState(() => _modalOpen = false),
                  onSaved: () {
                    setState(() => _modalOpen = false);
                    _loadLists();
                  },
                ),
        if (_importOpen && widget.importModalBuilder != null)
          widget.importModalBuilder!(
            context,
            () => setState(() => _importOpen = false),
            () {
              widget.onImportCompleted?.call();
              _loadLists();
            },
            (id) => showImportedList(id),
          ),
      ],
    );
  }

  // ── Selected List View ───────────────────────────────────────────────────
  Widget _buildSelectedView(
    CustomListDetail selected,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    final listColor = _parseColor(selected.color) ?? tokens.accent;
    final selectedIcon = _listIcon(selected.icon);
    final summary = _lists.where((l) => l.id == selected.id).firstOrNull;
    final smartQuery = _SmartQueryData.tryParse(selected.smartQueryJson);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top row: Back button & Info
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: 16,
          runSpacing: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TsundokuButton(
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.sm,
                  onPressed: closeList,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('← '),
                      Text(t.tr('views.listBack')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: listColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        selectedIcon,
                        size: 23,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.tf('views.listTitles', [selected.items.length]),
                          style: TextStyle(
                            fontSize: 14,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (selected.description != null &&
                    selected.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      selected.description!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Edit & Delete actions
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TsundokuButton(
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.lg,
                    onPressed: () => openCreate(summary),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.pencil, size: 15),
                        const SizedBox(width: 8),
                        Text(t.tr('views.listEdit')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TsundokuButton(
                    variant: ButtonVariant.danger,
                    size: ButtonSize.lg,
                    onPressed: summary != null ? () => removeList(summary) : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.trash2, size: 15),
                        const SizedBox(width: 8),
                        Text(t.tr('views.listDelete')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Smart List rules banner
        if (selected.isSmart && smartQuery != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFA78BFA).withAlpha(13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFA78BFA).withAlpha(51),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      '⚡ ${t.tr('views.smartBadge')}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC4B5FD),
                      ),
                    ),
                    if (smartQuery.categories.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          smartQuery.categories.join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                    if (smartQuery.statuses.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          smartQuery.statuses
                              .map((s) => statusLabel(
                                  MediaStatus.tryValue(s) ??
                                      MediaStatus.planned,
                                  t))
                              .join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                    if (smartQuery.maxEpisodes != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '≤${smartQuery.maxEpisodes} эп.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                    if (smartQuery.maxDurationMinutes != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '≤${smartQuery.maxDurationMinutes} мин',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                    if (smartQuery.maxPages != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '≤${smartQuery.maxPages} стр.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                    if (smartQuery.minScore != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withAlpha(38),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '★${smartQuery.minScore}+',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFDDD6FE),
                          ),
                        ),
                      ),
                  ],
                ),
                InkWell(
                  onTap: () => openCreate(summary),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA78BFA).withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFA78BFA).withAlpha(76),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.pencil,
                            size: 12, color: Color(0xFFE9D5FF)),
                        const SizedBox(width: 6),
                        Text(
                          t.tr('views.smartEditRules'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE9D5FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Media Grid
        MediaGridView(
          grid: MediaGrid(
            items: selected.items,
            showProgress: false,
            loading: _loading,
            error: _error.isNotEmpty ? _error : null,
            onRetry: summary != null ? () => openList(summary) : null,
            onOpen: widget.onOpen,
            onRemoveFromList: selected.isSmart ? null : removeItem,
          ),
        ),
      ],
    );
  }

  // ── Lists Gallery View ───────────────────────────────────────────────────
  Widget _buildListsView(
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Bar
        Wrap(
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
                    letterSpacing: 2.0,
                    color: tokens.accentSoft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.tr('views.listsTitle'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TsundokuButton(
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.lg,
                  onPressed: openImport,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.layers, size: 16),
                      const SizedBox(width: 8),
                      Text(t.tr('importModal.start')),
                    ],
                  ),
                ),
                if (_lists.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TsundokuButton(
                    variant: ButtonVariant.primary,
                    size: ButtonSize.lg,
                    onPressed: () => openCreate(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.plus, size: 16),
                        const SizedBox(width: 8),
                        Text(t.tr('views.listsCreate')),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Main content
        if (_loading)
          _buildLoadingGrid(tokens)
        else if (_error.isNotEmpty)
          _buildErrorBox(t, tokens)
        else if (_lists.isEmpty)
          _buildEmptyBox(t, tokens)
        else
          _buildListsGrid(t, locale, tokens),
      ],
    );
  }

  Widget _buildLoadingGrid(TsundokuTheme tokens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1280
            ? 4
            : constraints.maxWidth >= 1024
                ? 3
                : constraints.maxWidth >= 640
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            return Container(
              height: 224,
              decoration: BoxDecoration(
                color: tokens.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorBox(I18nDictionary t, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFB7185).withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB7185).withAlpha(51)),
      ),
      child: Center(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              _error,
              style: const TextStyle(fontSize: 14, color: Color(0xFFFECDD3)),
            ),
            TextButton(
              onPressed: _loadLists,
              child: Text(
                t.tr('common.retry'),
                style: const TextStyle(
                  decoration: TextDecoration.underline,
                  color: Color(0xFFFECDD3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBox(I18nDictionary t, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
      decoration: BoxDecoration(
        color: tokens.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tokens.bgElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 27,
                color: tokens.accentSoft,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              t.tr('views.listsEmptyTitle'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                t.tr('views.listsEmptyHint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: tokens.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicWidth(
              child: TsundokuButton(
                variant: ButtonVariant.primary,
                size: ButtonSize.lg,
                onPressed: () => openCreate(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.plus, size: 16),
                    const SizedBox(width: 8),
                    Text(t.tr('views.listCreateFirst')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListsGrid(
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1280
            ? 4
            : constraints.maxWidth >= 1024
                ? 3
                : constraints.maxWidth >= 640
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _lists.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            final list = _lists[index];
            return _buildListCard(list, t, locale, tokens);
          },
        );
      },
    );
  }

  Widget _buildListCard(
    CustomListSummary list,
    I18nDictionary t,
    Locale locale,
    TsundokuTheme tokens,
  ) {
    final listColor = _parseColor(list.color) ?? tokens.accent;
    final icon = _listIcon(list.icon);
    final smartQuery = _SmartQueryData.tryParse(list.smartQueryJson);
    bool isHovered = false;

    return StatefulBuilder(
      builder: (context, setCardState) {
        return MouseRegion(
          onEnter: (_) => setCardState(() => isHovered = true),
          onExit: (_) => setCardState(() => isHovered = false),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHovered ? Colors.white.withAlpha(38) : Colors.white.withAlpha(18),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Clickable top area (Covers + details)
                Expanded(
                  child: InkWell(
                    onTap: () => openList(list),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cover area (height 176)
                        SizedBox(
                          height: 176,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildCardCovers(list, listColor, icon, tokens),
                              // Gradient shadow at bottom of cover
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 64,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Color(0xB3000000)],
                                    ),
                                  ),
                                ),
                              ),
                              // Smart badge
                              if (list.isSmart)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xCC1E1B4B),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFFA78BFA).withAlpha(76),
                                      ),
                                    ),
                                    child: Text(
                                      '⚡ ${t.tr('views.smartBadge')}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFDDD6FE),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Info area (Name, description, chips)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                list.description != null &&
                                        list.description!.isNotEmpty
                                    ? list.description!
                                    : '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: tokens.textMuted,
                                ),
                              ),
                              if (list.isSmart && smartQuery != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (smartQuery.categories.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              const Color(0xFFA78BFA).withAlpha(26),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          smartQuery.categories.join(', '),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFFC4B5FD),
                                          ),
                                        ),
                                      ),
                                    if (smartQuery.minScore != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              const Color(0xFFFBBF24).withAlpha(26),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '★${smartQuery.minScore}+',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFFFCD34D),
                                          ),
                                        ),
                                      ),
                                    if (smartQuery.maxEpisodes != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(26),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '≤${smartQuery.maxEpisodes} эп.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: tokens.textMuted,
                                          ),
                                        ),
                                      ),
                                    if (smartQuery.maxDurationMinutes != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(26),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '≤${smartQuery.maxDurationMinutes}м',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: tokens.textMuted,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom card footer with metadata and actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${t.tf('views.listTitles', [list.itemsCount])} · ${t.tr('views.listUpdated')} ${_formatUpdatedDate(list.updatedAt, locale)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: isHovered ? 1.0 : 0.0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.pencil, size: 15),
                              tooltip: t.tr('views.listEdit'),
                              onPressed: () => openCreate(list),
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 28, minHeight: 28),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2, size: 15),
                              tooltip: t.tr('views.listDelete'),
                              onPressed: () => removeList(list),
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 28, minHeight: 28),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardCovers(
    CustomListSummary list,
    Color listColor,
    IconData icon,
    TsundokuTheme tokens,
  ) {
    final covers = list.previewCovers.whereType<String>().toList();

    if (covers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              listColor.withAlpha(69),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: listColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(26)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(76),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 27, color: Colors.white),
          ),
        ),
      );
    }

    if (covers.length == 1) {
      final cover = covers[0];
      return Stack(
        fit: StackFit.expand,
        children: [
          if (!_brokenCovers.contains(cover)) ...[
            Opacity(
              opacity: 0.25,
              child: TsundokuImage(
                src: fullSizeCoverUrl(cover),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  _markBroken(cover);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 144,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: !_brokenCovers.contains(cover)
                      ? TsundokuImage(
                          src: fullSizeCoverUrl(cover),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const MediaCoverPlaceholder(),
                          placeholder: const MediaCoverPlaceholder(),
                        )
                      : const MediaCoverPlaceholder(),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 2 or more covers: overlapping row
    return Center(
      child: SizedBox(
        height: 144,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(covers.length, (i) {
            final cover = covers[i];
            return Transform.translate(
              offset: Offset(i * -20.0, 0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(128),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: !_brokenCovers.contains(cover)
                        ? TsundokuImage(
                            src: fullSizeCoverUrl(cover),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const MediaCoverPlaceholder(),
                            placeholder: const MediaCoverPlaceholder(),
                          )
                        : const MediaCoverPlaceholder(),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
