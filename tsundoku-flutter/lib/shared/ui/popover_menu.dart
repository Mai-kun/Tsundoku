/// 1:1 port of `mediatracker-ui/src/shared/ui/PopoverMenu.svelte`.
///
/// Нативный popover → Flutter OverlayPortal (позиция в viewport-координатах,
/// привязка к триггеру 1-в-1: bottom/bottom-start/bottom-end/top + EDGE=8
/// clamp + флип при нехватке места снизу). Hover-режим (openOnHover) с
/// deferred close (`closeDelay` 180ms) сохранён. Строгий прямоугольник без
/// декоративной стрелки. 140ms fade+settle — app.css [popover] rule
/// (решение #22).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_theme.dart';



import '../theme/tsundoku_tokens.dart';

/// Опция поповера (`PopoverOption<T>`).
class PopoverOption<T> {
  final T value;
  final String label;

  /// Опциональная иконка слева — аналог renderOption-сниппета Svelte
  /// (FilterBar/FilterMenu рендерят иконки опций). Additive к Фазе 1.
  final IconData? leading;

  const PopoverOption({required this.value, required this.label, this.leading});
}

/// `"bottom" | "bottom-start" | "bottom-end" | "top"`.
enum PopoverPlacement { bottom, bottomStart, bottomEnd, top }

/// Контекст триггера (аналог snippet-параметров trigger).
class PopoverTriggerContext {
  final bool isOpen;
  const PopoverTriggerContext({required this.isOpen});
}

/// Контекст опции (renderOption).
class PopoverOptionContext<T> {
  final PopoverOption<T> option;
  final bool selected;
  const PopoverOptionContext({required this.option, required this.selected});
}

/// Контекст футера.
class PopoverFooterContext {
  final void Function() close;
  const PopoverFooterContext({required this.close});
}

/// Global coordinator ensuring only one popover is open at any time.
/// Like the browser native [popover] behavior, opening any popover
/// automatically dismisses any previously active popover.
class PopoverCoordinator {
  PopoverCoordinator._();
  static final PopoverCoordinator instance = PopoverCoordinator._();

  VoidCallback? _activeDismiss;

  /// Registers an opened popover. If another popover is currently open,
  /// its dismiss callback is invoked immediately.
  void registerOpen(VoidCallback dismiss) {
    if (_activeDismiss != null && _activeDismiss != dismiss) {
      final prev = _activeDismiss;
      _activeDismiss = null;
      prev?.call();
    }
    _activeDismiss = dismiss;
  }

  /// Unregisters the dismiss callback if it was active.
  void unregister(VoidCallback dismiss) {
    if (_activeDismiss == dismiss) {
      _activeDismiss = null;
    }
  }

  /// Closes the currently active popover if any.
  void closeAll() {
    final active = _activeDismiss;
    _activeDismiss = null;
    active?.call();
  }
}

const double _edge = 8;
const double _defaultPopoverHeight = 220;
const double _gapBelowTrigger = 8;

/// Поповер-меню с привязкой к триггеру. Триггер передаётся как builder —
/// Flutter-эквивалент Svelte-snippet; [PopoverTriggerContext.isOpen] отражает
/// текущее состояние.
class TsundokuPopoverMenu<T> extends StatefulWidget {
  final String id;
  final List<PopoverOption<T>> options;
  final T selected;
  final void Function(T value) onSelect;
  final Widget Function(BuildContext context, PopoverTriggerContext ctx) trigger;
  final PopoverPlacement placement;
  final bool matchTriggerWidth;
  /// Open on hover and close after [closeDelay] ms.
  final bool openOnHover;
  final int closeDelay;
  final String label;
  final String optionClass;
  final Widget Function(BuildContext, PopoverFooterContext)? footer;

  /// Полностью кастомная строка опции — аналог renderOption-сниппета Svelte
  /// (звёзды-избранное в DetailSidebar, иконки в меню «…»). Additive к Фазе 1
  /// (как PopoverOption.leading). null → стандартный рендер.
  final Widget Function(BuildContext, PopoverOptionContext<T>)? optionBuilder;
  final bool initiallyOpen;

  const TsundokuPopoverMenu({
    super.key,
    required this.id,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.trigger,
    this.placement = PopoverPlacement.bottomStart,
    this.matchTriggerWidth = false,
    this.openOnHover = false,
    this.closeDelay = 180,
    required this.label,
    this.optionClass = '',
    this.footer,
    this.optionBuilder,
    this.initiallyOpen = false,
  });

  @override
  State<TsundokuPopoverMenu<T>> createState() => _TsundokuPopoverMenuState<T>();
}

