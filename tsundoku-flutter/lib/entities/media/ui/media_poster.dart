/// 1:1 port of `mediatracker-ui/src/entities/media/ui/MediaPoster.svelte`.
///
/// Постер: фон canvas, server-relative обложка (`src.startsWith('/')`) через
/// Image.network с error-fallback на [Placeholder404] (onerror — не retry-loop),
/// syncing-оверлей (спиннер + activity.syncing), needsReview-кнопка
/// (bg-amber-500/90, открывает BackgroundJobsModal на review-табе), слоты
/// badges/actions в верхних углах.
///
/// Svelte-проп `children` объявлен, но никогда не рендерится в шаблоне —
/// мёртвый API, в Dart не переносился (YAGNI).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/api/jobs_client.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import 'placeholder404.dart';

class MediaPoster extends ConsumerStatefulWidget {
  final String? src;
  final String alt;

  /// Status + score cluster, rendered inside the poster's top-left corner.
  final Widget? badges;

  /// Destructive/secondary actions, rendered top-right and revealed on hover.
  final Widget? actions;

  /// Background enrichment is still filling this item in. The card stays
  /// clickable.
  final bool syncing;

  /// The matcher parked this title for manual confirmation; the badge opens
  /// the review tab.
  final bool needsReview;

  const MediaPoster({
    super.key,
    required this.src,
    required this.alt,
    this.badges,
    this.actions,
    this.syncing = false,
    this.needsReview = false,
  });

  @override
  ConsumerState<MediaPoster> createState() => _MediaPosterState();
}

class _MediaPosterState extends ConsumerState<MediaPoster> {
  /// A broken remote/проксирующий link is a "cover not found" case, not a
  /// retry loop forever.
  bool _imgError = false;

  @override
  void didUpdateWidget(MediaPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset on a new src: another sync may have repaired the cover ($effect).
    if (oldWidget.src != widget.src) {
      _imgError = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    // <img src="/..."> в браузере резолвится от origin сервера; в Dart
    // склейка с baseUrl — 1-в-1 с TsundokuApi.absoluteUrl.
    final baseUrl = ref.watch(apiBaseUrlProvider);

    final src = widget.src;
    // Внешние URL приходят уже проксированными (proxiedExternalCoverUrl),
    // поэтому ветка else — Placeholder404, как в Svelte.
    final showImage = src != null && src.startsWith('/') && !_imgError;

    return Stack(
      fit: StackFit.expand,
      children: [
        // bg-canvas
        ColoredBox(color: TsundokuTheme.of(context).bgCanvas),
        if (showImage)
          Image.network(
            '$baseUrl$src',
            fit: BoxFit.cover, // object-cover
            semanticLabel: widget.alt, // alt
            errorBuilder: (context, error, stackTrace) {
              // onerror: пометить сломанной и показать плейсхолдер.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_imgError) {
                  setState(() => _imgError = true);
                }
              });
              return const SizedBox.expand();
            },
          )
        else
          const Placeholder404(),

        // syncing-оверлей
        if (widget.syncing)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xCC000000), // bg-black/80
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 22, // LoaderCircle size={22}
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xE6FFFFFF), // text-white/90
                    ),
                  ),
                  const SizedBox(height: 8), // gap-2
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2), // px-2 py-0.5
                    decoration: BoxDecoration(
                      color: const Color(0x99000000), // bg-black/60
                      borderRadius: BorderRadius.circular(999), // rounded-full
                    ),
                    child: Text(
                      t.tr('activity.syncing'),
                      style: const TextStyle(
                        fontSize: 10, // text-[10px]
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: 0.25, // tracking-wide @ 10px
                        color: Color(0xE6FFFFFF), // text-white/90
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // needsReview-кнопка
        if (widget.needsReview)
          Positioned(
            left: 10, // inset-x-2.5
            right: 10,
            bottom: 10, // bottom-2.5
            child: _NeedsReviewButton(onPressed: () {
              ref
                  .read(jobsClientProvider.notifier)
                  .openModal(JobsModalTab.review);
            }),
          ),

        // Верхняя полоса: badges слева, actions справа (z-10, p-2.5)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.all(10), // p-2.5
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // relative flex items-center (кластер бейджей)
                if (widget.badges != null)
                  Align(
                    alignment: Alignment.topLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [widget.badges!],
                    ),
                  ),
                const Spacer(),
                if (widget.actions != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [widget.actions!], // flex items-center gap-1.5
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `bg-amber-500/90 … hover:bg-amber-400` кнопка «Уточнить» с lucide
/// AlertTriangle 16px; click не всплывает в карточку (внутренний GestureDetector
/// выигрывает арену — Svelte stopPropagation эквивалентен).
class _NeedsReviewButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _NeedsReviewButton({required this.onPressed});

  @override
  State<_NeedsReviewButton> createState() => _NeedsReviewButtonState();
}

class _NeedsReviewButtonState extends State<_NeedsReviewButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final label = ref.watch(tProvider).tr('backgroundJobs.refineBadge');
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // px-2.5 py-1
            decoration: BoxDecoration(
              // bg-amber-500/90; hover:bg-amber-400 (без альфы)
              color: _hovered
                  ? const Color(0xFFFBBF24)
                  : const Color(0xE6F59E0B),
              borderRadius: BorderRadius.circular(6), // rounded-md
              boxShadow: const [
                // shadow-lg
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 10),
                  blurRadius: 15,
                  spreadRadius: -3,
                ),
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 4),
                  blurRadius: 6,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.triangleAlert, // AlertTriangle
                  size: 16,
                  color: Colors.black,
                ),
                const SizedBox(width: 4), // gap-1
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11, // text-[11px]
                      fontWeight: FontWeight.w700, // font-bold
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
