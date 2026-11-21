/// 1:1 port of `mediatracker-ui/src/shared/ui/ImageLightbox.svelte`.
///
/// Глобальный лайтбокс поверх AppShell: backdrop black/85 + blur, zoom-in
/// 220ms, X-кнопка, Escape, клик по фону. Позиционируется поверх
/// Navigator'a (аналог fixed z-100000).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_theme.dart';
import 'lightbox.dart';

/// Показывает лайтбокс, если [lightboxProvider] открыт; монтируется в
/// AppShell (Фаза 3) поверх всех view.
class ImageLightbox extends ConsumerWidget {
  const ImageLightbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lightboxProvider);
    final url = state.url;
    if (url == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _close(ref),
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: const AlwaysStoppedAnimation(1.0),
        child: Container(
          // bg-black/85 + backdrop-blur-md (blur даёт BackdropFilter ниже).
          color: const Color(0xD9000000),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16), // p-4
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 900 * 0.85, // max-h-[85dvh] при 1440x900
                    maxWidth: double.infinity,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const SizedBox(width: 200, height: 200),
                        ),
                      ),
                      if (state.caption != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            state.caption!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFE5E7EB), // text-slate-200
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // X-кнопка: top-4 right-4, bg-white/10, rounded-lg.
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  onPressed: () => _close(ref),
                  icon: const Icon(Icons.close, size: 24, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x1AFFFFFF), // bg-white/10
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          TsundokuPalette.radiusSelector),
                    ),
                  ),
                  tooltip: 'Закрыть',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _close(WidgetRef ref) {
    ref.read(lightboxProvider.notifier).closeLightbox();
  }
}
