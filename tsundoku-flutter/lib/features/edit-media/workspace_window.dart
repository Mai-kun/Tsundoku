/// Порт `mediatracker-ui/src/features/edit-media/WorkspaceWindow.svelte`.
///
/// Одно плавающее окно пространственного edit-канваса. Перетаскивание за
/// шапку, ресайз за правый нижний grip, z-стек у родителя, сворачивание до
/// голого тайтл-бара. Дельты указателя применяются на лету; поверхности драга
/// — только шапка и grip (текст и инпуты тела не трогаются).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/edit-media/workspace_layout.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_scroll.dart';

/// Жёсткие границы вьюпорта (зеркало workspaceLayout): бока 16, полоса
/// тулбара 64 сверху, снизу 16.
const double _sideMargin = 16;
const double _topBar = 64;
const double _bottomMargin = 16;

/// Высота свёрнутого окна: только тайтл-бар.
const double _headerH = 40;

/// Сворачивание анимирует высоту (220ms cubic-bezier(0.16, 1, 0.3, 1));
/// живой ресайз — мгновенно.
const Duration _heightTransition = Duration(milliseconds: 220);

class WorkspaceWindow extends ConsumerStatefulWidget {
  final String id; // WorkspaceWindowId
  final String title;
  final IconData icon;
  final int? count;
  final WorkspaceRect rect;
  final double z;
  final bool highlighted;

  /// Свёрнутое окно рендерится голым тайтл-баром; нити следуют за формой.
  final bool collapsed;
  final ValueChanged<bool>? onCollapsedChange;
  final VoidCallback onFront;
  final ValueChanged<bool> onHoverChange;
  final ValueChanged<bool> onDragStateChange;
  final VoidCallback onSettled;
  final ValueChanged<WorkspaceRect> onRectChange;
  final double viewportW;
  final double viewportH;
  final Widget child;

  const WorkspaceWindow({
    super.key,
    required this.id,
    required this.title,
    required this.icon,
    required this.count,
    required this.rect,
    required this.z,
    required this.highlighted,
    required this.collapsed,
    required this.onCollapsedChange,
    required this.onFront,
    required this.onHoverChange,
    required this.onDragStateChange,
    required this.onSettled,
    required this.onRectChange,
    required this.viewportW,
    required this.viewportH,
    required this.child,
  });

  @override
  ConsumerState<WorkspaceWindow> createState() => _WorkspaceWindowState();
}

class _WorkspaceWindowState extends ConsumerState<WorkspaceWindow> {
  bool _resizing = false;
  ({bool resizing, Offset start, WorkspaceRect origin})? _drag;

  void _apply(WorkspaceRect next) => widget.onRectChange(next);

  void _startDrag(bool resizing, Offset global) {
    if (_drag != null) return;
    widget.onFront();
    widget.onDragStateChange(true);
    setState(() {
      _resizing = resizing;
      _drag = (resizing: resizing, start: global, origin: widget.rect);
    });
  }

  void _handleMove(Offset global) {
    final drag = _drag;
    if (drag == null) return;
    final min = minWindowSize(widget.id);
    final vw = widget.viewportW;
    final vh = widget.viewportH;
    final origin = drag.origin;
    final rect = widget.rect;
    if (!drag.resizing) {
      // Жёсткие границы вьюпорта, live: окно не покидает видимую полосу.
      final x = (origin.x + (global.dx - drag.start.dx))
          .clamp(_sideMargin, math.max(vw - _sideMargin - rect.w, _sideMargin))
          .toDouble();
      final y = (origin.y + (global.dy - drag.start.dy))
          .clamp(_topBar, math.max(vh - _bottomMargin - rect.h, _topBar))
          .toDouble();
      _apply(WorkspaceRect(x: x, y: y, w: rect.w, h: rect.h));
    } else {
      _apply(WorkspaceRect(
        x: rect.x,
        y: rect.y,
        w: math.max(min.w,
            math.min(origin.w + (global.dx - drag.start.dx), vw - rect.x - _sideMargin)),
        h: math.max(min.h,
            math.min(origin.h + (global.dy - drag.start.dy), vh - rect.y - _bottomMargin)),
      ));
    }
  }

