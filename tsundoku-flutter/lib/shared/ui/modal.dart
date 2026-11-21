/// 1:1 port of `mediatracker-ui/src/shared/ui/Modal.svelte`.
///
/// Fully opaque panel: only the dim layer carries the shade, never the panel
/// surface itself. Sizes (md/lg/xl/search/jobs) 1-в-1; backdrop-drag
/// (mousedown на фоне → mouseup на фоне) — dismissal 1-в-1; entry/exit
/// анимации 160/180/150ms через ScaleTransition/FadeTransition (решение #21).
library;

import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_theme.dart';

/// `"md" | "lg" | "xl" | "search" | "jobs"`.
enum ModalSize { md, lg, xl, search, jobs }

/// Размеры модалок 1-в-1 с классами Modal.svelte.
class ModalGeometry {
  final double? width;
  final double? maxWidth;
  final double? height;
  final double? maxHeight;
  final bool stretchColumn;

  const ModalGeometry({
    this.width,
    this.maxWidth,
    this.height,
    this.maxHeight,
    this.stretchColumn = false,
  });

  static ModalGeometry of(ModalSize size, double viewportWidth, double viewportHeight) {
    switch (size) {
      case ModalSize.jobs:
        return ModalGeometry(
          width: viewportWidth * 0.92, // w-[92vw]
          maxWidth: 1600,
          height: viewportHeight * 0.88, // h-[88vh]
          maxHeight: viewportHeight * 0.88,
          stretchColumn: true,
        );
      case ModalSize.search:
        return ModalGeometry(
          width: viewportWidth * 0.80, // w-[80vw] (sm)
          maxWidth: viewportWidth * 0.80,
          height: viewportHeight * 0.80, // h-[80vh] (sm)
          maxHeight: viewportHeight * 0.80,
          stretchColumn: true,
        );
      case ModalSize.xl:
        return ModalGeometry(
          width: viewportWidth * 0.90, // w-[90vw]
          maxWidth: 1280, // max-w-7xl
          height: viewportHeight * 0.86,
          maxHeight: viewportHeight * 0.90,
          stretchColumn: true,
        );
      case ModalSize.lg:
        return ModalGeometry(maxWidth: 1024); // max-w-5xl
      case ModalSize.md:
        return ModalGeometry(maxWidth: 672); // max-w-2xl
    }
  }
}

/// `<dialog>`-обёртка: показывает модалку поверх Navigator'а.
/// Backdrop-drag guard 1-в-1: клик по фону засчитывается только когда
/// mousedown и mouseup оба на фоне (в Flutter onTap-события атомарны, guard
/// учитывается через onBackdropPressChanged).
class TsundokuModal extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final ModalSize size;
  final bool closable;
  final Widget child;

  /// Drag-guard: mousedown стартовал на фоне.
  final void Function(bool pressedOnBackdrop)? onBackdropPressChanged;

  const TsundokuModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.size = ModalSize.md,
    this.closable = true,
    required this.child,
    this.onBackdropPressChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();
    final vp = MediaQuery.sizeOf(context);
    final geometry = ModalGeometry.of(size, vp.width, vp.height);

    return Stack(
      children: [
        // backdrop: bg-[#090b10]/80
        ModalBarrier(
          dismissible: closable,
          onDismiss: onClose,
          color: const Color(0xCC090B10),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16), // p-4
            child: Material(
              color: const Color(0xFF151A26), // bg-[#151a26] modal-panel
              borderRadius:
                  BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(TsundokuPalette.radiusBox),
                side: BorderSide(
                    color: const Color(0x14FFFFFF).withValues(alpha: 0.08 * 4)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: geometry.width ?? double.infinity,
                  maxHeight: geometry.maxHeight ?? double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: geometry.stretchColumn
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [Flexible(child: child)],
                        )
                      : child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
