/// 1:1 port of `mediatracker-ui/src/widgets/media-card/BaseCard.svelte`.
///
/// Каркас карточки: MediaPoster (бейджи статуса/оценки + hover-кнопка
/// удаления), градиент-оверлей с пассивным слоем (timeHint + children) и
/// hover-слоем (stepper), правый клик → контекст-меню (edit/status/списки/
/// буфер/постер/источник/удаление hold-to-delete), hover → префетч детали,
/// Enter/Space → onOpen, deleteError-alert.
///
/// Браузерные замены: navigator.clipboard → PlatformService (решение #32);
/// window.open → openExternalUrl; document-anchor download → saveFile;
/// revealInExplorer — серверный API (кроссплатформенно). data-id-атрибут —
/// DOM-специфика, не переносился. Selection-guard контекст-меню не нужен:
/// текст в карточках не выделяется.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart' show Options, ResponseType;
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/cover_url.dart';
import '../../entities/media/ui/media_poster.dart';
import '../../entities/media/ui/media_score_badge.dart';
import '../../entities/media/ui/media_status_badge.dart';
import '../../features/change-status/status_controller.dart';
import '../../features/prefetch-details/media_detail_prefetch.dart';
import '../media-detail/detail_formatters.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/platform/platform.dart';
import '../../shared/theme/tsundoku_theme.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import '../../shared/ui/context_menu_controller.dart';
import '../../shared/ui/toast.dart';
import 'card_types.dart';

/// Прозрачная часть буфера обмена webp/jpeg: PNG-подпись передаётся как есть
/// (1-в-1 с TS-проверкой blob.type), остальное перекодируется через dart:ui.
const _pngSignature = <int>[0x89, 0x50, 0x4E, 0x47];

class BaseCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  /// Rendered below the poster: title, progress, type-specific controls.
  final Widget children;

  /// Hover layer swapped in over [children] (stepper / quick actions).
  final Widget? hover;

  const BaseCard({
    super.key,
    required this.props,
    required this.children,
    this.hover,
  });

  @override
  ConsumerState<BaseCard> createState() => _BaseCardState();
}

class _BaseCardState extends ConsumerState<BaseCard> {
  /// A failed delete surfaces as an alert overlay (role="alert").
  Object? _deleteError;

  /// group-hover/focus-within: passive info → hover layer swap.
  bool _hovered = false;
  bool _focused = false;

  bool get _hoverActive => _hovered || _focused;

  CardStatusState _buildStatus() {
    final props = widget.props;
    // ref-контроллеров — ProviderContainer (решение #34): из виджета Ref
    // недоступен, container.read эквивалентен и живёт столько же, сколько
    // приложение.
    return createCardStatus(CardStatusOptions(
      getItem: () => props.item,
      getOnStatusChange: () => props.onStatusChange,
      getOnProgressCommitted: () => props.onProgressCommitted ?? () {},
      ref: ProviderScope.containerOf(context),
    ));
  }

