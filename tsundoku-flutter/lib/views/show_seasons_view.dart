/// 1:1 port of `mediatracker-ui/src/views/ShowSeasonsView.svelte`.
///
/// Вью сезонов tvshow: back-кнопка, скелетон загрузки (title-планка +
/// 3 панели), error-box с retry, header-карточка сериала (постер 80×112,
/// accent-сабтайтл, счётчик эпизодов/сезонов) и список SeasonRow.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/api/api.dart';
import '../shared/i18n/index.dart';
import '../shared/types/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/theme/tsundoku_theme.dart';
import '../shared/ui/tsundoku_image.dart';
import '../widgets/media-detail/season_row.dart';

/// rose-200 (Tailwind-литерал вне ThemeExtension).
const Color _rose200 = Color(0xFFFECDD3);

class ShowSeasonsView extends ConsumerStatefulWidget {
  final String mediaId;
  final int refreshKey;
  final VoidCallback onBack;
  final VoidCallback onMediaChanged;

  const ShowSeasonsView({
    super.key,
    required this.mediaId,
    required this.refreshKey,
    required this.onBack,
    required this.onMediaChanged,
  });

  @override
  ConsumerState<ShowSeasonsView> createState() => _ShowSeasonsViewState();
}

class _ShowSeasonsViewState extends ConsumerState<ShowSeasonsView> {
  TvShowDetail? _show;
  bool _loading = true;
  Object? _loadError;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    // $effect: первый loadShow.
    unawaited(_loadShow(++_requestSequence));
  }

  @override
  void didUpdateWidget(covariant ShowSeasonsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect(refreshKey, mediaId): ремоунт-логика Svelte перезагружает
    // при изменении refreshKey/mediaId.
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.mediaId != widget.mediaId) {
      unawaited(_loadShow(++_requestSequence));
    }
  }

  Future<void> _loadShow(int sequence) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final media = await ref.read(apiClientProvider).getMediaItem(widget.mediaId);
      if (!isTvShowDetail(media)) {
        throw StateError('Media item is not a TV show');
      }

      if (sequence == _requestSequence && mounted) {
        setState(() => _show = TvShowDetail(media));
      }
    } catch (error) {
      if (sequence == _requestSequence && mounted) {
        setState(() => _loadError = error);
      }
    } finally {
      if (sequence == _requestSequence && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _retry() {
    unawaited(_loadShow(++_requestSequence));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      // mx-auto max-w-4xl.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 896),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // back-кнопка.
            _BackButton(t: t, th: th, onBack: widget.onBack),
            const SizedBox(height: 24), // space-y-6
            if (_loading)
              _Skeleton(th: th)
            else if (_loadError != null)
              _ErrorBox(t: t, th: th, error: _loadError!, onRetry: _retry)
            else if (_show != null) ...[
              _ShowHeaderCard(t: t, th: th, show: _show!),
              const SizedBox(height: 24),
              _SeasonsSection(
                t: t,
                th: th,
                show: _show!,
                onProgress: ref.read(apiClientProvider).setSeasonProgress,
                onMediaChanged: widget.onMediaChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// TvShowDetail-обёртка: MediaDetail tvshow с непустым seasons.
class TvShowDetail {
  final MediaDetail media;

  const TvShowDetail(this.media);

  String get title => media.title;
  String? get coverUrl => media.coverUrl;
  int? get totalEpisodesWatched => media.totalEpisodesWatched;
  int? get totalEpisodesCount => media.totalEpisodesCount;
  int? get seasonsCount => media.seasonsCount;
  List<TvSeason> get seasons => media.seasons ?? const <TvSeason>[];
}

class _BackButton extends ConsumerStatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final VoidCallback onBack;

  const _BackButton(
      {required this.t, required this.th, required this.onBack});

  @override
  ConsumerState<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends ConsumerState<_BackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onBack,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowLeft,
                size: 16, color: th.textSecondary), // text-muted
            const SizedBox(width: 8), // gap-2
            Text(
              widget.t.tr('common.back'),
              style: TextStyle(
                fontSize: 14, // text-sm
                fontWeight: FontWeight.w600, // font-semibold
                color: _hovered ? th.textPrimary : th.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final TsundokuTheme th;

  const _Skeleton({required this.th});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 256, // w-64
          height: 28, // h-7
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4), // rounded
            color: th.bgCard, // bg-card
          ),
        ),
        const SizedBox(height: 16), // space-y-4
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 128, // h-32
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-lg
              color: th.bgCard,
            ),
          ),
          if (i < 2) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ErrorBox extends ConsumerStatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final Object error;
  final VoidCallback onRetry;

  const _ErrorBox(
      {required this.t, required this.th, required this.error, required this.onRetry});

  @override
  ConsumerState<_ErrorBox> createState() => _ErrorBoxState();
}

