/// 1:1 port of `mediatracker-ui/src/shared/ui/MediaCoverPlaceholder.svelte`.
///
/// Градиентный фон + /placeholder-404.jpg (asset из media-сервера, здесь —
/// ассет-фолбэк) + нижний бейдж-лейбл «Обложка не найдена».
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/index.dart';
import 'tsundoku_image.dart';

class MediaCoverPlaceholder extends ConsumerWidget {
  /// Переопределяет label (по умолчанию activity.coverMissing).
  final String? label;

  const MediaCoverPlaceholder({super.key, this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final text = label ?? t.tr('activity.coverMissing');
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // bg-gradient-to-br from-[#12151c] to-[#1a1e28]:
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12151C), Color(0xFF1A1E28)],
              ),
            ),
            child: SizedBox.expand(),
          ),
          // Mascot 404 image: opacity-90, object-cover
          Opacity(
            opacity: 0.9,
            child: Image.asset(
              'assets/images/placeholder-404.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const TsundokuImage(
                imageUrl: '/placeholder-404.jpg',
                fit: BoxFit.cover,
                errorWidget: SizedBox.shrink(),
              ),
            ),
          ),
          // Нижний бейдж: absolute inset-x-0 bottom-0, gradient black/85→0.
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xD9000000), // black/85
                    Color(0x66000000), // black/40
                    Color(0x00000000),
                  ],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFCBD5E1), // text-slate-300
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
