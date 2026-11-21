/// 1:1 port of `mediatracker-ui/src/shared/ui/ContextMenu.svelte`.
///
/// Глобальное контекстное меню поверх Navigator: позиционирование с флипом
/// (x/y flip у краёв, clamp 8px), сабменю (flyout слева при нехватке места),
/// hold-to-delete через HoldToDeleteController, Esc/scroll/outside-close.
/// Иконки — lucide_icons_flutter (Icons.ts ⏭️). Позиция fixed z-99999 →
/// Overlay Portal (решение #10). i18n holdToDelete — через tProvider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/index.dart';
import 'context_menu_controller.dart';
import 'hold_to_delete.dart';

/// Мост имя-иконки → IconData 1-в-1 с map из исходника.
const Map<String, IconData> contextMenuIcons = <String, IconData>{
  'edit': LucideIcons.pencil,
  'status': LucideIcons.listChecks,
  'list': LucideIcons.list,
  'copy': LucideIcons.copy,
  'delete': LucideIcons.trash2,
  'search': LucideIcons.search,
  'logs': LucideIcons.fileText,
  'browser': LucideIcons.externalLink,
  'settings': LucideIcons.settings,
  'power': LucideIcons.power,
  'exit': LucideIcons.power,
  'download': LucideIcons.download,
  'folder': LucideIcons.folderOpen,
  'globe': LucideIcons.globe,
  'image': LucideIcons.image,
  'link': LucideIcons.link2,
  'refresh': LucideIcons.refreshCw,
  'dices': LucideIcons.dices,
};

IconData? getContextMenuIcon(String? name) =>
    name == null ? null : contextMenuIcons[name];

/// CSS-цвета контекстного меню 1-в-1 (.context-menu*).
const Color _menuBg = Color(0xFF181B24);
const Color _menuBorder = Color(0x1AFFFFFF);
const Color _itemText = Color(0xFFE8EAED);
const Color _itemHover = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
const Color _iconColor = Color(0xFF94A3B8);
const Color _iconHover = Color(0xFFF1F5F9);
const Color _dangerText = Color(0xFFFB7185); // text-rose-400
const Color _dangerHoverBg = Color(0x1AF43F94); // hover:bg-rose-500/10
const Color _dangerHoverText = Color(0xFFFDA4AF);
const Color _chevronColor = Color(0xFF64748B);
const Color _separatorColor = Color(0x14FFFFFF);

/// Глобальное контекстное меню; монтируется в AppShell (Фаза 3) поверх всех
/// view. Показ управляется [contextMenuStoreProvider].
class ContextMenu extends ConsumerStatefulWidget {
  const ContextMenu({super.key});