  void _finishDrag() {
    if (_drag == null) return;
    setState(() {
      _drag = null;
      _resizing = false;
    });
    widget.onDragStateChange(false);
    widget.onSettled();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final collapsed = widget.collapsed;

    return Positioned(
      left: widget.rect.x,
      top: widget.rect.y,
      width: widget.rect.w,
      child: MouseRegion(
        onEnter: (_) => widget.onHoverChange(true),
        onExit: (_) {
          if (_drag == null) widget.onHoverChange(false);
        },
        child: AnimatedContainer(
          // Сворачивание анимирует высоту; живой ресайз — без анимации.
          duration: _resizing ? Duration.zero : _heightTransition,
          curve: const Cubic(0.16, 1, 0.3, 1),
          height: collapsed ? _headerH : widget.rect.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
              color: widget.highlighted
                  ? th.accent.withAlpha(153) // border-accent/60
                  : Colors.white.withAlpha(20), // border-white/[0.08]
            ),
            color: const Color(0xF212151C), // bg-[#12151c]/95
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000), // shadow-2xl shadow-black/50
                blurRadius: 25,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  // ----------------------------------------------------------
                  // Header (h-10): иконка, title, count, collapse.
                  // ----------------------------------------------------------
                  // GestureDetector (pan, а не raw Listener): арена жестов
                  // доставляет все обновления драга, даже когда указатель
                  // выходит за экран (Svelte-аналог — window-level listeners).
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _startDrag(false, details.globalPosition);
                    },
                    onPanUpdate: (details) =>
                        _handleMove(details.globalPosition),
                    onPanEnd: (_) => _finishDrag(),
                    onPanCancel: () => _finishDrag(),
                    child: Container(
                      // Внешний контейнер несёт border-box: 1px граница
                      // съедает 2px высоты (box-sizing Svelte).
                      height: _headerH - 2,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withAlpha(15)), // white/[0.06]
                        ),
                        color: Colors.white.withAlpha(8), // bg-white/[0.03]
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12), // px-3
                          Container(
                            width: 24, // size-6
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(6), // rounded-md
                              color:
                                  Colors.white.withAlpha(13), // bg-white/[0.05]
                            ),
                            alignment: Alignment.center,
                            child: Icon(widget.icon,
                                size: 15, color: th.accentSoft),
                          ),
                          const SizedBox(width: 8), // gap-2
                          Expanded(
                            child: Text(
                              widget.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.68, // tracking-[0.14em]
                                color: th.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.count != null && widget.count! > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2), // px-2 py-0.5
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.white
                                    .withAlpha(15), // bg-white/[0.06]
                              ),
                              child: Text(
                                '${widget.count}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFCBD5E1), // slate-300
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          // Кнопка сворачивания (не начинает драг шапки).
                          Semantics(
                            label: collapsed
                                ? t.tr('common.expand')
                                : t.tr('common.collapse'),
                            button: true,
                            child: GestureDetector(
                              onTap: () =>
                                  widget.onCollapsedChange?.call(!collapsed),
                              child: SizedBox(
                                width: 24, // size-6
                                height: 24,
                                child: AnimatedRotation(
                                  turns: collapsed ? 0.5 : 0, // rotate-180
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(LucideIcons.chevronUp,
                                      size: 14, color: th.textMuted),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12), // px-3
                        ],
                      ),
                    ),
                  ),
                  // --------------------------------------------------------
                  // Тело: всегда смонтировано; collapse гасит opacity и высоту.
                  // --------------------------------------------------------
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: collapsed ? 0 : 1,
                      child: IgnorePointer(
                        ignoring: collapsed, // inert={collapsed}
                        child: TsundokuSmoothScrollView(
                          padding: const EdgeInsets.all(12), // p-3
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // ------------------------------------------------------------
              // Grip ресайза: правый нижний угол, 3 диагональные линии.
              // ------------------------------------------------------------
              if (!collapsed)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _startDrag(true, details.globalPosition);
                    },
                    onPanUpdate: (details) =>
                        _handleMove(details.globalPosition),
                    onPanEnd: (_) => _finishDrag(),
                    onPanCancel: () => _finishDrag(),
                    child: SizedBox(
                      width: 20, // size-5
                      height: 20,
                      child: CustomPaint(
                        painter: _ResizeGripPainter(
                          color: th.textMuted.withAlpha(153), // text-muted/60
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 3 диагональные линии grip ресайза (svg path M19 7 L7 19 M19 12 L12 19
/// M19 17 L17 19 в viewBox 20x20).
class _ResizeGripPainter extends CustomPainter {
  final Color color;

  const _ResizeGripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (size.width > 0) canvas.scale(size.width / 20);
    final path = Path()
      ..moveTo(19, 7)
      ..lineTo(7, 19)
      ..moveTo(19, 12)
      ..lineTo(12, 19)
      ..moveTo(19, 17)
      ..lineTo(17, 19);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ResizeGripPainter oldDelegate) =>
      oldDelegate.color != color;
}