  void _handleKeydown(KeyEvent event) {
    // if (event.target !== event.currentTarget) return; — вложенные фокусируемые
    // узлы отсутствуют, guard не нужен.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.props.onOpen?.call(widget.props.item);
    }
  }

  List<MenuItem> _buildCardMenuItems(MediaItem item) {
    final t = ref.read(tProvider);
    final sourceLink = providerLink(item);
    final posterDataPath = _localAssetDataPath(item.coverUrl);

    return [
      MenuItem(
        id: 'edit',
        label: t.tr('detailModal.edit'),
        icon: 'edit',
        action: () => widget.props.onEdit != null
            ? widget.props.onEdit!(item)
            : widget.props.onOpen?.call(item),
      ),
      MenuItem(
        id: 'status',
        label: t.tr('status.label'),
        icon: 'status',
        children: [
          for (final status in const <MediaStatus>[
            MediaStatus.planned, // 1-в-1: onHold в меню отсутствует
            MediaStatus.inProgress,
            MediaStatus.completed,
            MediaStatus.dropped,
          ])
            MenuItem(
              id: 'status-${status.name}',
              label: statusLabel(status, t),
              action: () => widget.props.onStatusChange?.call(item, status),
            ),
        ],
      ),
      MenuItem(
        id: 'add-to-list',
        label: t.tr('views.listAddTo'),
        icon: 'list',
        action: () => openListPicker(ref, item.id),
      ),
      MenuItem(
        id: 'copy-title',
        label: t.tr('contextMenu.copyTitle'), // ?? common.copy — ключ есть
        icon: 'copy',
        action: () async {
          try {
            await platformService.copyText(item.title);
          } catch (_) {
            // navigator.clipboard.writeText(...).catch(() => {})
          }
          showToast(
            ref,
            ToastOptions(
              title: t.tr('common.copied'),
              description: t.tr('toast.descCopied'),
            ),
          );
        },
      ),
      const MenuItem(id: 'separator-poster', kind: 'separator'),
      if (posterDataPath != null)
        MenuItem(
          id: 'reveal-poster',
          label: t.tr('contextMenu.revealPoster'),
          icon: 'image',
          action: () => unawaited(_revealInExplorer(posterDataPath)),
        ),
      if (item.coverUrl != null) ...[
        MenuItem(
          id: 'save-poster',
          label: t.tr('contextMenu.savePosterAs'),
          icon: 'download',
          action: _savePosterAs,
        ),
        MenuItem(
          id: 'copy-image',
          label: t.tr('contextMenu.copyImage'),
          icon: 'copy',
          action: () => unawaited(_copyPosterToClipboard()),
        ),
        MenuItem(
          id: 'copy-cover-url',
          label: t.tr('contextMenu.copyCoverUrl'),
          icon: 'link',
          action: () async {
            try {
              await platformService
                  .copyText(_absoluteCoverUrl(item.coverUrl));
            } catch (_) {}
            showToast(
              ref,
              ToastOptions(
                title: t.tr('common.copied'),
                description: t.tr('toast.descCopied'),
              ),
            );
          },
        ),
      ],
      if (sourceLink != null)
        MenuItem(
          id: 'open-on-source',
          label: t.tf('contextMenu.openOnSource', [sourceLink.name]),
          icon: 'browser',
          action: () =>
              unawaited(platformService.openExternalUrl(sourceLink.url)),
        ),
      MenuItem(
        id: 'open-title-folder',
        label: t.tr('contextMenu.openTitleFolder'),
        icon: 'folder',
        action: () => unawaited(_revealInExplorer('media/${item.id}')),
      ),
      const MenuItem(id: 'separator1', kind: 'separator'),
      MenuItem(
        id: 'delete',
        label: t.tr('detailModal.delete'),
        icon: 'delete',
        kind: 'danger',
        holdToDelete: true,
        // The menu item's 1-second hold is the confirmation; no modal here.
        action: () async {
          final onDelete = widget.props.onDelete;
          if (onDelete == null) return;
          try {
            await onDelete(item);
          } catch (error) {
            setState(() => _deleteError = error);
          }
        },
      ),
    ];
  }

  /// Data-directory-relative path behind a locally served asset URL; null for
  /// external hosts.
  String? _localAssetDataPath(String? url) {
    if (url == null ||
        url.startsWith('http://') ||
        url.startsWith('https://')) {
      return null;
    }
    final clean = url.split('?').first.split('#').first.replaceFirst('/', '');
    if (clean.startsWith('media-assets/')) {
      return 'media/${clean.substring('media-assets/'.length)}';
    }
    if (clean.startsWith('covers/')) return clean;
    return null;
  }

  /// The card shows a thumbnail; downloads and clipboard want the original
  /// variant.
  String? _fullSizeCoverUrl(String? url) {
    if (url == null) return null;
    return url.replaceFirst(RegExp(r'thumb\.webp(\?.*)?$'), 'original.webp');
  }

  String _absoluteCoverUrl(String? url) {
    if (url == null) return '';
    // new URL(url, window.location.origin) → склейка с baseUrl.
    return ref.read(apiClientProvider).absoluteUrl(url);
  }

  /// Asks the server to reveal a data-relative path in the OS file manager.
  Future<void> _revealInExplorer(String dataPath) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref.read(apiClientProvider).revealInExplorer(dataPath);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('contextMenu.revealed'),
          description: t.tr('toast.descRevealed'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  Future<void> _savePosterAs() async {
    final url = _fullSizeCoverUrl(widget.props.item.coverUrl) ??
        widget.props.item.coverUrl;
    if (url == null) return;
    final api = ref.read(apiClientProvider);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      // TS: браузер качал по URL с referrerPolicy=no-referrer; здесь dio.
      final response = await api.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      await platformService.saveFile(
        suggestedName: 'cover.webp',
        bytes: bytes,
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  Future<void> _copyPosterToClipboard() async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    final url = _fullSizeCoverUrl(widget.props.item.coverUrl) ??
        widget.props.item.coverUrl;
    if (url == null) return;
    final api = ref.read(apiClientProvider);
    try {
      final response = await api.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      var bytes = Uint8List.fromList(response.data ?? const <int>[]);
      // The clipboard spec only guarantees image/png; transcode webp/jpeg
      // sources (PNG-подпись → passthrough, 1-в-1 с проверкой blob.type).
      if (!_isPng(bytes)) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) {
          throw const FormatException('PNG transcode failed');
        }
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      await platformService.copyImagePng(bytes);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('common.copied'),
          description: t.tr('toast.descCopied'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  void _schedulePrefetch() {
    final item = widget.props.item;
    // onpointerenter/onfocus → schedulePrefetchMediaDetail(item.id).
    ref.read(hoverPrefetchSchedulerProvider).schedule(item.id, (id) {
      prefetchMediaDetail(
        ref.read(mediaDetailCacheProvider),
        ref.read(apiClientProvider),
        id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final item = props.item;
    final th = TsundokuTheme.of(context);
    final status = _buildStatus();

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        _schedulePrefetch();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          _handleKeydown(event);
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => props.onOpen?.call(item),
          onSecondaryTapUp: (details) {
            openContextMenu(
              ref,
              details.globalPosition.dx,
              details.globalPosition.dy,
              _buildCardMenuItems(item),
            );
          },
          child: AspectRatio(
            aspectRatio: 2 / 3, // aspect-[2/3]
            child: Container(
              clipBehavior: Clip.antiAlias, // overflow-hidden
              decoration: BoxDecoration(
                color: th.bgCanvas, // bg-canvas
                borderRadius:
                    BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
                border: Border.all(
                  // border-white/5 → hover:border-white/10
                  color: _hovered
                      ? Colors.white.withAlpha(26)
                      : Colors.white.withAlpha(13),
                ),
                boxShadow: [
                  if (_focused)
                    const BoxShadow(
                      color: Color(0x4D6366F1), // focus-within:ring-2 ring-indigo-500/30
                      spreadRadius: 2,
                    ),
                  // shadow-lg: 0 10px 15px -3px rgb(0 0 0/0.1),
                  //            0 4px 6px -4px rgb(0 0 0/0.1)
                  const BoxShadow(
                    color: Color(0x1A000000),
                    offset: Offset(0, 10),
                    blurRadius: 15,
                    spreadRadius: -3,
                  ),
                  const BoxShadow(
                    color: Color(0x1A000000),
                    offset: Offset(0, 4),
                    blurRadius: 6,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaPoster(
                    src: item.coverUrl != null
                        ? proxiedExternalCoverUrl(item.coverUrl!)
                        : null,
                    alt: item.title,
                    syncing: item.syncStatus == SyncStatus.syncing,
                    needsReview: item.syncStatus == SyncStatus.needsReview,
                    badges: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MediaStatusBadge(
                          id: 'status-${item.id}',
                          status: item.status,
                          onSelect: (next) => unawaited(status.changeStatus(next)),
                        ),
                        MediaScoreBadge(score: item.score),
                      ],
                    ),
                  ),

                  // Градиент-оверлей: пассивный слой + hover-слой.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      // px-3 pt-16 pb-2 (shifted down slightly vs pb-3); bg-gradient-to-t 3-stop.
                      padding: const EdgeInsets.fromLTRB(12, 64, 12, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          stops: [0.0, 0.5, 1.0],
                          colors: [
                            Color(0xF20D0F14), // from-[#0d0f14]/95
                            Color(0x990D0F14), // via-[#0d0f14]/60
                            Color(0x000D0F14), // to-transparent
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Пассивная информация: title и author only.
                          AnimatedOpacity(
                            opacity: _hoverActive ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (props.timeHint != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8), // pb-2
                                    child: _TimeHintChip(hint: props.timeHint!),
                                  ),
                                widget.children,
                              ],
                            ),
                          ),
                          // Hover-слой (stepper / quick actions).
                          if (widget.hover != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                ignoring: !_hoverActive,
                                // group-hover:pointer-events-auto
                                child: AnimatedOpacity(
                                  opacity: _hoverActive ? 1 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: widget.hover,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // deleteError alert (role="alert").
                  if (_deleteError != null)
                    Positioned(
                      left: 8, // inset-x-2
                      right: 8,
                      top: 48, // top-12
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4), // px-2 py-1
                        decoration: BoxDecoration(
                          color: const Color(0xE64C0526), // bg-rose-950/90
                          borderRadius: BorderRadius.circular(6), // rounded-md
                        ),
                        child: Text(
                          errorMessage(_deleteError!, ref.watch(i18nProvider)),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            height: 16 / 12, // leading-4
                            color: Color(0xFFFECDD3), // text-rose-200
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isPng(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// timeHint-чип: emerald (canFinishNow) или accent (обычный).
class _TimeHintChip extends ConsumerWidget {
  final CardTimeHint hint;

  const _TimeHintChip({required this.hint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = TsundokuTheme.of(context);
    final canFinish = hint.canFinishNow;

    return Tooltip(
      message: hint.label, // title={timeHint.label}
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // px-2 py-0.5
        constraints: const BoxConstraints(maxWidth: double.infinity),
        decoration: BoxDecoration(
          color: canFinish
              ? const Color(0x3310B981) // bg-emerald-500/20
              : th.accent.withAlpha(51), // bg-accent/20
          borderRadius: BorderRadius.circular(6), // rounded-md
          border: Border.all(
            color: canFinish
                ? const Color(0x6634D399) // border-emerald-400/40
                : th.accent.withAlpha(77), // border-accent/30
          ),
        ),
        child: Text(
          hint.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis, // truncate
          style: TextStyle(
            fontSize: 11, // text-[11px]
            fontWeight: canFinish ? FontWeight.w600 : FontWeight.w500,
            color: canFinish
                ? const Color(0xFF6EE7B7) // text-emerald-300
                : th.accentSoft, // text-accent-soft
          ),
        ),
      ),
    );
  }
}
