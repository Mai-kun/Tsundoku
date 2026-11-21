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

  const PopoverOption({required this.value, required this.label});
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

const double _edge = 8;
const double _defaultPopoverWidth = 144;
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
  });

  @override
  State<TsundokuPopoverMenu<T>> createState() => _TsundokuPopoverMenuState<T>();
}

class _TsundokuPopoverMenuState<T> extends State<TsundokuPopoverMenu<T>> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _triggerKey = GlobalKey();
  Timer? _closeTimer;
  bool _isOpen = false;

  void _toggle() {
    if (_isOpen) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    _cancelPendingClose();
    setState(() => _isOpen = true);
    _portalController.show();
  }

  void _hide() {
    setState(() => _isOpen = false);
    if (_portalController.isShowing) _portalController.hide();
  }

  void _select(T value) {
    widget.onSelect(value);
    // A single-value select closes right after picking (см. Select.svelte).
    if (!_isOpen) return;
    _hide();
  }


  Rect? _triggerRect(BuildContext context) {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Позиция поповера 1-в-1 с placePopover() из исходника (viewport-координаты,
  /// EDGE=8 clamp, флип вверх при нехватке места снизу).
  Offset? _place(Size size, Rect triggerRect, BuildContext menuContext) {
    final rect = triggerRect;
    if (rect.width == 0 && rect.height == 0) return null;

    final width = widget.matchTriggerWidth ? rect.width : size.width;
    final height = size.height > 0 ? size.height : _defaultPopoverHeight;
    final viewport = MediaQuery.sizeOf(menuContext);

    var left = switch (widget.placement) {
      PopoverPlacement.bottomEnd => rect.right - width,
      PopoverPlacement.bottom => rect.left + rect.width / 2 - width / 2,
      _ => rect.left,
    };
    left = left.clamp(_edge, viewport.width - width - _edge);

    var top = rect.bottom + _gapBelowTrigger;
    if (widget.placement == PopoverPlacement.top ||
        (top + height > viewport.height - _edge &&
            rect.top - height - _gapBelowTrigger > _edge)) {
      top = rect.top - height - _gapBelowTrigger;
    } else if (top + height > viewport.height - _edge) {
      top = viewport.height - height - _edge;
    }
    top = top < _edge ? _edge : top;

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
    _cancelPendingClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final triggerContext = PopoverTriggerContext(isOpen: _isOpen);

    Widget trigger = GestureDetector(
      onTap: _toggle,
      child: MouseRegion(
        onEnter: (_) {
          if (!widget.openOnHover) return;
          _cancelPendingClose();
          if (!_isOpen) _show();
        },
        onExit: (_) => _scheduleClose(),
        child: widget.trigger(context, triggerContext),
      ),
    );

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (menuContext) {
        final size = Size(_defaultPopoverWidth, _defaultPopoverHeight);
        final triggerRect = _triggerRect(menuContext);
        final position = triggerRect == null
            ? Offset.zero
            : _place(size, triggerRect, menuContext) ?? Offset.zero;
        final width = widget.matchTriggerWidth
            ? triggerRect?.width ?? _defaultPopoverWidth
            : null;

        final menu = Material(
          color: const Color(0xFF1C202B), // bg-[#1c202b]
          borderOnForeground: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsundokuPalette.radiusSelector),
            side: BorderSide(color: const Color(0x14FFFFFF)), // border-white/10
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 144, // min-w-36
              maxWidth: width ?? double.infinity,
            ),
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
        );

        return Stack(
          children: [
            // Клик мимо — закрыть:
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy,
              child: MouseRegion(
                onEnter: (_) => _cancelPendingClose(),
                onExit: (_) => _scheduleClose(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: width ?? _defaultPopoverWidth * 3),
                  child: menu,
                ),
              ),
            ),
          ],
        );
      },
      child: trigger,
    );
  }
}

class _MenuOptionButton<T> extends StatelessWidget {
  final PopoverOption<T> option;
  final bool selected;
  final void Function(T value) onSelect;
  final String optionClass;

  const _MenuOptionButton({
    required this.option,
    required this.selected,
    required this.onSelect,
    required this.optionClass,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(option.value),
        hoverColor: const Color(0x0DFFFFFF), // hover:bg-white/5
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // tap-анимация (active:scale) — через InkWell-подсветку.
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
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
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel =
        options.where((o) => o.value == value).map((o) => o.label).firstOrNull ??
            placeholder;

    return TsundokuPopoverMenu<T>(
      id: id,
      options: options,
      selected: value,
      onSelect: onChange,
      label: label ?? selectedLabel,
      placement: PopoverPlacement.bottomStart,
      matchTriggerWidth: matchTriggerWidth,
      trigger: (context, ctx) => TextButton(
        onPressed: disabled ? null : () {},
        style: TextButton.styleFrom(
          foregroundColor: Colors.transparent,
          backgroundColor: const Color(0xFF1C202B), // bg-[#1c202b]
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsundokuPalette.radiusSelector),
            side: BorderSide(
                color: const Color(0x1AFFFFFF)), // border-white/10
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          fixedSize: const Size.fromHeight(40), // h-10 w-full
          minimumSize: const Size.fromHeight(40),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Icon(Icons.expand_more,
                size: 14, color: Color(0xFF9CA3AF)), // ChevronDown text-muted
          ],
        ),
      ),
    );
  }
}
