/// 1:1 port of `mediatracker-ui/src/widgets/layout/ToastContainer.svelte`.
///
/// Стек тостов bottom-right (420px): тип-бейдж (error/success/warning/info) ↔
/// шеврон разворота (кроссфейд), заголовок, компактный ряд кнопок
/// (undo/actions/OK) ↔ развёрнутый футер (описание + подписанные кнопки),
/// X-закрытие; JS-driven countdown с паузой на hover и 1s-грейсом после
/// ухода — один Timer.periodic-клок (rAF → 16ms, конвенция hold_to_delete).
///
/// Браузерные замены: popover Top Layer — DOM-специфика, не переносится
/// (Flutter Overlay и так выше всего); flip/fly-переходы — AnimatedOpacity/
/// AnimatedSize (вход), выход — мгновенный (dismiss), зафиксировано в
/// Пояснениях.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../shared/ui/toast.dart';

/// Grace window after the pointer leaves: the countdown stays frozen for
/// exactly 1s and only then smoothly resumes (a re-enter cancels it).
const int _graceMs = 1000;

const Duration _frameStep = Duration(milliseconds: 16); // ≈ 60fps rAF

class _TimerState {
  int elapsed = 0;
  int? last;
  int? grace;
}

class ToastContainer extends ConsumerStatefulWidget {
  const ToastContainer({super.key});

  @override
  ConsumerState<ToastContainer> createState() => _ToastContainerState();
}

class _ToastContainerState extends ConsumerState<ToastContainer> {
  final Set<String> _expanded = <String>{};
  final Set<String> _hovered = <String>{};

  // ---------- JS-driven countdown (pause on hover, 1s grace on leave) ----------
  // The bar and the auto-dismiss share one periodic clock: pausing freezes the
  // bar exactly where it is and delays the dismissal by the same amount.

  final Map<String, _TimerState> _timers = <String, _TimerState>{};
  final Map<String, double> _progress = <String, double>{};
  Timer? _clock;

  bool _hasButtons(ToastItem toast) =>
      toast.showOk || toast.undo != null || toast.actions.isNotEmpty;

  void _startTimer(ToastItem toast) {
    if (toast.durationMs <= 0) return;
    _timers.putIfAbsent(
        toast.id, () => _TimerState());
    _ensureClock();
  }

  void _stopTimer(String id) {
    _timers.remove(id);
    _progress.remove(id);
  }

  bool _isPaused(String id) => _hovered.contains(id) || _expanded.contains(id);