  @override
  ConsumerState<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends ConsumerState<ContextMenu> {
  Offset? _renderedPosition;
  bool _isPositioned = false;
  String? _expandedSubmenu;
  bool _openSubmenuToLeft = false;

  // Hold-to-delete: один общий контроллер с замыканиями на state (актуальный
  // heldItem читается в момент завершения холда — 1-в-1 с исходником).
  MenuItem? _heldItem;
  String? _heldItemId;
  String? _hintItemId;
  late final HoldToDeleteController _menuHold = HoldToDeleteController(
    HoldToDeleteOptions(
      onComplete: () {
        final held = _heldItem;
        _heldItem = null;
        _heldItemId = null;
        held?.action?.call();
        _closeMenu();
      },
      onShortPress: () {
        _hintItemId = _heldItemId;
      },
      isEnabled: () => _heldItem?.disabled != true,
    ),
  );

  List<MenuItem> _lastItems = const <MenuItem>[];

  @override
  void dispose() {
    _menuHold.dispose();
    super.dispose();
  }

  void _resetForOpen(ContextMenuState state) {
    _menuHold.dispose();
    _heldItem = null;
    _heldItemId = null;
    _hintItemId = null;
    _expandedSubmenu = null;
    _isPositioned = false;
    _openSubmenuToLeft = false;
    _renderedPosition = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _renderedPosition = _updatePosition(state);
        _isPositioned = true;
      });
    });
  }

  /// updatePosition(): флип у краёв + clamp 8px 1-в-1.
  Offset _updatePosition(ContextMenuState state) {
    const width = 220.0;
    const height = 200.0;
    final viewport = MediaQuery.sizeOf(context);

    var x = state.x;
    var y = state.y;

    if (x + width > viewport.width) {
      x = x - width;
    }
    if (y + height > viewport.height) {
      y = y - height;
    }

    final renderedX =
        x.clamp(8.0, (viewport.width - width - 8) < 8 ? 8.0 : viewport.width - width - 8);
    final renderedY =
        y.clamp(8.0, (viewport.height - height - 8) < 8 ? 8.0 : viewport.height - height - 8);
    _openSubmenuToLeft = renderedX + width + 190 > viewport.width;
    return Offset(renderedX, renderedY);
  }

  void _closeMenu() {
    _menuHold.dispose();
    ref.read(contextMenuStoreProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contextMenuStoreProvider);
    final t = ref.watch(tProvider);

    // $effect(isOpen): сброс hold/подменю + позиционирование после кадра.
    if (state.isOpen && !identical(state.items, _lastItems)) {
      _lastItems = state.items;
      _resetForOpen(state);
    } else if (!state.isOpen && _isPositioned) {
      _isPositioned = false;
    }

    if (!state.isOpen) return const SizedBox.shrink();

    final position = _renderedPosition ?? Offset(state.x, state.y);
    final isPositioned = _renderedPosition != null;

    return Stack(
      children: [
        // Outside close: pointerdown вне меню — как исходник (capture).
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _closeMenu(),
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Opacity(
            opacity: isPositioned ? 1.0 : 0.0, // visibility hidden до позиции
            child: _MenuPanel(
              items: state.items,
              deletingLabel: t.tr('holdToDelete.deleting'),
              hintLabel: t.tr('holdToDelete.hint'),
              title: t.tr('contextMenu.title'),
              onEscape: _closeMenu,
              expandedSubmenu: _expandedSubmenu,
              openSubmenuToLeft: _openSubmenuToLeft,
              onSubmenuToggle: (id) {
                setState(() {
                  _expandedSubmenu = _expandedSubmenu == id ? null : id;
                });
              },
              onSubmenuClose: () {
                setState(() => _expandedSubmenu = null);
                _closeMenu();
              },
              onHoverReset: () {
                setState(() => _expandedSubmenu = null);
              },
              heldItemId: _heldItemId,
              hintItemId: _hintItemId,
              menuHold: _menuHold,
              heldItem: _heldItem,
              onHoldStart: (item) {
                _heldItem = item;
                _heldItemId = item.id;
                _menuHold.press();
              },
              onHoldRelease: () => _menuHold.release(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Панель меню (items/подменю/hold) — отдельный виджет.
class _MenuPanel extends StatelessWidget {
  final List<MenuItem> items;
  final String deletingLabel;
  final String hintLabel;
  final String title;
  final VoidCallback onEscape;
  final String? expandedSubmenu;
  final bool openSubmenuToLeft;
  final void Function(String id) onSubmenuToggle;
  final void Function() onSubmenuClose;
  final void Function() onHoverReset;
  final String? heldItemId;
  final String? hintItemId;
  final HoldToDeleteController menuHold;
  final MenuItem? heldItem;
  final void Function(MenuItem item) onHoldStart;
  final void Function() onHoldRelease;

  const _MenuPanel({
    required this.items,
    required this.deletingLabel,
    required this.hintLabel,
    required this.title,
    required this.onEscape,
    required this.expandedSubmenu,
    required this.openSubmenuToLeft,
    required this.onSubmenuToggle,
    required this.onSubmenuClose,
    required this.onHoverReset,
    required this.heldItemId,
    required this.hintItemId,
    required this.menuHold,
    required this.heldItem,
    required this.onHoldStart,
    required this.onHoldRelease,
    });

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onEscape();
        }
      },
      child: Container(
        // .context-menu: bg/border/radius/padding/min-max/shadow/шрифт 1-в-1.
        width: 220,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _menuBg,
          border: Border.all(color: _menuBorder),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0xCC000000), offset: Offset(0, 20), blurRadius: 48),
            BoxShadow(color: Color(0x0DFFFFFF)),
          ],
        ),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item.kind == 'separator')
                const _Separator()
              else
                _buildItem(context, item),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, MenuItem item) {
    final icon = getContextMenuIcon(item.icon);
    final isSubmenu = (item.children?.isNotEmpty ?? false);
    final isExpanded = isSubmenu && expandedSubmenu == item.id;
    final isDanger = item.kind == 'danger';

    if (isSubmenu) {
      return _SubmenuWrapper(
        isExpanded: isExpanded,
        onEnter: () => onSubmenuToggle(item.id),
        onExit: () => onHoverReset(),
        flyoutLeft: openSubmenuToLeft,
        trigger: _MenuItemButton(
          label: item.label ?? '',
          icon: icon,
          danger: isDanger,
          disabled: item.disabled,
          active: isExpanded,
          showChevron: true,
          onTap: () => onSubmenuToggle(item.id),
        ),
        children: [
          for (final sub in item.children ?? const <MenuItem>[])
            _MenuItemButton(
              label: sub.label ?? '',
              isSubmenuChild: true,
              onTap: () {
                sub.action?.call();
                onSubmenuClose();
              },
            ),
        ],
      );
    }

    if (item.holdToDelete) {
      return _HoldToDeleteMenuItem(
        item: item,
        icon: icon,
        isDanger: isDanger,
        isHeld: heldItemId == item.id,
        showHint: hintItemId == item.id && menuHold.hintVisible,
        progress: heldItemId == item.id ? menuHold.progress : 0,
        holding: menuHold.holding,
        onHoldStart: () => onHoldStart(item),
        onHoldRelease: onHoldRelease,
        onHoverReset: onHoverReset,
        deletingLabel: deletingLabel,
        hintLabel: hintLabel,
      );
    }

    return _MenuItemButton(
      label: item.label ?? '',
      icon: icon,
      danger: isDanger,
      disabled: item.disabled,
      onTap: () {
        item.action?.call();
        onSubmenuClose();
      },
      onHoverReset: onHoverReset,
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: _separatorColor,
    );
  }
}

