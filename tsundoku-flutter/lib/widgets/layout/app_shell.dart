/// 1:1 port of `mediatracker-ui/src/widgets/layout/AppShell.svelte`.
///
/// Каркас: canvas-фон, h-dvh; десктоп (lg ≥1024) — сайдбар-колонка 240px
/// слева (border-r, px-3 py-5), контент справа (header h-14 border-b +
/// main#main-scroll overflow-y-auto p-6); мобайл — сайдбар-рельса снизу
/// (border-t, px-2 py-2). Оверлеи: ContextMenu, ImageLightbox (top-level —
/// вне view-fade трансформов), ListPicker по activeListPickerMediaId,
/// ToastContainer.
///
/// mainRef (Svelte DOM-хэндл для внешнего скролла) → [mainScrollController].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/lists/list_picker.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/ui/context_menu.dart';
import '../../shared/ui/context_menu_controller.dart';
import '../../shared/ui/image_lightbox.dart';
import 'toast_container.dart';

/// `lg:`-граница (та же, что у Sidebar).
const double kTsundokuLgBreakpoint = 1024;

class AppShell extends ConsumerWidget {
  final Widget sidebar;
  final Widget header;
  final Widget child;

  /// mainRef: контроллер скролла main-области (внешнее управление прокруткой).
  final ScrollController? mainScrollController;
  final bool noPadding;

  const AppShell({
    super.key,
    required this.sidebar,
    required this.header,
    required this.child,
    this.mainScrollController,
    this.noPadding = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = TsundokuTheme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= kTsundokuLgBreakpoint;
    final listPickerMediaId = ref.watch(activeListPickerMediaIdProvider);

    final mainArea = Container(
      color: th.bgCanvas, // bg-canvas
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header: bg-surface h-14 border-b border-white/[0.07] z-20.
          Container(
            key: const Key('appshell-header'), // data-widget="header"
            height: 56, // h-14
            decoration: BoxDecoration(
              color: th.bgSurface, // bg-surface
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withAlpha(18)), // white/[0.07]
              ),
            ),
            child: header,
          ),
          // main#main-scroll: min-h-0 flex-1 overflow.
          Expanded(
            key: const Key('appshell-main'), // #main-scroll
            child: SingleChildScrollView(
              controller: mainScrollController,
              // overflow-x-hidden + noPadding → h-full overflow-hidden p-0.
              physics: noPadding ? const NeverScrollableScrollPhysics() : null,
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: noPadding ? double.infinity : 0,
                ),
                child: noPadding
                    ? SizedBox(
                        height: MediaQuery.sizeOf(context).height - 56,
                        child: child,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24), // p-6
                        child: child,
                      ),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget shell;
    if (isDesktop) {
      shell = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // aside: lg:w-60 lg:border-r lg:px-3 lg:py-5.
          Container(
            key: const Key('appshell-sidebar'), // data-widget="sidebar"
            width: 240, // lg:w-60
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            decoration: BoxDecoration(
              color: th.bgSurface, // bg-surface
              border: Border(
                right: BorderSide(
                    color: Colors.white.withAlpha(18)), // border-r white/[0.07]
              ),
            ),
            child: sidebar,
          ),
          Expanded(child: mainArea),
        ],
      );
    } else {
      // Мобайл: aside fixed inset-x-0 bottom-0 border-t px-2 py-2.
      shell = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: mainArea),
          Container(
            key: const Key('appshell-sidebar'), // data-widget="sidebar"
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: th.bgSurface,
              border: Border(
                top: BorderSide(color: Colors.white.withAlpha(18)),
              ),
            ),
            child: sidebar,
          ),
        ],
      );
    }

    // Оверлеи — top-level поверх каркаса.
    return Container(
      color: th.bgCanvas,
      child: Stack(
        children: [
          Positioned.fill(child: shell),
          const ContextMenu(),
          const ImageLightbox(),
          if (listPickerMediaId != null)
            ListPicker(
              key: ValueKey('list-picker-$listPickerMediaId'),
              mediaId: listPickerMediaId,
              isOpen: true,
              showTrigger: false,
              onClose: () => closeListPicker(ref),
              onCreateList: null, // CreateListModal подключается в Фазе 5
            ),
          const ToastContainer(),
        ],
      ),
    );
  }
}