class _TsundokuPopoverMenuState<T> extends State<TsundokuPopoverMenu<T>> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _triggerKey = GlobalKey();
  Rect? _lastKnownTriggerRect;
  Timer? _closeTimer;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
  }

  void _toggle() {
    if (_isOpen) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    _cancelPendingClose();
    PopoverCoordinator.instance.registerOpen(_hide);
    setState(() => _isOpen = true);
    _portalController.show();
  }

  void _hide() {
    PopoverCoordinator.instance.unregister(_hide);
    if (!mounted) return;
    if (_isOpen || _portalController.isShowing) {
      setState(() => _isOpen = false);
      if (_portalController.isShowing) _portalController.hide();
    }
  }

  void _select(T value) {
    widget.onSelect(value);
    // A single-value select closes right after picking (см. Select.svelte).
    if (!_isOpen) return;
    _hide();
  }

  Rect? _triggerRect(BuildContext context) {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      _lastKnownTriggerRect = rect;
      return rect;
    }
    return _lastKnownTriggerRect;
  }

  /// Позиция поповера 1-в-1 с placePopover() из исходника (viewport-координаты,
  /// EDGE=8 clamp, флип вверх при нехватке места снизу). Никогда не фолбэчится в (0, 0).
  Offset _place(Size size, Rect? triggerRect, BuildContext menuContext) {
    final viewport = MediaQuery.sizeOf(menuContext);
    final width = widget.matchTriggerWidth
        ? (triggerRect?.width ?? size.width)
        : size.width;
    final height = size.height > 0 ? size.height : _defaultPopoverHeight;

    if (triggerRect == null || (triggerRect.width == 0 && triggerRect.height == 0)) {
      final fallbackLeft =
          ((viewport.width - width) / 2).clamp(_edge, (viewport.width - width - _edge).clamp(_edge, double.infinity));
      final fallbackTop =
          (56.0 + _gapBelowTrigger).clamp(_edge, (viewport.height - height - _edge).clamp(_edge, double.infinity));
      return Offset(fallbackLeft, fallbackTop);
    }

    final rect = triggerRect;
    var left = switch (widget.placement) {
      PopoverPlacement.bottomEnd => rect.right - width,
      PopoverPlacement.bottom => rect.left + rect.width / 2 - width / 2,
      _ => rect.left,
    };
    left = left.clamp(_edge, (viewport.width - width - _edge).clamp(_edge, double.infinity));

    var top = rect.bottom + _gapBelowTrigger;
    if (widget.placement == PopoverPlacement.top ||
        (top + height > viewport.height - _edge &&
            rect.top - height - _gapBelowTrigger > _edge)) {
      top = rect.top - height - _gapBelowTrigger;
    } else if (top + height > viewport.height - _edge) {
      top = viewport.height - height - _edge;
    }
    top = top.clamp(_edge, (viewport.height - height - _edge).clamp(_edge, double.infinity));

    return Offset(left, top);
  }

  /* Hover mode: the cursor has to cross the gap between trigger and menu, so
     the close is deferred and cancelled again as soon as the menu is entered. */
  void _scheduleClose() {
    if (!widget.openOnHover) return;
    _cancelPendingClose();
    _closeTimer = Timer(Duration(milliseconds: widget.closeDelay), _hide);
  }

  void _cancelPendingClose() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  @override
  void dispose() {
    PopoverCoordinator.instance.unregister(_hide);
    _cancelPendingClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final triggerContext = PopoverTriggerContext(isOpen: _isOpen);

    Widget trigger;
    if (widget.openOnHover) {
      trigger = KeyedSubtree(
        key: _triggerKey,
        child: MouseRegion(
          onEnter: (_) {
            _cancelPendingClose();
            if (!_isOpen) _show();
          },
          onExit: (_) => _scheduleClose(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: widget.trigger(context, triggerContext),
          ),
        ),
      );
    } else {
      trigger = KeyedSubtree(
        key: _triggerKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: widget.trigger(context, triggerContext),
        ),
      );
    }

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (menuContext) {
        final triggerRect = _triggerRect(menuContext);
        final defaultW = widget.matchTriggerWidth ? (triggerRect?.width ?? 140.0) : 140.0;
        final size = Size(defaultW, _defaultPopoverHeight);
        final position = _place(size, triggerRect, menuContext);
        final width = widget.matchTriggerWidth
            ? triggerRect?.width ?? defaultW
            : null;

        final menu = Material(
          color: const Color(0xFF151922), // bg-[#151922] strictly matching Svelte --bg-overlay
          elevation: 12,
          shadowColor: const Color(0x80000000),
          borderOnForeground: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsundokuPalette.radiusSelector),
            side: const BorderSide(color: Color(0x14FFFFFF)), // border-white/10
          ),
          child: Container(
            padding: const EdgeInsets.all(4), // p-1
            constraints: BoxConstraints(
              minWidth: widget.matchTriggerWidth ? (triggerRect?.width ?? 110) : 110,
              maxWidth: width ?? 240, // compact 110-240px instead of bloated width
            ),
            child: IntrinsicWidth(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in widget.options)
                      _MenuOptionButton<T>(
                        option: option,
                        selected: option.value == widget.selected,
                        onSelect: _select,
                        optionClass: widget.optionClass,
                        optionBuilder: widget.optionBuilder,
                      ),
                  if (widget.footer != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding:
                          const EdgeInsets.fromLTRB(6, 6, 6, 4), // pt-1.5 pb-1 px-1.5
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: Color(0x14FFFFFF))),
                      ),
                      child: widget.footer!(
                          menuContext,
                          PopoverFooterContext(close: _hide)),
                    ),
                ],
              ),
            ),
          ),
          ),
        );

        return TapRegion(
          groupId: widget.id,
          onTapOutside: (_) => _hide(),
          child: Stack(
            children: [
              Positioned(
                left: position.dx,
                top: position.dy,
                child: MouseRegion(
                  onEnter: (_) {
                    if (widget.openOnHover) _cancelPendingClose();
                  },
                  onExit: (_) {
                    if (widget.openOnHover) _scheduleClose();
                  },
                  child: menu,
                ),
              ),
            ],
          ),
        );
      },
      child: TapRegion(
        groupId: widget.id,
        child: trigger,
      ),
    );
  }
}

