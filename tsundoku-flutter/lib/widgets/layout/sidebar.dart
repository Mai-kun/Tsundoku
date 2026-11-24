/// 1:1 port of `mediatracker-ui/src/widgets/layout/Sidebar.svelte`.
///
/// Навигация: десктоп (lg ≥1024) — колонка (бренд, главная навигация с
/// вынесенными категориями сразу после родительского пункта, инструменты
/// внизу); мобайл — рельса иконок + Menu-кнопка с всплывающими инструментами.
/// Подсветка активного пункта: bg-accent-bright/15 + text-[#a5b4fc]; slide-
/// анимация crossfade 220ms cubic-bezier(0.2,0,0,1) → AnimatedContainer.
/// Конфиг вынесенных категорий лениво грузится при монтировании.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/navigation_categories.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart';
import '../../shared/ui/segmented_control.dart';

/// `lg:`-граница Tailwind (Svelte-классы перестраивают разметку по ней).
const double _lgBreakpoint = 1024;

/// Кривая slide-индикатора (CSS cubic-bezier(0.2, 0, 0, 1)).
const Cubic _indicatorCurve = Cubic(0.2, 0, 0, 1);

class Sidebar extends ConsumerStatefulWidget {
  final AppView activeView;
  final void Function(AppView view) onNavigate;
  final VoidCallback onCreate;