class _ErrorBoxState extends ConsumerState<_ErrorBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    final t = widget.t;
    return Container(
      constraints: const BoxConstraints(minHeight: 288), // min-h-72
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-lg
        color: const Color(0x0DFB7185), // bg-rose-400/5
      ),
      padding: const EdgeInsets.all(24), // p-6
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            errorMessage(widget.error, t.locale),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _rose200), // rose-200
          ),
          const SizedBox(height: 12), // gap-3
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8), // px-4 py-2
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // rounded-md
                  color: _hovered ? th.accentHover : th.accent,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 15, color: Colors.white),
                    const SizedBox(width: 8), // gap-2
                    Text(
                      t.tr('common.retry'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowHeaderCard extends ConsumerWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final TvShowDetail show;

  const _ShowHeaderCard(
      {required this.t, required this.th, required this.show});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-lg
        color: th.bgSurface, // bg-surface
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20), // p-5
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Постер 80×112 (h-28 w-20).
            Container(
              width: 80,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
                color: th.bgCard, // bg-card
              ),
              clipBehavior: Clip.antiAlias,
              child: show.coverUrl != null
                  ? TsundokuImage(
                      src: show.coverUrl,
                      fit: BoxFit.cover,
                      semanticLabel: show.title, // alt
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    )
                  : null,
            ),
            const SizedBox(width: 16), // gap-4
            // min-w-0 self-center.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.tr('navigation.tvshow'),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: th.accentSoft, // text-accent-soft
                      letterSpacing: 0.16 * 12, // tracking-[0.16em]
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4), // mt-1
                    child: Text(
                      show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis, // truncate
                      style: TextStyle(
                        fontSize: 20, // text-xl
                        fontWeight: FontWeight.w700, // font-bold
                        color: th.textPrimary, // text-ink
                        letterSpacing: -0.5, // tracking-tight
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8), // mt-2
                    child: Text(
                      '${show.totalEpisodesWatched} / ${show.totalEpisodesCount} · ${show.seasonsCount}',
                      style: TextStyle(
                        fontSize: 14, // text-sm
                        color: th.textMuted, // text-muted
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonsSection extends StatelessWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final TvShowDetail show;
  final Future<void> Function(String id, int currentEpisode) onProgress;
  final VoidCallback onMediaChanged;

  const _SeasonsSection({
    required this.t,
    required this.th,
    required this.show,
    required this.onProgress,
    required this.onMediaChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.tf('views.seasonsOf', [show.title]),
          style: const TextStyle(
            fontSize: 18, // text-lg
            fontWeight: FontWeight.w700, // font-bold
            letterSpacing: 0.025 * 18, // tracking-wide
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12), // space-y-3
        if (show.seasons.isEmpty)
          Container(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-lg
              color: th.bgSurface, // bg-surface
            ),
            padding: const EdgeInsets.all(32), // p-8
            child: Text(
              t.tr('views.noSeasons'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: th.textMuted), // text-sm
            ),
          )
        else
          ...[
            for (var i = 0; i < show.seasons.length; i++) ...[
              SeasonRow(
                key: ValueKey(show.seasons[i].id),
                season: show.seasons[i],
                onProgress: onProgress,
                onProgressCommitted: onMediaChanged,
              ),
              if (i < show.seasons.length - 1) const SizedBox(height: 12),
            ],
          ],
      ],
    );
  }
}