class _MenuOptionButton<T> extends StatelessWidget {
  final PopoverOption<T> option;
  final bool selected;
  final void Function(T value) onSelect;
  final String optionClass;
  final Widget Function(BuildContext, PopoverOptionContext<T>)? optionBuilder;

  const _MenuOptionButton({
    required this.option,
    required this.selected,
    required this.onSelect,
    required this.optionClass,
    this.optionBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    if (optionBuilder != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(option.value),
          borderRadius: BorderRadius.circular(4),
          hoverColor: const Color(0x0DFFFFFF), // hover:bg-white/5
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // px-3 py-1.5
            child: optionBuilder!(
              context,
              PopoverOptionContext<T>(option: option, selected: selected),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(option.value),
        borderRadius: BorderRadius.circular(2), // rounded-sm = 2px
        hoverColor: const Color(0x0DFFFFFF), // hover:bg-white/5
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
          child: Row(
            children: [
              if (option.leading != null) ...[
                Icon(
                  option.leading,
                  size: 14,
                  color: selected ? th.accentSoft : th.textMuted,
                ),
                const SizedBox(width: 8), // gap-2
              ],
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14, // text-sm = 14px
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? th.accentSoft : th.textMuted,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check,
                    size: 14, color: th.accentSoft), // Check size={14}
            ],
          ),
        ),
      ),
    );
  }
}

/// `Select.svelte` — обёртка над TsundokuPopoverMenu: одиночный выбор с
/// закрытием после пика (1-в-1 с handleSelect → hidePopover).
class TsundokuSelect<T> extends StatelessWidget {
  final String id;
  final List<PopoverOption<T>> options;
  final T value;
  final void Function(T value) onChange;
  final String placeholder;
  final bool disabled;
  /// aria-label для триггера; по умолчанию — label выбранного.
  final String? label;
  final bool matchTriggerWidth;
  final double? width;
  final double? height;

  const TsundokuSelect({
    super.key,
    required this.id,
    required this.options,
    required this.value,
    required this.onChange,
    this.placeholder = '',
    this.disabled = false,
    this.label,
    this.matchTriggerWidth = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel =
        options.where((o) => o.value == value).map((o) => o.label).firstOrNull ??
            placeholder;

    return AbsorbPointer(
      absorbing: disabled, // disabled: тапы поглощаются, меню не открывается
      child: TsundokuPopoverMenu<T>(
      id: id,
      options: options,
      selected: value,
      onSelect: onChange,
      label: label ?? selectedLabel,
      placement: PopoverPlacement.bottomStart,
      matchTriggerWidth: matchTriggerWidth,
      // Кнопка — визуал: тап уходит в GestureDetector поповера.
      // IgnorePointer исключает кнопку из арены (🐛 #6 — до фикса селектор
      // не открывался: TextButton выигрывал арену у GestureDetector).
      trigger: (context, ctx) => IgnorePointer(
        // Кнопка всегда чисто визуальная (🐛 #6): ignoring: false пропускал
        // хиты в TextButton с ненулевым onPressed — он выигрывал арену жестов
        // и селектор не открывался. Disabled гейтится AbsorbPointer'ом.
        child: TextButton(
        onPressed: null,
        style: TextButton.styleFrom(
          foregroundColor: Colors.transparent,
          backgroundColor: const Color(0xFF1C202B), // bg-[#1c202b]
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8), // rounded-lg = 8px
            side: const BorderSide(
                color: Color(0x1AFFFFFF)), // border-white/10
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
          fixedSize: width != null
              ? Size(width!, height ?? 40)
              : Size.fromHeight(height ?? 40),
          minimumSize: width != null
              ? Size(width!, height ?? 40)
              : Size.fromHeight(height ?? 40),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFFF3F4F6)), // text-ink text-sm
              ),
            ),
            const Icon(Icons.expand_more,
                size: 14, color: Color(0xFF9CA3AF)), // ChevronDown text-muted
          ],
        ),
      ),
      ),
      ),
    );
  }
}