  const Sidebar({
    super.key,
    required this.activeView,
    required this.onNavigate,
    required this.onCreate,
  });

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _toolsOpen = false;
  final OverlayPortalController _toolsPortal = OverlayPortalController();
  final GlobalKey _railKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Конфигурация вынесенных категорий лениво тянется при монтировании
    // сайдбара ($effect → loadNavigationCategories).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(navigationCategoriesProvider.notifier)
            .loadNavigationCategories();
      }
    });
  }

  void _navigate(AppView view) {
    setState(() => _toolsOpen = false);
    if (_toolsPortal.isShowing) _toolsPortal.hide();
    widget.onNavigate(view);
  }

  /// Вынесенные категории сразу после родительского пункта.
  Map<String, List<PromotedSubcategory>> _promotedAfterBase() {
    final byParent = <String, List<PromotedSubcategory>>{};
    for (final sub in ref.watch(navigationCategoriesProvider)) {
      final parent = promotedParentType(sub);
      byParent.putIfAbsent(parent, () => <PromotedSubcategory>[]).add(sub);
    }
    return byParent;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= _lgBreakpoint;
    final promotedByParent = _promotedAfterBase();

    // ---------- Главная навигация (icons-only на мобайле, с лейблами на lg) ----------
    List<Widget> mainNavChildren(bool desktop) {
      final children = <Widget>[];
      void nav(AppView view, String label, IconData icon) {
        children.add(_NavItem(
          view: view,
          label: label,
          icon: icon,
          iconSize: 18,
          desktop: desktop,
          active: widget.activeView == view,
          th: th,
          onNavigate: _navigate,
        ));
      }

      void promoted(String parent) {
        for (final sub
            in promotedByParent[parent] ?? const <PromotedSubcategory>[]) {
          children.add(_NavItem(
            view: sub.id,
            label: sub.label,
            icon: promotedIcon(sub.icon),
            iconSize: 18,
            desktop: desktop,
            active: widget.activeView == sub.id,
            th: th,
            onNavigate: _navigate,
          ));
        }
      }

      nav(AppViews.home, t.tr('navigation.home'), LucideIcons.home);
      nav(MediaType.tvshow.wire, t.tr('navigation.tvshow'), LucideIcons.tv);
      promoted('tvshow'); // promotedParentType — lowercase
      nav('movie', t.tr('navigation.movie'), LucideIcons.film);
      promoted('movie');
      nav('anime', t.tr('navigation.anime'), LucideIcons.clapperboard);
      nav('manga', t.tr('navigation.manga'), LucideIcons.library);
      promoted('manga');
      nav('game', t.tr('navigation.game'), LucideIcons.gamepad2);
      promoted('game');
      nav('book', t.tr('navigation.book'), LucideIcons.bookOpen);
      promoted('book');
      return children;
    }

    // ---------- Инструменты ----------
    Widget toolsItem(AppView view, String label, IconData icon,
        {double py = 8}) {
      return _NavItem(
        view: view,
        label: label,
        icon: icon,
        iconSize: 17,
        desktop: true,
        active: widget.activeView == view,
        th: th,
        onNavigate: _navigate,
        py: py,
      );
    }

    final Widget toolsColumn = Column(
      children: [
        // Добавить медиа — действие, не view (onCreate).
        _NavItem(
          view: '',
          label: t.tr('navigation.create'),
          icon: LucideIcons.plus,
          iconSize: 17,
          desktop: true,
          active: false,
          th: th,
          onNavigate: (_) => widget.onCreate(),
        ),
        toolsItem(AppViews.stats, t.tr('navigation.stats'), LucideIcons.barChart3),
        toolsItem(AppViews.lists, t.tr('navigation.lists'), LucideIcons.list),
        toolsItem(AppViews.history, t.tr('navigation.history'), LucideIcons.history),
        toolsItem(AppViews.calendar, t.tr('navigation.calendar'), LucideIcons.calendarDays),
        toolsItem(AppViews.goals, t.tr('navigation.goals'), LucideIcons.trophy),
        toolsItem(AppViews.settings, t.tr('navigation.settings'), LucideIcons.settings),
      ],
    );

    final Widget toolsLabel = TsundokuSectionHeader(
      t.tr('navigation.toolsLabel'),
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8), // px-3 pb-2
    );

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: 12, right: 12, bottom: 28), // px-3 pb-7
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tsundoku',
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: -0.025 * 14, // tracking-tight
                    color: th.textPrimary, // text-ink
                  ),
                ),
                const SizedBox(height: 4), // mt-1
                Text(
                  t.tr('navigation.brand').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.18 * 10, // tracking-[0.18em]
                    color: th.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: mainNavChildren(true),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x1AFFFFFF)), // border-border
              ),
            ),
            padding: const EdgeInsets.only(top: 16), // pt-4
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                toolsLabel,
                toolsColumn,
              ],
            ),
          ),
        ],
      );
    }

    // ---------- Мобильная рельса + всплывающие инструменты ----------
    // Поповер рендерится в Overlay (1-в-1 с absolute bottom-full: тапы за
    // пределами родительских границ в Flutter возможны только в оверлее).
    return OverlayPortal(
      controller: _toolsPortal,
      overlayChildBuilder: (overlayContext) {
        if (!_toolsOpen) return const SizedBox.shrink();
        final railBox =
            _railKey.currentContext?.findRenderObject() as RenderBox?;
        final railTop = railBox?.localToGlobal(Offset.zero).dy ?? 0;
        final screenH = MediaQuery.sizeOf(overlayContext).height;
        return Positioned(
          left: 8, // inset-x-2
          right: 8,
          bottom: screenH - railTop + 8, // bottom-full mb-2
          child: Container(
              padding: const EdgeInsets.all(8), // p-2
              decoration: BoxDecoration(
                color: th.bgElevated, // bg-elevated
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(color: Colors.white.withAlpha(20)), // white/[0.08]
                boxShadow: const [
                  // shadow-2xl shadow-black/60
                  BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 25),
                    blurRadius: 50,
                    spreadRadius: -12,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TsundokuSectionHeader(
                    t.tr('navigation.toolsLabel'),
                    padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 4),
                  ),
                  // py-2.5 = 10px у мобильных tools-пунктов.
                  _NavItem(
                    view: '',
                    label: t.tr('navigation.create'),
                    icon: LucideIcons.plus,
                    iconSize: 18,
                    desktop: true,
                    active: false,
                    th: th,
                    onNavigate: (_) {
                      setState(() => _toolsOpen = false);
                      if (_toolsPortal.isShowing) _toolsPortal.hide();
                      widget.onCreate();
                    },
                    py: 10,
                  ),
                  toolsItem(AppViews.stats, t.tr('navigation.stats'),
                      LucideIcons.barChart3,
                      py: 10),
                  toolsItem(AppViews.lists, t.tr('navigation.lists'),
                      LucideIcons.list,
                      py: 10),
                  toolsItem(AppViews.history, t.tr('navigation.history'),
                      LucideIcons.history,
                      py: 10),
                  toolsItem(AppViews.calendar, t.tr('navigation.calendar'),
                      LucideIcons.calendarDays,
                      py: 10),
                  toolsItem(AppViews.goals, t.tr('navigation.goals'),
                      LucideIcons.trophy,
                      py: 10),
                  toolsItem(AppViews.settings, t.tr('navigation.settings'),
                      LucideIcons.settings,
                      py: 10),
                ],
              ),
            ),
          );
        },
      child: Row(
          key: _railKey,
          mainAxisAlignment: MainAxisAlignment.spaceAround, // justify-around
          children: mainNavChildren(false) + [_mobileToolsButton(th)],
        ),
    );
  }

  Widget _mobileToolsButton(TsundokuTheme th) {
    return GestureDetector(
      onTap: () {
        setState(() => _toolsOpen = !_toolsOpen);
        if (_toolsOpen) {
          _toolsPortal.show();
        } else if (_toolsPortal.isShowing) {
          _toolsPortal.hide();
        }
      },
      child: Tooltip(
        message: ref.watch(tProvider).tr('navigation.toolsLabel'),
        child: Container(
          width: 40, // h-10 w-10
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
          child: Icon(
            LucideIcons.menu, // Menu size={18}
            size: 18,
            color: th.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Пункт навигации: h-10, rounded-md; активный — bg-accent-bright/15 +
/// text-[#a5b4fc] (text и иконка), неактивный — text-muted,
/// hover:bg-card/60 + hover:text-ink.
class _NavItem extends StatefulWidget {
  final AppView view;
  final String label;
  final IconData icon;
  final double iconSize;
  final bool desktop;
  final bool active;
  final TsundokuTheme th;
  final void Function(AppView view) onNavigate;
  final double py;

  const _NavItem({
    required this.view,
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.desktop,
    required this.active,
    required this.th,
    required this.onNavigate,
    this.py = 8, // py-2
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    final active = widget.active;
    final hovered = _hovered && !active;

    // itemClass: активный — #a5b4fc (text + icon), неактивный — text-muted,
    // hover — text-ink + bg-card/60.
    final color = active
        ? const Color(0xFFA5B4FC) // text-[#a5b4fc]
        : hovered
            ? th.textPrimary // hover:text-ink
            : th.textMuted; // text-muted
    final bg = active
        ? th.accentBright.withAlpha(38) // bg-accent-bright/15
        : hovered
            ? th.bgCard.withAlpha(153) // hover:bg-card/60
            : Colors.transparent;

    return Padding(
      padding: widget.desktop
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onNavigate(widget.view),
          child: Tooltip(
            message: widget.label, // title + aria-label
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: _indicatorCurve,
              height: 40, // h-10
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6), // rounded-md
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 12, // lg:px-3
                vertical: widget.py,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: widget.iconSize, color: color),
                  if (widget.desktop) ...[
                    const SizedBox(width: 12), // lg:gap-3
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis, // truncate
                        style: TextStyle(
                          fontSize: 14, // text-sm
                          fontWeight: FontWeight.w500, // font-medium
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
