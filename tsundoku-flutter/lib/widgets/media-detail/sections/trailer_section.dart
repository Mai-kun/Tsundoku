/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/TrailerSection.svelte`.
///
/// Превью трейлера: YouTube-thumbnail + Play; в Svelte — iframe
/// youtube-nocookie при playing; во Flutter iframe недоступен (стек без
/// webview) — Play открывает embed-URL через PlatformService.openExternalUrl
/// (решение #48, фасад §1.3).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/ui/tsundoku_image.dart';

/// Секция трейлера (1-в-1 с TrailerSection.svelte).
class TrailerSection extends ConsumerStatefulWidget {
  final String? trailerVideoId;
  final String title;

  const TrailerSection({
    super.key,
    required this.trailerVideoId,
    required this.title,
  });

  @override
  ConsumerState<TrailerSection> createState() => _TrailerSectionState();
}

class _TrailerSectionState extends ConsumerState<TrailerSection> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final videoId = widget.trailerVideoId;

    if (videoId == null || videoId.isEmpty) {
      return Container(
        // aspect-video w-full, min-h-[190px]; panel-line/40.
        constraints: const BoxConstraints(minHeight: 190),
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(13)), // white/5
          color: th.bgSurface.withAlpha(102), // /[0.40]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.film, size: 26, color: th.textMuted.withAlpha(153)),
            const SizedBox(height: 8), // mb-2
            Text(
              t.tr('detail.trailerNotFound'),
              style: TextStyle(fontSize: 14, color: th.textMuted),
            ),
          ],
        ),
      );
    }

    final thumbnail =
        'https://img.youtube.com/vi/${Uri.encodeComponent(videoId)}/hqdefault.jpg';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(26)), // white/10
        color: Colors.black.withAlpha(153), // bg-black/60
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9, // aspect-video
        child: Stack(
          fit: StackFit.expand,
          children: [
            TsundokuImage(
              imageUrl: thumbnail,
              fit: BoxFit.cover,
              errorWidget: Container(color: Colors.black),
            ),
            // group-hover:bg-black/25 → /40.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: Colors.black.withAlpha(_hovered ? 102 : 64),
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: () {
                  // Svelte embeds iframe(autoplay); Flutter без webview в
                  // стеке — открыть embed-URL внешне (решение #48).
                  unawaited(platformService.openExternalUrl(
                          'https://www.youtube-nocookie.com/embed/${Uri.encodeComponent(videoId)}?autoplay=1'));
                },
                child: Center(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: _hovered ? 1.03 : 1.0,
                    child: Container(
                      width: 56, // size-14
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16), // rounded-2xl
                        color: _hovered
                            ? const Color(0xE6EF4444) // hover:bg-red-500/90
                            : const Color(0xE6DC2626), // bg-red-600/90
                        boxShadow: const [
                          // shadow-xl (сокращённо: 0 20px 25px -5px /30)
                          BoxShadow(
                            color: Color(0x4D000000),
                            offset: Offset(0, 20),
                            blurRadius: 25,
                            spreadRadius: -5,
                          ),
                        ],
                      ),
                      child: const Icon(LucideIcons.play,
                          size: 25, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12, // bottom-3 left-3
              bottom: 12,
              child: Text(
                t.tr('detail.trailerTitle'),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
