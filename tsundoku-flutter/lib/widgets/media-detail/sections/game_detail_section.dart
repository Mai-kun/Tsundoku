/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/GameDetailSection.svelte`.
///
/// Игровая секция: ProgressCard (часы, teal, total неизвестен) + достижения
/// (поиск, toggle all, unlock-карточки, пагинация 60/стр).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/tsundoku_image.dart';
import '../../../shared/ui/tsundoku_scroll.dart';
import 'progress_card.dart';

/// Игровая секция (1-в-1 с GameDetailSection.svelte).
class GameDetailSection extends ConsumerStatefulWidget {
  final int progressValue;
  final String progressLabel;
  final Object? progressError;
  final void Function(int value) onCounterChange;
  final List<GameAchievementItem> achievements;
  final int achievementsTotal;
  final bool achievementsLoading;
  final bool achievementsBusy;
  final bool achievementsTruncated;

  /// `.has(name)` / `.size` — источник Map в родителе.
  final Set<String> unlockedNames;
  final Future<void> Function(String name) onToggleAchievement;
  final Future<void> Function() onToggleAllAchievements;

  const GameDetailSection({
    super.key,
    required this.progressValue,
    required this.progressLabel,
    required this.progressError,
    required this.onCounterChange,
    required this.achievements,
    required this.achievementsTotal,
    required this.achievementsLoading,
    required this.achievementsBusy,
    required this.achievementsTruncated,
    required this.unlockedNames,
    required this.onToggleAchievement,
    required this.onToggleAllAchievements,
  });

  @override
  ConsumerState<GameDetailSection> createState() => _GameDetailSectionState();
}

class _GameDetailSectionState extends ConsumerState<GameDetailSection> {
  static const int _pageSize = 60;

  late final TextEditingController _searchController;
  String _searchQuery = '';
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isUnlocked(GameAchievementItem ach) =>
      widget.unlockedNames.contains(ach.name.toLowerCase().trim());

  bool get _allUnlocked =>
      widget.achievements.isNotEmpty &&
      widget.achievements.every(_isUnlocked);

  List<GameAchievementItem> get _filteredAchievements {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return widget.achievements;
    return widget.achievements
        .where((ach) =>
            ach.name.toLowerCase().contains(q) ||
            (ach.description?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  int get _totalPages =>
      math.max(1, (_filteredAchievements.length / _pageSize).ceil());

  List<GameAchievementItem> get _pagedAchievements =>
      _filteredAchievements
          .skip((_currentPage - 1) * _pageSize)
          .take(_pageSize)
          .toList();

  List<Object> get _paginationPages {
    if (_totalPages <= 7) {
      return [for (var i = 1; i <= _totalPages; i++) i];
    }
    if (_currentPage <= 4) {
      return [1, 2, 3, 4, 5, '...', _totalPages];
    }
    if (_currentPage >= _totalPages - 3) {
      return [
        1,
        '...',
        _totalPages - 4,
        _totalPages - 3,
        _totalPages - 2,
        _totalPages - 1,
        _totalPages,
      ];
    }
    return [1, '...', _currentPage - 1, _currentPage, _currentPage + 1, '...', _totalPages];
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final isRu = locale.wire == 'ru';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Games track hours without a known total: teal, no ring, no time math.
        ProgressCard(
          label: widget.progressLabel,
          unitShort: t.tr('progress.unitShortH'),
          accent: ProgressAccent.teal,
          value: widget.progressValue,
          total: 0,
          percent: 0,
          minsPerUnit: null,
          doneLabel: t.tr('progress.playedVerb'),
          remainLabel: t.tr('progress.remainPlayVerb'),
          paceOptions: const [],
          startHint: t.tr('progress.startHours'),
          error: widget.progressError,
          onStep: (delta) =>
              widget.onCounterChange(widget.progressValue + delta),
          onCounterChange: widget.onCounterChange,
        ),
        const SizedBox(height: 16), // gap-4
        _achievementsSection(t, th, isRu),
      ],
    );
  }

  Widget _achievementsSection(I18nDictionary t, TsundokuTheme th, bool isRu) {
    final filtered = _filteredAchievements;
    final paged = _pagedAchievements;

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: th.bgSurface, // panel-line
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.trophy,
                  size: 16, color: Color(0xFFFBBF24)), // text-amber-400
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Text(
                  (isRu ? 'Достижения' : 'Achievements').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.6, // tracking-wider
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
              ),
              if (widget.achievements.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxWidth: 256), // w-56 sm:w-64
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _searchQuery = value;
                      _currentPage = 1; // $effect-аналог: сброс страницы
                    }),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white), // text-xs text-white
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isRu
                          ? 'Поиск достижений по названию и описанию...'
                          : 'Search achievements by name and description...',
                      hintStyle:
                          TextStyle(color: Colors.white.withAlpha(115)), // zinc-500
                      filled: true,
                      fillColor: const Color(0xFF161A24), // bg-[#161a24]
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6), // px-3 py-1.5
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _currentPage = 1;
                                });
                              },
                              child: const Icon(LucideIcons.x,
                                  size: 14, color: Color(0xFFA1A1AA)),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6), // rounded-md
                        borderSide:
                            BorderSide(color: Colors.white.withAlpha(26)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            BorderSide(color: Colors.white.withAlpha(26)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: th.accentBright),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8), // gap-2
              _ToggleAllButton(
                isRu: isRu,
                allUnlocked: _allUnlocked,
                disabled:
                    widget.achievementsBusy || widget.achievements.isEmpty,
                onTap: () => widget.onToggleAllAchievements(),
              ),
              const SizedBox(width: 8),
              _AchievementsCountPill(
                isRu: isRu,
                loading: widget.achievementsLoading,
                unlockedCount: widget.unlockedNames.length,
                achievementsTotal: widget.achievementsTotal,
                truncated: widget.achievementsTruncated,
                loadedCount: widget.achievements.length,
              ),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          if (widget.achievementsLoading)
            // Скелетон 4 карточек (animate-pulse).
            Wrap(
              spacing: 12, // gap-3
              runSpacing: 12,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 140,
                    height: 56, // h-14
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: th.bgSurface, // color-field → bg-surface
                    ),
                  ),
              ],
            )
          else if (widget.achievements.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16), // py-4
                    child: Center(
                      child: Text(
                        isRu ? 'Достижения не найдены' : 'No achievements found',
                        style:
                            TextStyle(fontSize: 12, color: th.textMuted), // text-xs
                      ),
                    ),
                  )
                else ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxHeight: 520), // max-h-[520px]
                    child: TsundokuSmoothScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-3
                          final w = constraints.maxWidth;
                          final int cols = w >= 900 ? 3 : (w >= 540 ? 2 : 1);
                          final cardWidth = (w - (cols - 1) * 10) / cols;
                          return Wrap(
                            spacing: 10, // gap-2.5
                            runSpacing: 10,
                            children: [
                              for (final ach in paged)
                                SizedBox(
                                  width: cardWidth,
                                  child: _AchievementCard(
                                    ach: ach,
                                    isUnlocked: _isUnlocked(ach),
                                    isRu: isRu,
                                    th: th,
                                    onToggle: () =>
                                        widget.onToggleAchievement(ach.name),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (_totalPages > 1)
                    _Pagination(
                      isRu: isRu,
                      currentPage: _currentPage,
                      totalPages: _totalPages,
                      pages: _paginationPages,
                      pagedCount: paged.length,
                      filteredCount: filtered.length,
                      th: th,
                      onGoToPage: _goToPage,
                    ),
                ],
              ],
            )
          else
            // Достижения — внешние данные; грузятся только при добавлении/
            // обновлении метаданных. Никакой кнопки fetch здесь сознательно нет.
            Text(
              isRu
                  ? 'Достижения не загружены. Обновите метаданные, чтобы получить их.'
                  : 'Achievements not loaded. Refresh metadata to fetch them.',
              style: TextStyle(fontSize: 12, color: th.textMuted), // text-xs
            ),
        ],
      ),
    );
  }
}

/// Кнопка «Отметить все»/«Снять все»: amber-чип.
class _ToggleAllButton extends StatefulWidget {
  final bool isRu;
  final bool allUnlocked;
  final bool disabled;
  final VoidCallback onTap;

  const _ToggleAllButton({
    required this.isRu,
    required this.allUnlocked,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_ToggleAllButton> createState() => _ToggleAllButtonState();
}

class _ToggleAllButtonState extends State<_ToggleAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.allUnlocked
          ? (widget.isRu ? 'Снять отметки со всех достижений' : 'Clear all achievements')
          : (widget.isRu ? 'Отметить все достижения' : 'Mark all achievements'),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.disabled ? null : widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // px-2.5 py-1
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(
                  color: const Color(0x4DFBBF24)), // border-amber-400/30
              color: _hovered && !widget.disabled
                  ? const Color(0x33FBBF24) // hover:bg-amber-400/20
                  : const Color(0x1AFBBF24), // bg-amber-400/10
            ),
            child: Text(
              widget.allUnlocked
                  ? (widget.isRu ? 'Снять все' : 'Clear all')
                  : (widget.isRu ? 'Отметить все' : 'Mark all'),
              style: TextStyle(
                fontSize: 11, // text-[11px]
                fontWeight: FontWeight.w600, // font-semibold
                color: widget.disabled
                    ? const Color(0xFFFCD34D).withAlpha(102) // disabled:opacity-40
                    : const Color(0xFFFCD34D), // text-amber-300
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Пилюля счётчика: loading-спиннер / Unlocked: n / total / total only.
class _AchievementsCountPill extends StatelessWidget {
  final bool isRu;
  final bool loading;
  final int unlockedCount;
  final int achievementsTotal;
  final bool truncated;
  final int loadedCount;

  const _AchievementsCountPill({
    required this.isRu,
    required this.loading,
    required this.unlockedCount,
    required this.achievementsTotal,
    required this.truncated,
    required this.loadedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 2), // px-2 py-0.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999), // rounded-full
        border: Border.all(
            color: const Color(0x33FBBF24)), // border-amber-400/20
        color: const Color(0x1AFBBF24), // bg-amber-400/10
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFCD34D)),
            )
          else if (unlockedCount > 0)
            Text(
              '${isRu ? 'Получено' : 'Unlocked'}: $unlockedCount / $achievementsTotal',
              style: const TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w600, // font-semibold
                color: Color(0xFFFCD34D), // text-amber-300
              ),
            )
          else
            Text(
              '${isRu ? 'Всего достижений' : 'Total achievements'}: $achievementsTotal',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFCD34D),
              ),
            ),
          if (truncated)
            const Text(
              ' *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFCD34D),
              ),
            ),
        ],
      ),
    );
  }
}

/// Карточка достижения: unlock-цвета/грейскейл, чек-бейдж.
class _AchievementCard extends StatelessWidget {
  final GameAchievementItem ach;
  final bool isUnlocked;
  final bool isRu;
  final TsundokuTheme th;
  final VoidCallback onToggle;

  const _AchievementCard({
    required this.ach,
    required this.isUnlocked,
    required this.isRu,
    required this.th,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isUnlocked
          ? (isRu ? 'Получено (нажмите, чтобы снять)' : 'Unlocked (click to lock)')
          : (isRu ? 'Не получено (нажмите, чтобы отметить)' : 'Locked (click to unlock)'),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(10), // p-2.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(
              color: isUnlocked
                  ? const Color(0x6610B981) // border-emerald-500/40
                  : Colors.white.withAlpha(15), // /[0.06]
            ),
            color: isUnlocked
                ? const Color(0xFF13231B) // success-deep (lit., вне ThemeExtension)
                : th.bgSurface, // color-field → bg-surface
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40, // h-10 w-10
                height: 40,
                child: Stack(
                  children: [
                    if (ach.iconUrl != null && ach.iconUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6), // rounded-md
                        child: Container(
                          color: Colors.black.withAlpha(102), // bg-black/40
                          child: Opacity(
                            opacity: isUnlocked ? 1.0 : 0.6, // grayscale/contrast ⏭️
                            child: TsundokuImage(
                              imageUrl: ach.iconUrl,
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              errorWidget: const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: isUnlocked
                              ? const Color(0x9905542F) // bg-emerald-950/60
                              : th.bgSurface, // panel-line
                        ),
                        child: Icon(
                          LucideIcons.trophy,
                          size: 16,
                          color: isUnlocked
                              ? const Color(0xFF34D399) // text-emerald-400
                              : const Color(0xFFFBBF24), // text-amber-400
                        ),
                      ),
                    if (isUnlocked)
                      Positioned(
                        right: -4, // -right-1
                        bottom: -4,
                        child: Container(
                          width: 16, // h-4 w-4
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xE610B981), // bg-emerald-500/90
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF13231B), // ring-success-deep (lit.)
                                blurRadius: 0,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(LucideIcons.check,
                              size: 10, color: Colors.black),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12), // gap-3
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ach.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        color: isUnlocked
                            ? const Color(0xFF6EE7B7) // text-emerald-300
                            : Colors.white,
                      ),
                    ),
                    if (ach.description != null &&
                        ach.description!.isNotEmpty)
                      Text(
                        ach.description!,
                        maxLines: 1, // line-clamp-1
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          color: th.textMuted, // text-muted
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пагинация: «Страница N из M (показано …)», Назад/страницы/Вперед.
class _Pagination extends StatelessWidget {
  final bool isRu;
  final int currentPage;
  final int totalPages;
  final List<Object> pages;
  final int pagedCount;
  final int filteredCount;
  final TsundokuTheme th;
  final void Function(int page) onGoToPage;

  const _Pagination({
    required this.isRu,
    required this.currentPage,
    required this.totalPages,
    required this.pages,
    required this.pagedCount,
    required this.filteredCount,
    required this.th,
    required this.onGoToPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12), // pt-3
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x0FFFFFFF))), // /[0.06]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRu
                ? 'Страница $currentPage из $totalPages (показано $pagedCount из $filteredCount достижений)'
                : 'Page $currentPage of $totalPages (showing $pagedCount of $filteredCount achievements)',
            style: TextStyle(
              fontSize: 12, // text-xs
              color: th.textMuted, // text-muted
            ),
          ),
          const SizedBox(height: 6), // gap-3 vertical
          Wrap(
            spacing: 6, // gap-1.5
            runSpacing: 6,
            children: [
              _PageNavButton(
                label: isRu ? 'Назад' : 'Prev',
                icon: LucideIcons.chevronLeft,
                iconFirst: true,
                disabled: currentPage == 1,
                th: th,
                onTap: () => onGoToPage(currentPage - 1),
              ),
              for (final p in pages)
                if (p == '...')
                  Container(
                    width: 36, // w-9
                    height: 36,
                    alignment: Alignment.center,
                    child: const Text(
                      '...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8), // text-muted
                      ),
                    ),
                  )
                else
                  _PageNumberButton(
                    page: p as int,
                    active: currentPage == p,
                    th: th,
                    onTap: () => onGoToPage(p),
                  ),
              _PageNavButton(
                label: isRu ? 'Вперед' : 'Next',
                icon: LucideIcons.chevronRight,
                iconFirst: false,
                disabled: currentPage == totalPages,
                th: th,
                onTap: () => onGoToPage(currentPage + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageNavButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool iconFirst;
  final bool disabled;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.label,
    required this.icon,
    required this.iconFirst,
    required this.disabled,
    required this.th,
    required this.onTap,
  });

  @override
  State<_PageNavButton> createState() => _PageNavButtonState();
}

class _PageNavButtonState extends State<_PageNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Container(
          height: 36, // h-9
          constraints: const BoxConstraints(minWidth: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(color: Colors.white.withAlpha(26)), // /10
            color: _hovered && !widget.disabled
                ? Colors.white.withAlpha(26) // hover:bg-white/10
                : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.iconFirst)
                Icon(widget.icon,
                    size: 14,
                    color: widget.disabled
                        ? Colors.white.withAlpha(102)
                        : const Color(0xFFCBD5E1)),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: widget.disabled
                      ? Colors.white.withAlpha(102) // disabled:opacity-40
                      : _hovered
                          ? Colors.white // hover:text-white
                          : const Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
              if (!widget.iconFirst)
                Icon(widget.icon,
                    size: 14,
                    color: widget.disabled
                        ? Colors.white.withAlpha(102)
                        : const Color(0xFFCBD5E1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageNumberButton extends StatefulWidget {
  final int page;
  final bool active;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _PageNumberButton({
    required this.page,
    required this.active,
    required this.th,
    required this.onTap,
  });

  @override
  State<_PageNumberButton> createState() => _PageNumberButtonState();
}

class _PageNumberButtonState extends State<_PageNumberButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36, // w-9
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            color: widget.active
                ? widget.th.accentBright // bg-accent-bright
                : _hovered
                    ? Colors.white.withAlpha(26) // hover:bg-white/10
                    : Colors.transparent,
            border: widget.active
                ? null
                : Border.all(color: Colors.white.withAlpha(26)), // /10
          ),
          child: Text(
            '${widget.page}',
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: widget.active ? FontWeight.w500 : FontWeight.w400,
              color: widget.active
                  ? Colors.white
                  : _hovered
                      ? Colors.white // hover:text-white
                      : const Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
        ),
      ),
    );
  }
}