  void _tick() {
    final now = clock.now().millisecondsSinceEpoch;
    final toasts = ref.read(toastStoreProvider);
    var active = false;
    for (final toast in toasts) {
      final timer = _timers[toast.id];
      if (timer == null) continue;

      if (timer.last == null) {
        timer.last = now;
        active = true;
        continue;
      }

      final dt = now - timer.last!;
      timer.last = now;
      if (_isPaused(toast.id)) {
        timer.grace = null; // back on the card: any pending grace is cancelled
      } else if (timer.grace != null) {
        timer.grace = timer.grace! - dt;
        if (timer.grace! <= 0) timer.grace = null; // grace over → resume
      } else {
        timer.elapsed += dt;
      }

      final remaining = (1 - timer.elapsed / toast.durationMs)
          .clamp(0.0, 1.0)
          .toDouble();
      _progress[toast.id] = remaining;
      if (remaining <= 0) {
        // Auto-expiry: dismiss without onClose, which stays reserved for X.
        ref.read(toastStoreProvider.notifier).dismiss(toast.id);
        _stopTimer(toast.id);
        continue;
      }
      active = true;
    }
    // Drop clocks of toasts removed through dismissToast (buttons, X).
    for (final id in _timers.keys.toList()) {
      if (!toasts.any((t) => t.id == id)) _stopTimer(id);
    }
    if (mounted) setState(() {}); // перерисовка полос countdown
    // Клок гасим, когда активных тостов не осталось (rAF: rafId = active ? …
    // : 0) — cancel ДО зануления, иначе таймер утекает.
    if (!active) {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _ensureClock() {
    _clock ??= Timer.periodic(_frameStep, (_) => _tick());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _enterCard(ToastItem toast) {
    _hovered.add(toast.id);
    final timer = _timers[toast.id];
    if (timer != null) timer.grace = null; // return cancels pending resume
  }

  void _leaveCard(ToastItem toast) {
    _hovered.remove(toast.id);
    final timer = _timers[toast.id];
    // While expanded the clock stays frozen; otherwise hold exactly 1s.
    if (timer != null && !_expanded.contains(toast.id)) {
      timer.grace = _graceMs;
    }
  }

  void _toggleExpanded(ToastItem toast) {
    setState(() {
      if (_expanded.contains(toast.id)) {
        _expanded.remove(toast.id);
      } else {
        _expanded.add(toast.id);
      }
    });
  }

  void _close(ToastItem toast) {
    toast.onClose?.call();
    _stopTimer(toast.id);
    dismissToast(ref, toast.id);
  }

  void _runAction(ToastItem toast, void Function() onClick) {
    _stopTimer(toast.id);
    dismissToast(ref, toast.id);
    onClick();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final toasts = ref.watch(toastStoreProvider);

    // One clock per toast: registered when the toast appears, unregistered
    // when it leaves (аналог $effect по toastStore.items).
    final ids = <String>{};
    for (final toast in toasts) {
      ids.add(toast.id);
      _startTimer(toast);
    }
    for (final id in _timers.keys.toList()) {
      if (!ids.contains(id)) _stopTimer(id);
    }

    if (toasts.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        // fixed right-5 bottom-5 = 1.25rem = 20px
        padding: const EdgeInsets.only(right: 20, bottom: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420, // w-[420px]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final toast in toasts)
                _ToastCard(
                  key: ValueKey(toast.id),
                  toast: toast,
                  t: t,
                  isExpanded: _expanded.contains(toast.id),
                  isHovered: _hovered.contains(toast.id),
                  progress: _progress[toast.id] ?? 1,
                  hasButtons: _hasButtons(toast),
                  onEnter: () => _enterCard(toast),
                  onLeave: () => _leaveCard(toast),
                  onToggle: () => _toggleExpanded(toast),
                  onClose: () => _close(toast),
                  onRunAction: (action) => _runAction(toast, action),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Цвета типа: badge (bg/border/text) + timer bar (1-в-1 с badgeClasses /
/// timerBarClasses в Svelte).
class _ToastTypeStyle {
  final Color badgeBg;
  final Color badgeBorder;
  final Color text;
  final Color bar;

  const _ToastTypeStyle({
    required this.badgeBg,
    required this.badgeBorder,
    required this.text,
    required this.bar,
  });

  static const _ToastTypeStyle error = _ToastTypeStyle(
    badgeBg: Color(0x26F43F5E), // bg-rose-500/15
    badgeBorder: Color(0x4DF43F5E), // border-rose-500/30
    text: Color(0xFFFB7185), // text-rose-400
    bar: Color(0xE6FB7185), // bg-rose-400/90
  );

  static const _ToastTypeStyle success = _ToastTypeStyle(
    badgeBg: Color(0x2610B981), // bg-emerald-500/15
    badgeBorder: Color(0x4D10B981), // border-emerald-500/30
    text: Color(0xFF34D399), // text-emerald-400
    bar: Color(0xE634D399), // bg-emerald-400/90
  );

  static const _ToastTypeStyle warning = _ToastTypeStyle(
    badgeBg: Color(0x26F59E0B), // bg-amber-500/15
    badgeBorder: Color(0x4DF59E0B), // border-amber-500/30
    text: Color(0xFFFBBF24), // text-amber-400
    bar: Color(0xE6FBBF24), // bg-amber-400/90
  );

  static const _ToastTypeStyle info = _ToastTypeStyle(
    badgeBg: Color(0x260EA5E9), // bg-sky-500/15
    badgeBorder: Color(0x4D0EA5E9), // border-sky-500/30
    text: Color(0xFF38BDF8), // text-sky-400
    bar: Color(0xE638BDF8), // bg-sky-400/90
  );

  static _ToastTypeStyle of(ToastType type) {
    switch (type) {
      case ToastType.error:
        return error;
      case ToastType.success:
        return success;
      case ToastType.warning:
        return warning;
      case ToastType.info:
        return info;
    }
  }

  IconData get icon {
    // Inline-SVG героя иконок в Svelte → ближайшие lucide (1-в-1 формы).
    switch (_currentType) {
      case ToastType.error:
        return LucideIcons.circleAlert;
      case ToastType.success:
        return LucideIcons.circleCheck;
      case ToastType.warning:
        return LucideIcons.triangleAlert;
      case ToastType.info:
        return LucideIcons.info;
    }
  }

  ToastType get _currentType {
    if (identical(this, error)) return ToastType.error;
    if (identical(this, success)) return ToastType.success;
    if (identical(this, warning)) return ToastType.warning;
    return ToastType.info;
  }
}

/// Компактный глиф кастомного действия (1-в-1 с actionIcon).
IconData? _actionIcon(String actionId) {
  switch (actionId) {
    case 'keepStatus':
      return LucideIcons.tag;
    default:
      return null;
  }
}

class _ToastCard extends StatelessWidget {
  final ToastItem toast;
  final I18nDictionary t;
  final bool isExpanded;
  final bool isHovered;
  final double progress;
  final bool hasButtons;
  final VoidCallback onEnter;
  final VoidCallback onLeave;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final void Function(void Function() onClick) onRunAction;

  const _ToastCard({
    super.key,
    required this.toast,
    required this.t,
    required this.isExpanded,
    required this.isHovered,
    required this.progress,
    required this.hasButtons,
    required this.onEnter,
    required this.onLeave,
    required this.onToggle,
    required this.onClose,
    required this.onRunAction,
  });

  /// role="alert" карточка: rounded-xl, border-white/10, bg-[#151a26]/95,
  /// p-3.5, shadow-2xl.
  @override
  Widget build(BuildContext context) {
    final style = _ToastTypeStyle.of(toast.type);
    final showChevron = isHovered || isExpanded;

    return Padding(
      padding: const EdgeInsets.only(top: 10), // gap-2.5 между карточками
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        onExit: (_) => onLeave(),
        child: Container(
          padding: const EdgeInsets.all(14), // p-3.5
          decoration: BoxDecoration(
            color: const Color(0xF2151A26), // bg-[#151a26]/95
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(color: Colors.white.withAlpha(26)), // white/10
            boxShadow: const [
              // shadow-2xl shadow-black/50 (приближение 1-в-1 Tailwind)
              BoxShadow(
                color: Color(0x80000000),
                offset: Offset(0, 25),
                blurRadius: 50,
                spreadRadius: -12,
              ),
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(0, 8),
                blurRadius: 20,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconSlot(
                    toast: toast,
                    style: style,
                    showChevron: showChevron,
                    isExpanded: isExpanded,
                    t: t,
                    onToggle: onToggle,
                  ),
                  const SizedBox(width: 10), // gap-2.5
                  Expanded(
                    child: Text(
                      toast.title,
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        height: 1.375, // leading-snug
                        fontWeight: FontWeight.w600, // font-semibold
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!isExpanded && hasButtons)
                    _CompactButtons(
                      toast: toast,
                      t: t,
                      onRunAction: onRunAction,
                    ),
                  const SizedBox(width: 4),
                  _CloseButton(onClose: onClose, t: t),
                ],
              ),
              // grid-rows 0fr→1fr → AnimatedSize (карточка растёт вверх —
              // Column снизу-вверх в стеке контейнера).
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: const Cubic(0.16, 1, 0.3, 1), // cubic-bezier(0.16,1,0.3,1)
                alignment: Alignment.bottomCenter,
                child: isExpanded
                    ? _ExpandedBody(
                        toast: toast,
                        t: t,
                        hasButtons: hasButtons,
                        onRunAction: onRunAction,
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (toast.durationMs > 0)
                PositionedFillBar(
                  fraction: progress,
                  color: style.bar,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed icon slot: the type badge and the expand chevron crossfade in place.
class _IconSlot extends StatelessWidget {
  final ToastItem toast;
  final _ToastTypeStyle style;
  final bool showChevron;
  final bool isExpanded;
  final I18nDictionary t;
  final VoidCallback onToggle;

  const _IconSlot({
    required this.toast,
    required this.style,
    required this.showChevron,
    required this.isExpanded,
    required this.t,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32, // size-8
      height: 32,
      child: Stack(
        children: [
          // Type badge (scale-75/opacity-0 при chevron).
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showChevron ? 0 : 1,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: showChevron ? 0.75 : 1,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: style.badgeBg,
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  border: Border.all(color: style.badgeBorder),
                ),
                child: Icon(style.icon, size: 16, color: style.text),
              ),
            ),
          ),
          // Chevron button (hover:text-white, title expand/collapse).
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showChevron ? 1 : 0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: showChevron ? 1 : 0.75,
              child: GestureDetector(
                onTap: onToggle,
                child: Tooltip(
                  message: isExpanded ? t.tr('toast.collapse') : t.tr('toast.expand'),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.transparent,
                    ),
                    child: Icon(
                      isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 16,
                      color: const Color(0xFFCBD5E1), // text-slate-300
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon row: undo / actions / OK (collapses into the expanded footer).
class _CompactButtons extends StatelessWidget {
  final ToastItem toast;
  final I18nDictionary t;
  final void Function(void Function() onClick) onRunAction;

  const _CompactButtons({
    required this.toast,
    required this.t,
    required this.onRunAction,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    final undo = toast.undo;
    if (undo != null) {
      buttons.add(_SquareButton(
        size: 28,
        semanticLabel: t.tr('toast.undo'),
        icon: LucideIcons.rotateCw, // RotateCcw size={14}
        iconSize: 14,
        onPressed: () => onRunAction(undo),
      ));
    }
    for (final action in toast.actions) {
      final icon = _actionIcon(action.id);
      buttons.add(_SquareButton(
        size: 28,
        semanticLabel: action.label,
        icon: icon,
        iconSize: 14,
        letterFallback: icon == null ? action.label.characters.first : null,
        onPressed: () => onRunAction(action.onClick),
      ));
    }
    if (toast.showOk) {
      buttons.add(_SquareButton(
        size: 28,
        semanticLabel: t.tr('toast.ok'),
        icon: LucideIcons.check, // Check size={15}
        iconSize: 15,
        background: const Color(0xFF4F46E5), // bg-indigo-600
        hoverBackground: const Color(0xFF6366F1), // hover:bg-indigo-500
        iconColor: Colors.white,
        onPressed: () => onRunAction(() {}),
      ));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final b in buttons) ...[
        if (buttons.first != b) const SizedBox(width: 6), // gap-1.5
        b,
      ]
    ]);
  }
}

/// size-7 rounded-lg border-white/10 bg-white/5 text-slate-300
/// hover:bg-white/10 hover:text-white.
class _SquareButton extends StatefulWidget {
  final double size;
  final String semanticLabel;
  final IconData? icon;
  final double iconSize;
  final String? letterFallback;
  final Color? background;
  final Color? hoverBackground;
  final Color? iconColor;
  final VoidCallback onPressed;

  const _SquareButton({
    required this.size,
    required this.semanticLabel,
    required this.iconSize,
    required this.onPressed,
    this.icon,
    this.letterFallback,
    this.background,
    this.hoverBackground,
    this.iconColor,
  });

  @override
  State<_SquareButton> createState() => _SquareButtonState();
}

class _SquareButtonState extends State<_SquareButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered;
    final bg = widget.background ?? Colors.white.withAlpha(13); // bg-white/5
    final hoverBg =
        widget.hoverBackground ?? Colors.white.withAlpha(26); // hover:bg-white/10
    final fg = widget.iconColor ??
        (hovered ? Colors.white : const Color(0xFFCBD5E1)); // text-slate-300

    return Tooltip(
      message: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: hovered ? hoverBg : bg,
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(color: Colors.white.withAlpha(26)), // white/10
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(widget.icon, size: widget.iconSize, color: fg)
                  : Text(
                      widget.letterFallback ?? '',
                      style: TextStyle(
                        fontSize: 11, // text-[11px]
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// X-кнопка закрытия: rounded-md p-1 text-slate-400 hover:bg-white/10
/// hover:text-white.
class _CloseButton extends StatefulWidget {
  final VoidCallback onClose;
  final I18nDictionary t;

  const _CloseButton({required this.onClose, required this.t});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onClose,
        child: Tooltip(
          message: widget.t.tr('common.close'),
          child: Container(
            padding: const EdgeInsets.all(4), // p-1
            decoration: BoxDecoration(
              color: _hovered ? Colors.white.withAlpha(26) : Colors.transparent,
              borderRadius: BorderRadius.circular(6), // rounded-md
            ),
            child: Icon(
              LucideIcons.x, // X size={16}
              size: 16,
              color: _hovered
                  ? Colors.white
                  : const Color(0xFF94A3B8), // text-slate-400
            ),
          ),
        ),
      ),
    );
  }
}

/// Развёрнутый футер: description (max-h-40, scroll) + подписанные кнопки.
class _ExpandedBody extends StatelessWidget {
  final ToastItem toast;
  final I18nDictionary t;
  final bool hasButtons;
  final void Function(void Function() onClick) onRunAction;

  const _ExpandedBody({
    required this.toast,
    required this.t,
    required this.hasButtons,
    required this.onRunAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8), // pt-2 (border-t white/5)
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x0DFFFFFF)), // border-white/5
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160), // max-h-40
                child: SingleChildScrollView(
                  child: Text(
                    toast.description,
                    style: const TextStyle(
                      fontSize: 11, // text-[11px]
                      height: 1.625, // leading-relaxed
                      color: Color(0xFFCBD5E1), // text-slate-300
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (hasButtons) ...[
            const SizedBox(height: 8), // mt-2
            Wrap(
              spacing: 6, // gap-1.5
              runSpacing: 6,
              children: [
                if (toast.undo != null)
                  _PillButton(
                    label: t.tr('toast.undo'),
                    onPressed: () => onRunAction(toast.undo!),
                  ),
                for (final action in toast.actions)
                  _PillButton(
                    label: action.label,
                    onPressed: () => onRunAction(action.onClick),
                  ),
                if (toast.showOk)
                  _PillButton(
                    label: t.tr('toast.ok'),
                    filled: true, // bg-indigo-600
                    onPressed: () => onRunAction(() {}),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// rounded-md border-white/10 bg-white/5 px-2.5 py-1 text-[11px] font-medium
/// text-slate-200 hover:bg-white/10 hover:text-white; filled → bg-indigo-600.
class _PillButton extends StatefulWidget {
  final String label;
  final bool filled;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // px-2.5 py-1
          decoration: BoxDecoration(
            color: widget.filled
                ? (_hovered
                    ? const Color(0xFF6366F1) // hover:bg-indigo-500
                    : const Color(0xFF4F46E5)) // bg-indigo-600
                : (_hovered ? Colors.white.withAlpha(26) : Colors.white.withAlpha(13)),
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: widget.filled
                ? null
                : Border.all(color: Colors.white.withAlpha(26)), // white/10
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11, // text-[11px]
              fontWeight: widget.filled ? FontWeight.w600 : FontWeight.w500,
              color: widget.filled
                  ? Colors.white
                  : (_hovered ? Colors.white : const Color(0xFFE2E8F0)), // text-slate-200
            ),
          ),
        ),
      ),
    );
  }
}

/// Countdown-полоса 2px снизу: scaleX = remaining fraction (origin-left).
class PositionedFillBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const PositionedFillBar({
    super.key,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(12),
      ),
      child: Stack(
        children: [
          Container(
            height: 2, // h-0.5
            color: Colors.white.withAlpha(13), // bg-white/5
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(height: 2, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
