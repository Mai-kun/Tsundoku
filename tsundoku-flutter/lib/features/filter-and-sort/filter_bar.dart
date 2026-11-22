/// 1:1 port of `mediatracker-ui/src/features/filter-and-sort/FilterBar.svelte`.
///
/// Тулбар фильтров библиотеки: группировка (status/franchise/all — иконки),
/// статус-селектор с бейджем-счётчиком, центрированный TotalBadge, поиск с
/// дебаунсом 300ms, селектор сортировки (newest/oldest/rating/title — иконки).
/// Иконки опций — PopoverOption.leading (renderOption-аналог).
///
/// `LibrarySort` — typedef String из category_model.dart (1-в-1 с TS-union,
/// решение #2); `GroupBy` — такой же строковый union отсюда.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/media_labels.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart';
import '../../shared/ui/badge.dart';
import '../../shared/ui/button.dart';
import '../../shared/ui/popover_menu.dart';
import '../../shared/ui/total_badge.dart';
import '../../views/category_model.dart' show LibrarySort;

/// TS-union `GroupBy = "status" | "franchise" | "all"` — открытый строковый
/// union (конвенция решения #2).
typedef GroupBy = String;

const String groupByStatus = 'status';
const String groupByFranchise = 'franchise';
const String groupByAll = 'all';

/// SORT_ICONS/GROUP_ICONS (script module) — 1-в-1.
IconData sortIcon(String sort) {
  switch (sort) {
    case 'newest':
      return LucideIcons.arrowDown;
    case 'oldest':
      return LucideIcons.arrowUp;
    case 'rating':
      return LucideIcons.star;
    case 'title':
      return LucideIcons.type;
    default:
      return LucideIcons.arrowDown;
  }
}

IconData groupIcon(String group) {
  switch (group) {
    case groupByStatus:
      return LucideIcons.listChecks;
    case groupByFranchise:
      return LucideIcons.tag;
    case groupByAll:
      return LucideIcons.layoutGrid;
    default:
      return LucideIcons.listChecks;
  }
}

class FilterBar extends ConsumerStatefulWidget {
  final StatusFilter status;
  final LibrarySort sort;
  final GroupBy groupBy;
  final String search;
  final Map<StatusFilter, int> counts;

  /// Полный total из БД; когда показан — центрирует TotalBadge вместо
  /// плавающего счётчика.
  final int? totalCount;

  /// Сколько из total показывают текущие фильтры.
  final int? shownCount;

  final void Function(StatusFilter status) onStatusChange;
  final void Function(LibrarySort sort) onSortChange;
  final void Function(GroupBy groupBy)? onGroupByChange;
  final void Function(String query) onSearchChange;

  const FilterBar({
    super.key,
    required this.status,
    required this.sort,
    this.groupBy = groupByStatus,
    required this.search,
    this.counts = const {},
    this.totalCount,
    this.shownCount,
    required this.onStatusChange,
    required this.onSortChange,
    this.onGroupByChange,
    required this.onSearchChange,
  });