class _MenuItemButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool danger;
  final bool disabled;
  final bool active;
  final bool showChevron;
  final bool isSubmenuChild;
  final VoidCallback? onTap;
  final void Function()? onHoverReset;

  const _MenuItemButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.disabled = false,
    this.active = false,
    this.showChevron = false,
    this.isSubmenuChild = false,
    this.onHoverReset,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = danger ? _dangerText : (active ? _iconHover : _itemText);
    final hoverBg = danger ? _dangerHoverBg : _itemHover;
    final hoverText = danger ? _dangerHoverText : _iconHover;

    return Opacity(
      opacity: disabled ? 0.4 : 1.0, // .context-menu-item_disabled
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          hoverColor: hoverBg,
          borderRadius: BorderRadius.circular(8),
          child: MouseRegion(
            cursor: disabled
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: onHoverReset == null
                ? null
                : (_) => onHoverReset!(),
            child: Padding(
              // padding: 7px 10px (или 6px 10px для подменю):
              padding: EdgeInsets.symmetric(
                  vertical: isSubmenuChild ? 6 : 7, horizontal: 10),
              child: Row(
                children: [
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(icon,
                          size: 15,
                          color: danger || active ? hoverText : _iconColor),
                    ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
                  if (showChevron)
                    const Icon(Icons.chevron_right,
                        size: 14, color: _chevronColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmenuWrapper extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final bool flyoutLeft;
  final Widget trigger;
  final List<Widget> children;

  const _SubmenuWrapper({
    required this.isExpanded,
    required this.onEnter,
    required this.onExit,
    required this.flyoutLeft,
    required this.trigger,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          trigger,
          // Решение #24: inline-раскрытие подменю вместо absolute-flyout —
          // flyout с точными viewport-координатами отложен до Фазы 2 сетки.
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

class _HoldToDeleteMenuItem extends StatelessWidget {
  final MenuItem item;
  final IconData? icon;
  final bool isDanger;
  final bool isHeld;
  final bool showHint;
  final double progress;
  final bool holding;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldRelease;
  final VoidCallback onHoverReset;
  final String deletingLabel;
  final String hintLabel;

  const _HoldToDeleteMenuItem({
    required this.item,
    required this.icon,
    required this.isDanger,
    required this.isHeld,
    required this.showHint,
    required this.progress,
    required this.holding,
    required this.deletingLabel,
    required this.hintLabel,
    required this.onHoldStart,
    required this.onHoldRelease,
      required this.onHoverReset,
  });

  @override
  Widget build(BuildContext context) {
    final label = isHeld && holding
        ? deletingLabel
        : showHint
            ? hintLabel
            : item.label ?? '';
    return Opacity(
      opacity: item.disabled ? 0.4 : 1.0,
      child: Stack(
        children: [
          // hold fill: bg-danger/30 origin-left.
          if (isHeld)
            Positioned.fill(
              child: IgnorePointer(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(color: const Color(0x4DB92B42)),
                ),
              ),
            ),
          GestureDetector(
            onLongPressStart: (_) => onHoldStart(),
            onLongPressEnd: (_) => onHoldRelease(),
            onLongPressCancel: onHoldRelease,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                child: Row(
                  children: [
                    if (icon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(icon,
                            size: 15,
                            color: isDanger ? _dangerText : _iconColor),
                      ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: isDanger ? _dangerText : _itemText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