  @override
  ConsumerState<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<FilterBar> {
  /// Список статусов 1-в-1 с Svelte (all + 5 медиа-статусов).
  static const List<StatusFilter> _statuses = <StatusFilter>[
    StatusFilter.all(),
    StatusFilter.status(0), // planned
    StatusFilter.status(1), // inProgress
    StatusFilter.status(2), // completed
    StatusFilter.status(3), // onHold
    StatusFilter.status(4), // dropped
  ];

  Timer? _searchDebounce;

  @override
  void dispose() {
    // $effect(() => () => clearTimeout).
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _labelForStatus(StatusFilter value, I18nDictionary t) {
    if (value.isAll) return t.tr('status.all');
    return statusLabel(MediaStatus.tryValue(value.status!)!, t);
  }

  void _debouncedSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearchChange(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final groupOptions = <PopoverOption<String>>[
      PopoverOption(
          value: groupByStatus,
          label: t.tr('grouping.byStatus'),
          leading: groupIcon(groupByStatus)),
      PopoverOption(
          value: groupByFranchise,
          label: t.tr('grouping.byFranchise'),
          leading: groupIcon(groupByFranchise)),
      PopoverOption(
          value: groupByAll,
          label: t.tr('grouping.all'),
          leading: groupIcon(groupByAll)),
    ];

    final statusOptions = <PopoverOption<StatusFilter>>[
      for (final s in _statuses) PopoverOption(value: s, label: _labelForStatus(s, t)),
    ];

    final sortOptions = <PopoverOption<LibrarySort>>[
      PopoverOption(value: 'newest', label: t.tr('sort.newest'), leading: sortIcon('newest')),
      PopoverOption(value: 'oldest', label: t.tr('sort.oldest'), leading: sortIcon('oldest')),
      PopoverOption(value: 'rating', label: t.tr('sort.rating'), leading: sortIcon('rating')),
      PopoverOption(value: 'title', label: t.tr('sort.title'), leading: sortIcon('title')),
    ];

    final count = widget.counts[widget.status];

    return Container(
      padding: const EdgeInsets.all(16), // p-3 sm:p-4
      decoration: BoxDecoration(
        color: th.bgSurface, // bg-surface
        borderRadius: BorderRadius.circular(8), // rounded-lg
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.slidersHorizontal, // SlidersHorizontal size={16}
                size: 16,
                color: th.textMuted, // text-muted
              ),
              const SizedBox(width: 8), // gap-2
              // Группировка: icon-only, openOnHover, closeDelay 220.
              TsundokuPopoverMenu<String>(
                id: 'library-group',
                options: groupOptions,
                selected: widget.groupBy,
                onSelect: (value) => widget.onGroupByChange?.call(value),
                label: t.tr('grouping.label'),
                placement: PopoverPlacement.bottomStart,
                openOnHover: true,
                closeDelay: 220,
                trigger: (context, ctx) => _IconButtonTrigger(
                  tooltip: t.tr('grouping.label'),
                  icon: groupIcon(widget.groupBy),
                  th: th,
                  showTooltip: !ctx.isOpen,
                ),
              ),
              const SizedBox(width: 8), // gap-2
              // Статус: лейбл + счётчик-бейдж + ChevronDown.
              TsundokuPopoverMenu<StatusFilter>(
                id: 'library-status',
                options: statusOptions,
                selected: widget.status,
                onSelect: (value) => widget.onStatusChange(value),
                label: t.tr('status.label'),
                placement: PopoverPlacement.bottomStart,
                openOnHover: true,
                closeDelay: 220,
                trigger: (context, ctx) => _StatusTrigger(
                  label: _labelForStatus(widget.status, t),
                  count: count,
                  th: th,
                  showTooltip: !ctx.isOpen,
                ),
              ),
              const Spacer(),
              // Центрированный счётчик (order-last lg:order-none).
              if (widget.totalCount != null)
                TsundokuTotalBadge(
                  total: widget.totalCount!,
                  shown: widget.shownCount,
                ),
              const Spacer(),
              // Поиск + сортировка справа.
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _SearchField(
                        initial: widget.search,
                        hint: t.tr('header.searchButton'),
                        th: th,
                        onChanged: _debouncedSearch,
                      ),
                    ),
                    const SizedBox(width: 8), // gap-2
                    TsundokuPopoverMenu<LibrarySort>(
                      id: 'library-sort',
                      options: sortOptions,
                      selected: widget.sort,
                      onSelect: (value) => widget.onSortChange(value),
                      label: t.tr('sort.label'),
                      placement: PopoverPlacement.bottomEnd,
                      openOnHover: true,
                      closeDelay: 220,
                      trigger: (context, ctx) => _IconButtonTrigger(
                        tooltip: t.tr('sort.label'),
                        icon: sortIcon(widget.sort),
                        th: th,
                        showTooltip: !ctx.isOpen,
                      ),
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
}

/// icon-only lg-кнопка (secondary, 40px).
class _IconButtonTrigger extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final TsundokuTheme th;
  final bool showTooltip;

  const _IconButtonTrigger({
    required this.tooltip,
    required this.icon,
    required this.th,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    // Кнопка — визуал: тап должен уходить в GestureDetector поповера —
    // IgnorePointer исключает кнопку из арены жестов (🐛 #6).
    final body = IgnorePointer(
      child: SizedBox(
        width: 36, // h-9 w-9
        height: 36,
        child: TsundokuButton(
          variant: ButtonVariant.secondary,
          size: ButtonSize.md,
          onPressed: () {},
          child: Icon(icon, size: 18, color: th.textMuted),
        ),
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

/// Статус-триггер: label truncate + Badge-счётчик + ChevronDown.
class _StatusTrigger extends StatelessWidget {
  final String label;
  final int? count;
  final TsundokuTheme th;
  final bool showTooltip;

  const _StatusTrigger({
    required this.label,
    required this.count,
    required this.th,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = IgnorePointer(
      child: SizedBox(
        height: 36,
        child: TsundokuButton(
          variant: ButtonVariant.secondary,
          size: ButtonSize.md,
          onPressed: () {},
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                TsundokuBadge(
                  tone: BadgeTone.neutral,
                  size: BadgeSize.xs,
                  child: Text('$count'),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown, // ChevronDown size={14}
                size: 14,
                color: th.textMuted, // text-muted
              ),
            ],
          ),
        ),
      ),
    );
    if (showTooltip && label.isNotEmpty) {
      return Tooltip(
        message: label,
        child: body,
      );
    }
    return body;
  }
}

/// Поле поиска: bg-field border-white/10 rounded-lg h-9 pl-9, Search 16px
/// внутри рамки слева, debounce 300ms снаружи.
class _SearchField extends StatefulWidget {
  final String initial;
  final String hint;
  final TsundokuTheme th;
  final void Function(String value) onChanged;

  const _SearchField({
    required this.initial,
    required this.hint,
    required this.th,
    required this.onChanged,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(_SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial &&
        widget.initial != _controller.text) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: 13, // text-sm
          color: th.textPrimary, // text-ink
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Icon(
              LucideIcons.search,
              size: 16,
              color: th.textMuted,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 36),
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: th.textMuted,
          ),
          filled: true,
          fillColor: th.bgSurface, // bg-field
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            borderSide:
                BorderSide(color: Colors.white.withAlpha(26)), // white/10
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0x996366F1), // focus:border-indigo-500/60
            ),
          ),
        ),
      ),
    );
  }
}
