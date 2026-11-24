/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/DetailSidebar.svelte`.
///
/// Сайдбар детальной страницы: постер (hover → CoverManagerModal), статус +
/// рейтинг (поповер с критериями), drop-причина, сохранённая детальная
/// оценка, «Ваша история» (voice/platform-комбо), «Действия» (удаление с
/// hold-to-delete), «Характеристики» (alt-тайтлы/жанры/spec-строки).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/cover_url.dart';
import '../../entities/media/model/detailed_score.dart';
import '../../entities/media/model/drop_reasons.dart';
import '../../entities/media/model/genre_label.dart';
import '../../entities/media/model/media_labels.dart';
import '../../features/drop-reason/drop_reason_prompt.dart';
import '../../features/lists/create_list_modal.dart';
import '../../features/lists/list_picker.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_theme.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/badge.dart';
import '../../shared/ui/button.dart';
import '../../shared/ui/hold_to_delete.dart';
import '../../shared/ui/lightbox.dart';
import '../../shared/ui/media_cover_placeholder.dart';
import '../../shared/ui/modal.dart';
import '../../shared/platform/platform.dart';
import '../../shared/ui/panel.dart';
import '../../shared/ui/text_field.dart';
import '../../shared/ui/tsundoku_image.dart';
import '../../shared/ui/popover_menu.dart';
import '../../shared/ui/toast.dart';
import '../../shared/utils/ui_settings.dart';
import 'cover_manager_modal.dart';
import 'detail_types.dart';
import 'media_activity_modal.dart';

// Tailwind-литералы (вне ThemeExtension).
const Color _kPanelRaised = Color(0xFF1A1E28); // --color-panel-raised
const Color _kInfoSoft = Color(0xFF7DD3FC); // --color-info-soft
const Color _kSuccessLine = Color(0xFF34D399); // --color-success-line
const Color _kAccentSoft = Color(0xFFA5B4FC); // --color-accent-soft
const Color _kTrackFaint = Color(0xFF161A22); // --color-track-faint
const Color _kAmber300 = Color(0xFFFCD34D);
const Color _kAmber400 = Color(0xFFFBBF24);
const Color _kAmber500 = Color(0xFFF59E0B);
const Color _kRose300 = Color(0xFFFDA4AF);
const Color _kRose400 = Color(0xFFFB7185);
const Color _kRose500 = Color(0xFFF43F5E);
const Color _kSlate200 = Color(0xFFE2E8F0);
const Color _kSlate300 = Color(0xFFCBD5E1);
const Color _kZinc400 = Color(0xFFA1A1AA);

/// Rare actions behind the compact "…" menu.
enum _MoreAction { covers, lists, relink, activity }

/// Сайдбар (1-в-1 с DetailSidebar.svelte).
class DetailSidebar extends ConsumerStatefulWidget {
  final MediaDetail media;
  final List<MediaStatus> statusOptions;
  final bool statusBusy;
  final Future<void> Function(MediaStatus status) onChangeStatus;
  final Object? statusError;
  final int? scoreValue;
  final bool ratingOpen;
  final VoidCallback onRatingOpen;
  final VoidCallback onRatingClose;
  final VoidCallback onRatingHide;
  final Future<void> Function(int score) onSetScore;
  final VoidCallback onClearScore;
  final Future<void> Function(String? detailedJson, [int? newScore])?
      onSaveDetailedScore;
  final String Function(String? value) formatDate;
  final String watchedOnInput;
  final void Function(String value) onWatchedOnInput;
  final VoidCallback onWatchedOnDirty;
  final Future<void> Function() onSaveWatchedOn;
  final List<String> platformOptions;
  final Future<void> Function(String platform) onSelectPlatform;
  final bool refreshBusy;
  final String? syncStep;
  final Object? refreshError;
  final Future<void> Function() onRefreshMetadata;
  final bool fillMissingBusy;
  final VoidCallback onFillMissing;
  final VoidCallback onRelink;
  final VoidCallback onStartEdit;
  final bool deleteBusy;
  final Object? deleteError;
  final Future<void> Function() onDelete;

  final List<SpecRow> specRows;

  /// Фоновое обогащение идёт: ждёт только постер.
  final bool syncing;

  /// Свежая строка после one-click авто-проверки / мутаций.
  final void Function(MediaDetail media)? onAutoRefreshed;
  final void Function(MediaDetail media)? onMediaUpdated;

  const DetailSidebar({
    super.key,
    required this.media,
    required this.statusOptions,
    required this.statusBusy,
    required this.onChangeStatus,
    required this.statusError,
    required this.scoreValue,
    required this.ratingOpen,
    required this.onRatingOpen,
    required this.onRatingClose,
    required this.onRatingHide,
    required this.onSetScore,
    required this.onClearScore,
    this.onSaveDetailedScore,
    required this.formatDate,
    required this.watchedOnInput,
    required this.onWatchedOnInput,
    required this.onWatchedOnDirty,
    required this.onSaveWatchedOn,
    this.syncStep,
    required this.platformOptions,
    required this.onSelectPlatform,
    required this.refreshBusy,
    required this.refreshError,
    required this.onRefreshMetadata,
    required this.fillMissingBusy,
    required this.onFillMissing,
    required this.onRelink,
    required this.onStartEdit,
    required this.deleteBusy,
    required this.deleteError,
    required this.onDelete,
    required this.specRows,
    this.syncing = false,
    this.onAutoRefreshed,
    this.onMediaUpdated,
  });

  @override
  ConsumerState<DetailSidebar> createState() => _DetailSidebarState();
}

class _DetailSidebarState extends ConsumerState<DetailSidebar> {
  bool _isCoverManagerOpen = false;
  bool _isActivityOpen = false;
  bool _isListPickerOpen = false;
  bool _isCreateListOpen = false;
  final GlobalKey<ListPickerState> _listPickerKey = GlobalKey<ListPickerState>();
  bool _detailedExpanded = false;
  DetailedScoreMap _detailedDraft = <String, int>{};
  String? _lastMediaJson;
  bool _imgError = false;
  bool _showAllAltTitles = false;
  bool _showAllGenres = false;
  bool _autoRefreshBusy = false;

  /// rating-pop: absolute z-30 в браузере рисует поповер над всеми
  /// следующими секциями колонки; локальный Positioned рисуется под
  /// нижележащими панелями и не получает тапы → top-layer аналог
  /// (OverlayPortal + LayerLink), как у нативного PopoverMenu.
  final LayerLink _ratingLink = LayerLink();
  final OverlayPortalController _ratingPortal = OverlayPortalController();

  late HoldToDeleteController _deleteHold;

  @override
  void initState() {
    super.initState();
    _deleteHold = createHoldToDelete(
      HoldToDeleteOptions(
        onComplete: () => unawaited(widget.onDelete()),
        isEnabled: () => !widget.deleteBusy,
      ),
    );
    // $effect при монтировании: draft из текущего json.
    _lastMediaJson = widget.media.detailedScoreJson;
    _detailedDraft = parseDetailedScore(widget.media.detailedScoreJson);
    // Изначально открытый поповер — показать после первого кадра.
    if (widget.ratingOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.ratingOpen && !_ratingPortal.isShowing) {
          _ratingPortal.show();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant DetailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect: смена coverUrl → сброс imgError.
    if (oldWidget.media.coverUrl != widget.media.coverUrl) {
      _imgError = false;
    }
    // $effect: смена detailedScoreJson → пересборка draft.
    if (widget.media.detailedScoreJson != _lastMediaJson) {
      _lastMediaJson = widget.media.detailedScoreJson;
      _detailedDraft = parseDetailedScore(widget.media.detailedScoreJson);
    }
    // ratingOpen → show/hide top-layer портала. show/hide во время build
    // запрещены — пост-кадр.
    if (widget.ratingOpen != oldWidget.ratingOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.ratingOpen && !_ratingPortal.isShowing) {
          _ratingPortal.show();
        } else if (!widget.ratingOpen && _ratingPortal.isShowing) {
          _ratingPortal.hide();
        }
      });
    }
  }

  @override
  void dispose() {
    _deleteHold.dispose();
    super.dispose();
  }

  // splitAltTitles: blob-split, дедуп ci, без display-тайтла.
  List<String> get _splitAltTitles {
    final seen = <String>{};
    final titleKey = widget.media.title.trim().toLowerCase();
    final result = <String>[];
    for (final raw in widget.media.altTitles ?? const <String>[]) {
      for (final part in raw.split(RegExp(r'\s*[/,]\s*'))) {
        final value = part.trim();
        final key = value.toLowerCase();
        if (value.isEmpty || key == titleKey || seen.contains(key)) continue;
        seen.add(key);
        result.add(value);
      }
    }
    return result;
  }

  List<SpecRow> get _filteredSpecRows {
    final t = ref.read(tProvider);
    final altTitles = _splitAltTitles;
    return widget.specRows.where((row) {
      if (row.label == t.tr('detail.genresLabel')) return false;
      if (row.label != t.tr('detail.romajiTitle')) return true;
      final value = row.value.trim().toLowerCase();
      if (value.isEmpty || value == widget.media.title.trim().toLowerCase()) {
        return false;
      }
      return !altTitles.any((alt) => alt.toLowerCase() == value);
    }).toList();
  }

  List<String> get _genreChips {
    final seen = <String>{};
    final result = <String>[];
    for (final part in widget.media.genres ?? const <String>[]) {
      final value = part.trim();
      final key = value.toLowerCase();
      if (value.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      result.add(value);
    }
    return result;
  }

  List<CriterionAxis> get _axes => getCriteriaAxes(widget.media.type.wire);

  DetailedScoreMap get _savedDetailedMap =>
      parseDetailedScore(widget.media.detailedScoreJson);
  DetailedAverage? get _savedSummary =>
      computeDetailedAverage(_savedDetailedMap);
  DetailedAverage? get _draftSummary =>
      computeDetailedAverage(_detailedDraft);

  bool get _isRu => ref.read(i18nProvider).wire == 'ru';

  /// Чтение словаря вне build (для под-виджетов без Ref).
  I18nDictionary readT() => ref.read(tProvider);

  /// setState-обёртка для под-виджетов поповера рейтинга.
  void sidebarSetState(VoidCallback fn) => setState(fn);

  bool get _finishedRelease =>
      (widget.media.releaseStatus ?? '').toUpperCase() == 'FINISHED';

  /// Игры и книги не опрашиваются сервером; кнопка — только активным
  /// онгоингам.
  bool get _isOngoing =>
      widget.media.type != MediaType.game &&
      !_finishedRelease &&
      (widget.media.type == MediaType.manga ||
          widget.media.type == MediaType.tvshow ||
          widget.media.nextAutoRefreshAt != null);

  // Voice/reading combobox scope по типу.
  VoiceOptionScope? get _comboScope {
    final type = widget.media.type;
    if (type == MediaType.book) return VoiceOptionScope.read;
    if (type == MediaType.movie || type == MediaType.tvshow) {
      return VoiceOptionScope.watch;
    }
    return null;
  }

  bool get _isAnimeMedia => widget.media.isAnime == true;

  List<String> get _comboPresets {
    final scope = _comboScope;
    if (scope == VoiceOptionScope.read) {
      return ref.read(tProvider).tfl('detail.readingFormatPresets');
    }
    return ref
        .read(tProvider)
        .tfl('detail.voiceStudioPresets', [_isAnimeMedia]);
  }

  VoiceOptionMemory? get _comboMemory {
    final scope = _comboScope;
    if (scope == null) return null;
    return ref
        .read(uiSettingsProvider.notifier)
        .getVoiceOptions(scope);
  }

  List<String> get _comboOptions {
    final memory = _comboMemory;
    if (memory == null) return const <String>[];
    bool isFavorite(String value) => memory.favorites
        .any((v) => v.toLowerCase() == value.toLowerCase());
    final seen = <String>{};
    final merged = <String>[];
    for (final value in [..._comboPresets, ...memory.custom]) {
      final key = value.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      merged.add(value);
    }
    merged.sort((a, b) =>
        (isFavorite(b) ? 1 : 0) - (isFavorite(a) ? 1 : 0));
    return merged;
  }

  bool _comboIsFavorite(String value) => (_comboMemory?.favorites ?? const [])
      .any((v) => v.toLowerCase() == value.toLowerCase());

  void _toggleComboFavorite(String value) {
    final scope = _comboScope;
    if (scope == null) return;
    unawaited(
        ref.read(uiSettingsProvider.notifier).toggleVoiceFavorite(scope, value));
  }

  /// Save + remember: применённое значение остаётся навсегда и звёздится.
  void _commitComboValue(String value) {
    widget.onWatchedOnInput(value);
    final scope = _comboScope;
    if (scope != null) {
      unawaited(ref
          .read(uiSettingsProvider.notifier)
          .rememberVoiceOption(scope, value));
    }
    unawaited(widget.onSaveWatchedOn());
  }

  Future<void> _handleAutoRefresh() async {
    if (_autoRefreshBusy) return;
    setState(() => _autoRefreshBusy = true);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      final updated =
          await ref.read(apiClientProvider).triggerAutoRefresh(widget.media.id);
      widget.onAutoRefreshed?.call(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.autoRefreshDone'),
          description: t.tr('toast.descUpdated'),
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
    } finally {
      if (mounted) setState(() => _autoRefreshBusy = false);
    }
  }

  void _runMoreAction(_MoreAction value) {
    switch (value) {
      case _MoreAction.covers:
        setState(() => _isCoverManagerOpen = true);
      case _MoreAction.lists:
        setState(() => _isListPickerOpen = true);
      case _MoreAction.relink:
        widget.onRelink();
      case _MoreAction.activity:
        setState(() => _isActivityOpen = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final isRu = _isRu;

    // lg:w-80: боковая колонка 320px на desktop-ширинах.
    final isLg = MediaQuery.sizeOf(context).width >= 1024;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: isLg ? 320 : double.infinity, // lg:w-80
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPoster(t, th),
              const SizedBox(height: 24), // space-y-6
              _buildStatusRow(t, th),
              if (widget.statusError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    errorMessage(widget.statusError!, ref.read(i18nProvider)),
                    style: const TextStyle(
                        fontSize: 12, color: _kRose300), // text-xs rose-300
                  ),
                ),
              if (widget.media.status == MediaStatus.dropped) ...[
                const SizedBox(height: 16), // space-y-6
                _DropReasonPill(media: widget.media, isRu: isRu),
              ],
              if (_savedSummary != null) ...[
                const SizedBox(height: 24),
                _buildSavedDetailedCard(t, th),
              ],
              const SizedBox(height: 24),
              _buildHistoryPanel(t, th),
              const SizedBox(height: 24),
              _buildActionsPanel(t, th),
              const SizedBox(height: 24),
              _buildDetailsPanel(t, th),
            ],
          ),
        ),
        // Модалки sidebar'а: через OverlayPortal, чтобы перекрывать весь
        // viewport поверх узкой 320px-колонки и ScrollView.
        TsundokuOverlayModal(
          isOpen: _isActivityOpen,
          modal: MediaActivityModal(
            isOpen: true,
            mediaId: widget.media.id,
            title: widget.media.title,
            onClose: () => setState(() => _isActivityOpen = false),
          ),
        ),
        TsundokuOverlayModal(
          isOpen: _isListPickerOpen,
          modal: ListPicker(
            key: _listPickerKey,
            mediaId: widget.media.id,
            isOpen: _isListPickerOpen,
            onClose: () => setState(() => _isListPickerOpen = false),
            onCreateList: () => setState(() => _isCreateListOpen = true),
          ),
        ),
        TsundokuOverlayModal(
          isOpen: _isCreateListOpen,
          modal: CreateListModal(
            isOpen: true,
            onClose: () => setState(() => _isCreateListOpen = false),
            onSaved: () {
              setState(() => _isCreateListOpen = false);
              _listPickerKey.currentState?.refreshLists();
            },
          ),
        ),
        TsundokuOverlayModal(
          isOpen: _isCoverManagerOpen,
          modal: CoverManagerModal(
            isOpen: true,
            media: widget.media,
            onClose: () => setState(() => _isCoverManagerOpen = false),
            onUpdate: (updated) {
              widget.onAutoRefreshed?.call(updated);
              widget.onMediaUpdated?.call(updated);
            },
          ),
        ),
      ],
    );
  }

  // ---- Постер ----

  Widget _buildPoster(I18nDictionary t, TsundokuTheme th) {
    final media = widget.media;
    final showCover = media.coverUrl != null && !_imgError;

    Widget coverArea;
    if (widget.syncing && media.coverUrl == null) {
      coverArea = Container(
        color: Colors.white.withAlpha(10), // bg-white/[0.04]
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.image, size: 32, color: th.textMuted),
            const SizedBox(height: 8), // gap-2
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                t.tr('activity.loadingCover'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: th.textMuted), // text-muted text-xs
              ),
            ),
          ],
        ),
      );
    } else if (showCover) {
      coverArea = GestureDetector(
        onTap: () {
          final cover = media.coverUrl;
          if (cover != null) {
            ref
                .read(lightboxProvider.notifier)
                .openLightbox(
                    proxiedExternalCoverUrl(fullSizeCoverUrl(cover)),
                    media.title);
          }
        },
        child: TsundokuImage(
          src: media.coverUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter, // object-top
          semanticLabel: media.title, // alt
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_imgError) setState(() => _imgError = true);
            });
            return const SizedBox.expand();
          },
        ),
      );
    } else {
      coverArea = const MediaCoverPlaceholder();
    }

    return AspectRatio(
      aspectRatio: 2 / 3,
      child: _HoverBuilder(
        builder: (context, hovered) => Container(
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
            border: Border.all(
                color: Colors.white.withAlpha(15)), // border-white/[0.06]
            color: th.bgSurface, // bg-panel-line
            boxShadow: const [
              // shadow-lg
              BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 10),
                  blurRadius: 15,
                  spreadRadius: -3),
              BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 4),
                  blurRadius: 6,
                  spreadRadius: -4),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              coverArea,
              // Кнопка CoverManager: hover/focus reveal.
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity:
                      hovered || _imgError || media.coverUrl == null ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _HoverBuilder(
                    builder: (context, btnHovered) => GestureDetector(
                      onTap: () => setState(() => _isCoverManagerOpen = true),
                      child: Semantics(
                        button: true,
                        label: t.tr('coversModal.openCovers'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4), // px-2.5 py-1
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(8), // rounded-lg
                            border: Border.all(
                              color: btnHovered
                                  ? Colors.white.withAlpha(102) // /40
                                  : Colors.white.withAlpha(51), // white/20
                            ),
                            color: btnHovered
                                ? Colors.black.withAlpha(230) // bg-black/90
                                : Colors.black.withAlpha(179), // bg-black/70
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.image,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 6), // gap-1.5
                              Text(
                                t.tr('coversModal.openCovers'),
                                style: const TextStyle(
                                  fontSize: 12, // text-xs
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              if ((media.covers?.length ?? 0) > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _kAccentSoft // indigo-500/80 близко;
                                        .withAlpha(204),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${media.covers!.length}',
                                    style: const TextStyle(
                                      fontSize: 10, // text-[10px]
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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

  // ---- Статус + рейтинг ----

  Widget _buildStatusRow(I18nDictionary t, TsundokuTheme th) {
    return Row(
      children: [
        Expanded(
          child: TsundokuPopoverMenu<MediaStatus>(
            id: 'detail-status-${widget.media.id}',
            options: [
              for (final value in widget.statusOptions)
                PopoverOption(value: value, label: statusLabel(value, t)),
            ],
            selected: widget.media.status,
            onSelect: (value) => unawaited(widget.onChangeStatus(value)),
            label: t.tr('status.label'),
            matchTriggerWidth: true,
            placement: PopoverPlacement.bottomEnd,
            trigger: (context, ctx) => IgnorePointer(
              child: _HoverBuilder(
                builder: (context, hovered) => Container(
                  height: 40, // size-lg h-10
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14), // px-3.5
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(TsundokuPalette.radiusField),
                    border: Border.all(color: th.borderSubtle),
                    color: hovered ? const Color(0xFF1D2230) : const Color(0xFF151821),
                    // has-[:popover-open]:ring-2 ring-accent-soft
                    boxShadow: ctx.isOpen
                        ? [
                            BoxShadow(
                              color: _kAccentSoft.withAlpha(115),
                              blurRadius: 0,
                              spreadRadius: 2,
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusLabel(widget.media.status, t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis, // truncate
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: th.textPrimary,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: ctx.isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(LucideIcons.chevronDown,
                            size: 15, color: th.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8), // gap-2
        _buildRatingButton(t, th),
      ],
    );
  }

  Widget _buildRatingButton(I18nDictionary t, TsundokuTheme th) {
    final score = widget.scoreValue;
    final hasScore = score != null && score > 0;

    return CompositedTransformTarget(
      link: _ratingLink,
      child: MouseRegion(
        onEnter: (_) => widget.onRatingOpen(),
        onExit: (_) => widget.onRatingClose(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: widget.onRatingOpen,
            child: Semantics(
              button: true,
              // title/aria-label
              label: hasScore
                  ? '${t.tr('detail.yourRating')}: $score'
                  : t.tr('detail.yourRating'),
              child: _HoverBuilder(
                builder: (context, hovered) => Container(
                  width: 40, // h-10 w-10
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(TsundokuPalette.radiusField),
                    border: Border.all(
                      color: hasScore
                          ? _kAmber400.withAlpha(102) // border-amber-400/40
                          : Colors.white.withAlpha(21), // white/[0.08]
                    ),
                    color: hasScore
                        ? _kAmber400.withAlpha(26) // bg-amber-400/10
                        : (hovered
                            ? const Color(0xFF1D2230) // hover:bg-panel-raised
                            : const Color(0xFF151821)), // panel-line
                  ),
                  child: hasScore
                      ? _ScorePop(
                          key: ValueKey(score),
                          child: Text(
                            '$score',
                            style: const TextStyle(
                              fontSize: 17, // text-[17px]
                              fontWeight: FontWeight.w900, // font-black
                              color: _kAmber300,
                              letterSpacing: -0.5, // tracking-tight
                            ),
                          ),
                        )
                      : Icon(LucideIcons.star,
                          size: 18, color: Colors.white.withAlpha(204)),
                ),
              ),
            ),
          ),
            // top-full + mt-2: top-layer аналог z-30 absolute.
            OverlayPortal(
              controller: _ratingPortal,
              overlayChildBuilder: (context) => Align(
                alignment: Alignment.topLeft,
                child: CompositedTransformFollower(
                link: _ratingLink,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8), // mt-2
                showWhenUnlinked: false,
                child: MouseRegion(
                  // Контейнер-аналог Svelte: hover в поповере держит его
                  // открытым (onpointerenter/leave на общем контейнере).
                  onEnter: (_) => widget.onRatingOpen(),
                  onExit: (_) => widget.onRatingClose(),
                  child: _RatingPopover(state: this, th: th),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Сохранённая детальная оценка ----

  Widget _buildSavedDetailedCard(I18nDictionary t, TsundokuTheme th) {
    final savedSummary = _savedSummary!;
    final savedMap = _savedDetailedMap;
    return GestureDetector(
      onTap: () {
        setState(() {
          _detailedDraft = parseDetailedScore(widget.media.detailedScoreJson);
          _detailedExpanded = true;
        });
        widget.onRatingOpen();
      },
      child: _HoverBuilder(
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.all(12), // p-3
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
            border: Border.all(
              color: hovered
                  ? Colors.white.withAlpha(31) // hover:border-white/[0.12]
                  : Colors.white.withAlpha(15), // /[0.06]
            ),
            color: hovered ? _kPanelRaised : th.bgSurface, // panel-line
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.tr('detail.detailedScoreTitle'),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: hovered ? Colors.white : _kSlate300,
                    ),
                  ),
                  Text(
                    '★ ${savedSummary.exact.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kAmber400, // text-amber-400
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2), // pt-0.5
                child: Column(
                  children: [
                    for (final axis in _axes)
                      if (savedMap[axis.key] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6), // space-y-1.5
                          child: Row(
                            children: [
                              SizedBox(
                                width: 96, // w-24
                                child: Text(
                                  _isRu ? axis.labelRu : axis.labelEn,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11, // text-[11px]
                                    color: th.textMuted, // text-muted
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8), // gap-2
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    height: 6, // h-1.5
                                    color: Colors.white.withAlpha(20),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor:
                                          (savedMap[axis.key]! * 0.1).clamp(0, 1),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              _kAmber500.withAlpha(204),
                                              _kAmber400,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 16, // w-4
                                child: Text(
                                  '${savedMap[axis.key]}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _kSlate200,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Панель «Ваша история» ----

  Widget _buildHistoryPanel(I18nDictionary t, TsundokuTheme th) {
    final media = widget.media;
    final isRu = _isRu;
    final rows = <Widget>[];

    void addRow(Widget row, {bool first = false}) {
      if (!first && rows.isNotEmpty) {
        rows.add(Container(
          height: 1,
          color: Colors.white.withAlpha(15), // divide-white/[0.06]
        ));
      }
      rows.add(row);
    }

    Widget dlRow({required Widget left, required Widget right}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10), // py-2.5
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: left),
            const SizedBox(width: 12), // gap-3
            Flexible(child: right),
          ],
        ),
      );
    }

    // Фильмы смотрятся за один присест: started-строка не добавляет смысла.
    if (media.type != MediaType.movie) {
      addRow(dlRow(
        left: Text(t.tr('detail.startedLabel'),
            style: TextStyle(fontSize: 12, color: th.textMuted)),
        right: Text(
          widget.formatDate(media.startedAt),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white),
        ),
      ), first: true);
    }
    addRow(dlRow(
      left: Text(t.tr('detail.endedLabel'),
          style: TextStyle(fontSize: 12, color: th.textMuted)),
      right: Text(
        widget.formatDate(media.finishedAt),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white),
      ),
    ));

    if (media.type != MediaType.game &&
        media.nextAutoRefreshAt != null &&
        !_finishedRelease) {
      final status = (media.releaseStatus ?? '').toUpperCase();
      final value = status == 'HIATUS'
          ? t.tr('detail.autoRefreshHiatus')
          : (media.autoRefreshIntervalDays != null
              ? t.tf('detail.autoRefreshInterval',
                  [media.autoRefreshIntervalDays!])
              : '');
      addRow(dlRow(
        left: Text(t.tr('detail.autoRefreshTitle'),
            style: TextStyle(fontSize: 12, color: th.textMuted)),
        right: Text(
          value,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white),
        ),
      ));
    }

    // Voice/reading combobox.
    final comboScope = _comboScope;
    if (comboScope != null) {
      addRow(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        // Svelte: dd flex-1 min-w-0 — комбо занимает всю доступную ширину.
        child: Row(
          children: [
            Text(
              t.tr(comboScope == VoiceOptionScope.read
                  ? 'detail.readingFormatLabel'
                  : 'detail.voiceStudioLabel'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: th.textMuted),
            ),
            const SizedBox(width: 8), // gap-2
            Expanded(
              child: _VoiceCombo(
                state: this,
                t: t,
                th: th,
                isRu: isRu,
              ),
            ),
          ],
        ),
      ));
    }

    // Platform (только игры).
    if (media.type == MediaType.game) {
      addRow(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(t.tr('detailModal.platform'),
                style: TextStyle(fontSize: 12, color: th.textMuted)),
            const Spacer(),
            if (widget.platformOptions.isNotEmpty)
              _PlatformPicker(state: this, t: t, th: th)
            else
              Text('—',
                  style: TextStyle(fontSize: 12, color: th.textMuted)),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8), // mb-2
          child: Text(
            t.tr('detail.historyTitle').toUpperCase(),
            style: const TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w700, // font-bold
              letterSpacing: 0.6, // tracking-wider
              color: _kSlate200, // text-slate-200 uppercase tracking-wider
            ),
          ),
        ),
        TsundokuPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ],
    );
  }

  // ---- Панель «Действия» ----

  Widget _buildActionsPanel(I18nDictionary t, TsundokuTheme th) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.tr('detail.actionsTitle').toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: _kSlate200,
                ),
              ),
            ),
            // Редкие действия — в компактном меню «…».
            TsundokuPopoverMenu<String>(
              id: 'detail-actions-more-${widget.media.id}',
              options: [
                PopoverOption(
                    value: 'covers', label: t.tr('coversModal.openCovers')),
                PopoverOption(value: 'lists', label: t.tr('views.listAddTo')),
                PopoverOption(value: 'relink', label: t.tr('detail.changeSource')),
                PopoverOption(value: 'activity', label: t.tr('detail.activity')),
              ],
              selected: '',
              onSelect: (value) =>
                  _runMoreAction(_MoreAction.values.firstWhere(
                (a) => a.name == value,
              )),
              label: t.tr('detail.actionsMore'),
              placement: PopoverPlacement.bottomEnd,
              matchTriggerWidth: false,
              optionClass: 'text-xs',
              trigger: (context, ctx) => IgnorePointer(
                child: _HoverBuilder(
                  builder: (context, hovered) => Container(
                    width: 28, // size-sm iconOnly
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(TsundokuPalette.radiusField),
                      color: hovered ? th.bgHover : Colors.transparent,
                    ),
                    child: Icon(
                      LucideIcons.ellipsis,
                      size: 15,
                      color: ctx.isOpen ? th.textPrimary : th.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8), // mb-2
        TsundokuPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionRow(
                th: th,
                icon: LucideIcons.refreshCw,
                iconColor: _kSuccessLine,
                spin: widget.refreshBusy,
                label: t.tr('detail.updateMetadata'),
                disabled: widget.refreshBusy,
                onTap: () => unawaited(widget.onRefreshMetadata()),
              ),
              if (widget.refreshBusy && widget.syncStep != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    widget.syncStep!,
                    style: TextStyle(
                        fontSize: 11, color: th.textMuted), // text-[11px]
                  ),
                ),
              if (widget.refreshError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    errorMessage(widget.refreshError!, ref.read(i18nProvider)),
                    style: const TextStyle(
                        fontSize: 12, color: _kRose300), // text-xs rose-300
                  ),
                ),
              if (_isOngoing)
                _ActionRow(
                  th: th,
                  icon: LucideIcons.refreshCw,
                  iconColor: _kAccentSoft,
                  spin: _autoRefreshBusy,
                  label: _autoRefreshBusy
                      ? t.tr('views.calendarChecking')
                      : t.tr('detail.autoRefreshCheckNow'),
                  disabled: _autoRefreshBusy,
                  onTap: () => unawaited(_handleAutoRefresh()),
                ),
              _ActionRow(
                th: th,
                icon: LucideIcons.sparkles,
                iconColor: _kAccentSoft,
                pulse: widget.fillMissingBusy,
                label: widget.fillMissingBusy
                    ? t.tr('detail.fillMissingRunning')
                    : t.tr('detail.fillMissing'),
                disabled: widget.fillMissingBusy || widget.refreshBusy,
                onTap: widget.onFillMissing,
              ),
              _ActionRow(
                th: th,
                icon: LucideIcons.pencil,
                iconColor: _kInfoSoft,
                label: t.tr('detailModal.edit'),
                onTap: widget.onStartEdit,
              ),
              // Hold-to-delete: удержание 1 сек = подтверждение, без модалки.
              _HoldDeleteButton(
                th: th,
                t: t,
                hold: _deleteHold,
                deleteBusy: widget.deleteBusy,
                onTapDown: _deleteHold.press,
                onTapUp: _deleteHold.release,
              ),
              if (widget.deleteError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    errorMessage(widget.deleteError!, ref.read(i18nProvider)),
                    style: const TextStyle(
                        fontSize: 12, color: _kRose300), // text-xs rose-300
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Панель «Характеристики» ----

  Widget _buildDetailsPanel(I18nDictionary t, TsundokuTheme th) {
    final altTitles = _splitAltTitles;
    final genreChips = _genreChips;
    final specRows = _filteredSpecRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t.tr('detail.detailsTitle').toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: _kSlate200,
            ),
          ),
        ),
        TsundokuPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Alt-тайтлы: первые два + разворот.
              if (altTitles.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.only(bottom: 12), // pb-3
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Color(0x0DFFFFFF))), // /5
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('detail.altTitlesLabel'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: th.textMuted),
                      ),
                      const SizedBox(height: 8), // mt-2
                      for (final alt in altTitles.take(2))
                        Padding(
                          padding: const EdgeInsets.only(top: 4), // space-y-1
                          child: Text(
                            '• $alt',
                            style: TextStyle(
                              fontSize: 12, // text-xs
                              height: 20 / 12, // leading-5
                              color: Colors.white.withAlpha(217), // white/85
                            ),
                          ),
                        ),
                      if (_showAllAltTitles && altTitles.length > 2)
                        for (final alt in altTitles.skip(2))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• $alt',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 20 / 12,
                                  color: Colors.white.withAlpha(217),
                                )),
                          ),
                      if (altTitles.length > 2)
                        _FoldToggle(
                          th: th,
                          expanded: _showAllAltTitles,
                          label: _showAllAltTitles
                              ? t.tr('detail.altTitlesLess')
                              : t.tf('detail.altTitlesMore',
                                  [altTitles.length - 2]),
                          onPressed: () => setState(
                              () => _showAllAltTitles = !_showAllAltTitles),
                        ),
                    ],
                  ),
                ),
              ],
              // Жанры: матовые чипы + спойлер хвоста.
              if (genreChips.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12), // mt-3 pb-3
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: Color(0x0DFFFFFF))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tr('detail.genresLabel'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: th.textMuted),
                        ),
                        const SizedBox(height: 8), // pt-2
                        Wrap(
                          spacing: 6, // gap-1.5
                          runSpacing: 6,
                          children: [
                            for (final genre in genreChips.take(6))
                              TsundokuBadge(
                                tone: BadgeTone.neutral,
                                size: BadgeSize.sm,
                                child: Text(genreLabel(
                                    genre, t, ref.read(i18nProvider))),
                              ),
                          ],
                        ),
                        if (_showAllGenres && genreChips.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 6), // mt-1.5
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final genre in genreChips.skip(6))
                                  TsundokuBadge(
                                    tone: BadgeTone.neutral,
                                    size: BadgeSize.sm,
                                    child: Text(genreLabel(
                                        genre, t, ref.read(i18nProvider))),
                                  ),
                              ],
                            ),
                          ),
                        if (genreChips.length > 6)
                          _FoldToggle(
                            th: th,
                            expanded: _showAllGenres,
                            label: _showAllGenres
                                ? t.tr('detail.altTitlesLess')
                                : t.tf('detail.genresMore',
                                    [genreChips.length - 6]),
                            onPressed: () => sidebarSetState(
                                () => _showAllGenres = !_showAllGenres),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 12), // pt-3
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var idx = 0; idx < specRows.length; idx++)
                      _SpecDlRow(
                        row: specRows[idx],
                        th: th,
                        first: idx == 0,
                        last: idx == specRows.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- Вспомогательные виджеты ----

/// MouseRegion-hover builder.
class _HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  const _HoverBuilder({required this.builder});

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// score-pop: число перекатывается 1.3 → 1 (160ms cubic-bezier(.16,1,.3,1)).
class _ScorePop extends StatefulWidget {
  final Widget child;

  const _ScorePop({super.key, required this.child});

  @override
  State<_ScorePop> createState() => _ScorePopState();
}

class _ScorePopState extends State<_ScorePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _scale = Tween<double>(begin: 1.3, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.16, 1, 0.3, 1),
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Drop-причина: плашка при статусе dropped; открывает prompt.
class _DropReasonPill extends ConsumerWidget {
  final MediaDetail media;
  final bool isRu;

  const _DropReasonPill({required this.media, required this.isRu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final reason = media.dropReason ?? 'unspecified';
    final label =
        getDropReasonLabel(reason, lang: ref.watch(i18nProvider).wire);

    return _HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: () {
          ref.read(dropPromptStateProvider.notifier).open(DropPromptTarget(
                id: media.id,
                title: media.title,
                type: media.type.wire,
                isAnime: media.isAnime,
                dropReason: media.dropReason,
                dropNotes: media.dropNotes,
              ));
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(
              color: hovered
                  ? _kRose500.withAlpha(102) // hover:rose-500/40
                  : _kRose500.withAlpha(64), // rose-500/25
            ),
            color: hovered
                ? _kRose500.withAlpha(51) // hover:rose-500/20
                : _kRose500.withAlpha(26), // rose-500/10
          ),
          child: Row(
            children: [
              Icon(LucideIcons.ban, size: 13, color: _kRose400),
              const SizedBox(width: 6), // gap-1.5
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: t.tr('dropReason.badgePrefix'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _kRose400.withAlpha(204), // rose-400/80
                        ),
                      ),
                      TextSpan(
                        text: label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _kRose300,
                        ),
                      ),
                      if (media.dropNotes != null &&
                          media.dropNotes!.isNotEmpty)
                        TextSpan(
                          text: ' (${media.dropNotes})',
                          style: TextStyle(
                            fontSize: 11, // text-[11px]
                            color: _kRose300.withAlpha(153), // rose-300/60
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Pencil reveal на hover.
              Icon(LucideIcons.pencil,
                  size: 12, color: hovered ? _kRose400 : Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Поповер рейтинга: сетка 1..10, критерии (слайдеры), сохранение.
class _RatingPopover extends ConsumerStatefulWidget {
  final _DetailSidebarState state;
  final TsundokuTheme th;

  const _RatingPopover({required this.state, required this.th});

  @override
  ConsumerState<_RatingPopover> createState() => _RatingPopoverState();
}

class _RatingPopoverState extends ConsumerState<_RatingPopover> {
  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final t = ref.watch(tProvider);
    final th = widget.th;
    final score = st.widget.scoreValue;
    final savedSummary = st._savedSummary;
    final draftSummary = st._draftSummary;
    final width = st._detailedExpanded ? 288.0 : 192.0; // w-48 / w-72

    return Container(
      width: width,
      padding: const EdgeInsets.all(12), // p-3
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
            color: Colors.white.withAlpha(31)), // border-white/[0.12]
        color: th.bgOverlay, // bg-overlay
        boxShadow: const [
          BoxShadow(
              color: Color(0xE6000000), // shadow-black/90
              offset: Offset(0, 25),
              blurRadius: 50,
              spreadRadius: -12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок.
          Padding(
            padding: const EdgeInsets.only(bottom: 8), // mb-2
            child: Text.rich(
              TextSpan(
                children: [
                  if (score != null)
                    TextSpan(
                      text: '$score ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kAmber300,
                      ),
                    ),
                  TextSpan(
                    text: t.tr(
                        score != null ? 'detail.yourRating' : 'detail.rateButton'),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kSlate300),
            ),
          ),
          // Сетка 1..10 (5×2).
          Wrap(
            spacing: 6, // gap-1.5
            runSpacing: 6,
            children: [
              for (var index = 0; index < 10; index++)
                _ScoreButton(
                  state: st,
                  th: th,
                  value: index + 1,
                ),
            ],
          ),
          // Критерии (expand).
          Padding(
            padding: const EdgeInsets.only(top: 10), // mt-2.5
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
              ),
              padding: const EdgeInsets.only(top: 8), // pt-2
              child: GestureDetector(
                onTap: () => st.sidebarSetState(
                    () => st._detailedExpanded = !st._detailedExpanded),
                child: Row(
                  children: [
                    Text(
                      t.tr('detail.byCriteria'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: th.textPrimary),
                    ),
                    if (savedSummary != null) ...[
                      const SizedBox(width: 6), // gap-1.5
                      TsundokuBadge(
                        tone: BadgeTone.warning,
                        size: BadgeSize.xs,
                        child: Text(
                          '★ ${savedSummary.exact.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, // font-bold
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: st._detailedExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(LucideIcons.chevronDown,
                          size: 14, color: th.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (st._detailedExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Color(0x14FFFFFF))),
                ),
                padding: const EdgeInsets.only(top: 10), // pt-2.5
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final axis in st._axes)
                      _AxisSlider(state: st, th: th, axis: axis),
                    if (draftSummary != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Color(0x14FFFFFF))),
                          ),
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${t.tr('detail.detailedAverage')}:',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _kSlate300,
                                    ),
                                  ),
                                  Text(
                                    '★ ${draftSummary.exact.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _kAmber300,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6), // gap-1.5
                              _HoverBuilder(
                                builder: (context, hovered) =>
                                    GestureDetector(
                                  onTap: () async {
                                    final json = serializeDetailedScore(
                                        st._detailedDraft);
                                    if (st.widget.onSaveDetailedScore !=
                                        null) {
                                      await st.widget.onSaveDetailedScore!(
                                          json, draftSummary.rounded);
                                    } else {
                                      await st.widget
                                          .onSetScore(draftSummary.rounded);
                                    }
                                    st.widget.onRatingHide();
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6), // px-3 py-1.5
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: hovered
                                          ? _kAmber400.withAlpha(
                                              77) // hover:amber-400/30
                                          : _kAmber400.withAlpha(
                                              51), // bg-amber-400/20
                                    ),
                                    child: Text(
                                      t.tf('detail.saveDetailedScore',
                                          [draftSummary.rounded]),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12, // text-xs
                                        fontWeight: FontWeight.w700,
                                        color: _kAmber300,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (st.widget.onSaveDetailedScore != null &&
                                  (score == null ||
                                      score != draftSummary.rounded))
                                _HoverBuilder(
                                  builder: (context, hovered) =>
                                      GestureDetector(
                                    onTap: () async {
                                      final json = serializeDetailedScore(
                                          st._detailedDraft);
                                      await st.widget.onSaveDetailedScore!(
                                          json);
                                      st.widget.onRatingHide();
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4), // px-2 py-1
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        color: hovered
                                            ? Colors.white
                                                .withAlpha(26) // white/10
                                            : Colors.white
                                                .withAlpha(13), // white/5
                                      ),
                                      child: Text(
                                        t.tr('detail.saveCriteriaOnly'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11, // text-[11px]
                                          color: hovered
                                              ? Colors.white
                                              : _kSlate300,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Clear rating.
          if (score != null || savedSummary != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Color(0x14FFFFFF))),
                ),
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () {
                    st.widget.onClearScore();
                    st.sidebarSetState(() => st._detailedDraft = <String, int>{});
                    st.widget.onRatingHide();
                  },
                  child: Text(
                    t.tr('detail.clearRating'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600,
                      color: _kRose400, // hover:rose-300 — близко
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

/// Кнопка оценки 1..10.
class _ScoreButton extends StatelessWidget {
  final _DetailSidebarState state;
  final TsundokuTheme th;
  final int value;

  const _ScoreButton({
    required this.state,
    required this.th,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == state.widget.scoreValue;
    return _HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: () {
          unawaited(state.widget.onSetScore(value));
          state.widget.onRatingHide();
        },
        child: Container(
          width: 28, // h-7 w-7
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            color: selected
                ? th.chartBlue // bg-chart-blue
                : (hovered
                    ? Colors.white.withAlpha(38) // hover:white/15
                    : Colors.white.withAlpha(13)), // bg-white/5
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w700, // font-bold
              color: selected
                  ? Colors.white
                  : (hovered ? Colors.white : _kSlate300),
            ),
          ),
        ),
      ),
    );
  }
}

/// Слайдер одной оси критериев (range 1..10).
class _AxisSlider extends StatelessWidget {
  final _DetailSidebarState state;
  final TsundokuTheme th;
  final CriterionAxis axis;

  const _AxisSlider({
    required this.state,
    required this.th,
    required this.axis,
  });

  @override
  Widget build(BuildContext context) {
    final val = state._detailedDraft[axis.key];
    final isRu = state._isRu;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), // space-y-2.5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isRu ? axis.labelRu : axis.labelEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500,
                    color: _kSlate300,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${val ?? '—'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: val != null ? _kAmber300 : th.textMuted,
                ),
              ),
              if (val != null)
                GestureDetector(
                  onTap: () {
                    final next = <String, int>{...state._detailedDraft};
                    next.remove(axis.key);
                    state.sidebarSetState(() => state._detailedDraft = next);
                  },
                  child: Semantics(
                    button: true,
                    label: 'Очистить ${isRu ? axis.labelRu : axis.labelEn}',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2), // ml-0.5
                      child: Text(
                        '✕',
                        style: TextStyle(
                          fontSize: 10, // text-[10px]
                          color: th.textMuted, // hover:rose-400 упрощено
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // range 1..10: track h-1.5 white/10, thumb amber.
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6, // h-1.5
              activeTrackColor:
                  val == null ? Colors.white.withAlpha(10) : _kAmber400,
              inactiveTrackColor: Colors.white.withAlpha(10),
              thumbColor: _kAmber400,
              overlayColor: Colors.transparent,
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: (val ?? 5).toDouble(),
              min: 1,
              max: 10,
              divisions: 9, // step 1
              onChanged: (v) {
                final num = v.round();
                state.sidebarSetState(() {
                  state._detailedDraft = <String, int>{
                    ...state._detailedDraft,
                    axis.key: num,
                  };
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Voice/reading комбо: единый компонент поля ввода и выпадающего списка,
/// список открывается сразу при вводе текста или по нажатию на шеврон.
class _VoiceCombo extends ConsumerStatefulWidget {
  final _DetailSidebarState state;
  final I18nDictionary t;
  final TsundokuTheme th;
  final bool isRu;

  const _VoiceCombo({
    required this.state,
    required this.t,
    required this.th,
    required this.isRu,
  });

  @override
  ConsumerState<_VoiceCombo> createState() => _VoiceComboState();
}

class _VoiceComboState extends ConsumerState<_VoiceCombo> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _comboLink = LayerLink();
  final GlobalKey _comboKey = GlobalKey();
  String _lastExternal = '';
  bool _isOpen = false;
  bool _filterByInput = false;

  String get _tapGroupId => 'voice-combo-${widget.state.widget.media.id}';

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.state.widget.watchedOnInput);
    _lastExternal = widget.state.widget.watchedOnInput;
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      _openMenu(filterByInput: false);
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant _VoiceCombo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Внешняя смена значения (коммит из поповера) → синхронизация поля.
    final external = widget.state.widget.watchedOnInput;
    if (external != _lastExternal && external != _controller.text) {
      _controller.text = external;
    }
    _lastExternal = external;
  }

  @override
  void dispose() {
    PopoverCoordinator.instance.unregister(_closeMenu);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> _filteredOptions() {
    final all = widget.state._comboOptions;
    if (!_filterByInput) return all;
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all.where((o) => o.toLowerCase().contains(query)).toList();
  }

  void _openMenu({required bool filterByInput}) {
    _filterByInput = filterByInput;
    if (_filteredOptions().isEmpty) {
      _closeMenu();
      return;
    }
    PopoverCoordinator.instance.registerOpen(_closeMenu);
    if (!_isOpen) {
      setState(() => _isOpen = true);
      _portalController.show();
    } else {
      setState(() {});
    }
  }

  void _closeMenu() {
    PopoverCoordinator.instance.unregister(_closeMenu);
    if (!mounted) return;
    if (_isOpen || _portalController.isShowing) {
      setState(() => _isOpen = false);
      if (_portalController.isShowing) _portalController.hide();
    }
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu(filterByInput: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final state = widget.state;
    final t = widget.t;
    final comboLabel = t.tr(state._comboScope == VoiceOptionScope.read
        ? 'detail.readingFormatLabel'
        : 'detail.voiceStudioLabel');
    final watchedOnInput = state.widget.watchedOnInput;

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (menuContext) {
        final options = _filteredOptions();
        if (options.isEmpty) return const SizedBox.shrink();

        final box = _comboKey.currentContext?.findRenderObject() as RenderBox?;
        final comboWidth =
            (box != null && box.hasSize) ? box.size.width : 190.0;
        final menuWidth = comboWidth < 190.0 ? 190.0 : comboWidth;

        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _comboLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            showWhenUnlinked: false,
            child: TapRegion(
              groupId: _tapGroupId,
              onTapOutside: (_) => _closeMenu(),
              child: Material(
                color: const Color(0xFF151922),
                elevation: 12,
                shadowColor: const Color(0x80000000),
                borderOnForeground: true,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TsundokuPalette.radiusSelector),
                  side: const BorderSide(color: Color(0x14FFFFFF)),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: menuWidth,
                    maxWidth: 240,
                    maxHeight: 256,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final value in options)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              hoverColor: Colors.white.withAlpha(15),
                              onTap: () {
                                state._commitComboValue(value);
                                _controller.text = value;
                                _closeMenu();
                                _focusNode.unfocus();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: _ComboOptionRow(
                                  state: state,
                                  option: PopoverOption(
                                      value: value, label: value),
                                  selected: value == watchedOnInput,
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
          ),
        );
      },
      child: TapRegion(
        groupId: _tapGroupId,
        child: CompositedTransformTarget(
          link: _comboLink,
          child: ConstrainedBox(
            key: _comboKey,
            constraints: const BoxConstraints(maxWidth: 208), // max-w-[13rem]
            child: TsundokuTextField(
              controller: _controller,
              focusNode: _focusNode,
              height: 32,
              onChanged: (value) {
                state.widget.onWatchedOnInput(value);
                state.widget.onWatchedOnDirty();
                _openMenu(filterByInput: value.trim().isNotEmpty);
              },
              onSubmitted: (_) {
                // Enter коммитит через blur-путь.
                _closeMenu();
                FocusScope.of(context).unfocus();
                state._commitComboValue(state.widget.watchedOnInput);
              },
              textAlign: TextAlign.right,
              placeholder: t.tr('detail.watchedOnPlaceholder'),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              contentPadding: const EdgeInsets.only(left: 10, right: 4, top: 6, bottom: 6),
              suffix: Semantics(
                button: true,
                label: comboLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleMenu,
                  child: SizedBox(
                    width: 28,
                    height: 32,
                    child: Center(
                      child: AnimatedRotation(
                        turns: _isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          LucideIcons.chevronDown,
                          size: 13,
                          color: _isOpen
                              ? Colors.white
                              : Colors.white.withAlpha(153),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Платформа (игры): поповер выбора.
class _PlatformPicker extends ConsumerWidget {
  final _DetailSidebarState state;
  final I18nDictionary t;
  final TsundokuTheme th;

  const _PlatformPicker({
    required this.state,
    required this.t,
    required this.th,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = state.widget.media;
    return TsundokuPopoverMenu<String>(
      id: 'platform-${media.id}',
      options: [
        for (final value in state.widget.platformOptions)
          PopoverOption(value: value, label: value),
      ],
      selected: media.userPlatform ?? '',
      onSelect: (value) => unawaited(state.widget.onSelectPlatform(value)),
      label: t.tr('detailModal.platform'),
      placement: PopoverPlacement.bottomEnd,
      matchTriggerWidth: false,
      optionClass: 'text-xs',
      openOnHover: true,
      closeDelay: 220,
      trigger: (context, ctx) => IgnorePointer(
        child: _HoverBuilder(
          builder: (context, hovered) => Container(
            constraints:
                const BoxConstraints(maxWidth: 155), // max-w-[155px]
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6), // px-2.5 py-1.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(
                color: hovered || ctx.isOpen
                    ? th.accent.withAlpha(128) // hover: accent-50%
                    : Colors.white.withAlpha(21), // /[0.08]
              ),
              color: hovered ? _kTrackFaint : th.bgSurface, // bg-field
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  media.userPlatform?.isNotEmpty ?? false
                      ? media.userPlatform!
                      : t.tr('detail.platformNotSelected'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                AnimatedRotation(
                  turns: ctx.isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 13,
                    color: ctx.isOpen ? Colors.white : th.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка действия панели «Действия».
class _ActionRow extends StatelessWidget {
  final TsundokuTheme th;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool disabled;
  final bool spin;
  final bool pulse;
  final VoidCallback onTap;

  const _ActionRow({
    required this.th,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.disabled = false,
    this.spin = false,
    this.pulse = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TsundokuButton(
      variant: ButtonVariant.ghost,
      size: ButtonSize.sm,
      disabled: disabled,
      onPressed: onTap,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            AnimatedRotation(
              turns: spin ? 1 : 0,
              duration: spin ? const Duration(seconds: 1) : Duration.zero,
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8), // gap-2
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14, // text-sm (sm-кнопка)
                  fontWeight: FontWeight.w500,
                  color: th.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка удаления с hold-to-delete.
class _HoldDeleteButton extends StatelessWidget {
  final TsundokuTheme th;
  final I18nDictionary t;
  final HoldToDeleteController hold;
  final bool deleteBusy;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  const _HoldDeleteButton({
    required this.th,
    required this.t,
    required this.hold,
    required this.deleteBusy,
    required this.onTapDown,
    required this.onTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) => onTapUp(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: deleteBusy ? null : (_) => onTapDown(),
        onPointerUp: deleteBusy ? null : (_) => onTapUp(),
        onPointerCancel: deleteBusy ? null : (_) => onTapUp(),
        child: ListenableBuilder(
          listenable: hold.changes,
          builder: (context, _) {
            final label = hold.holding
                ? t.tr('holdToDelete.deleting')
                : hold.hintVisible
                    ? t.tr('holdToDelete.hint')
                    : t.tr('detailModal.delete');

            return TsundokuButton(
              variant: ButtonVariant.ghost,
              size: ButtonSize.sm,
              disabled: deleteBusy,
              holdProgress: hold.progress,
              onPressed: () {},
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 14, color: _kRose400),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: th.dangerText, // text-danger-text
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Шеврон-тоггл разворота списков (alt-тайтлы/жанры).
class _FoldToggle extends StatelessWidget {
  final TsundokuTheme th;
  final bool expanded;
  final String label;
  final VoidCallback onPressed;

  const _FoldToggle({
    required this.th,
    required this.expanded,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4), // mt-1
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: label,
            child: Container(
              height: 24, // h-6 (size xs)
              width: 24,
              alignment: Alignment.center,
              child: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(LucideIcons.chevronDown,
                    size: 14, color: th.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка spec-таблицы «Характеристик».
class _SpecDlRow extends ConsumerWidget {
  final SpecRow row;
  final TsundokuTheme th;
  final bool first;
  final bool last;

  const _SpecDlRow({
    required this.row,
    required this.th,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 12, bottom: last ? 0 : 12),
      decoration: (first && last)
          ? null
          : (last
              ? const BoxDecoration()
              : const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Color(0x0DFFFFFF))), // /5
                )),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w500,
              color: th.textMuted, // text-muted
            ),
          ),
          const SizedBox(width: 12), // gap-3
          Expanded(
            child: _SpecValue(row: row, th: th),
          ),
        ],
      ),
    );
  }
}

class _SpecValue extends ConsumerWidget {
  final SpecRow row;
  final TsundokuTheme th;

  const _SpecValue({required this.row, required this.th});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (row.href != null) {
      return Align(
        alignment: Alignment.centerRight,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () =>
                unawaited(platformService.openExternalUrl(row.href!)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (row.importSource != null)
                  Text(
                    '${row.importSource} · ',
                    style: const TextStyle(
                        fontSize: 12, color: _kZinc400), // text-zinc-400
                  ),
                Flexible(
                  child: Text(
                    row.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _kAccentSoft, // text-accent-soft
                    ),
                  ),
                ),
                const SizedBox(width: 4), // gap-1
                Icon(LucideIcons.externalLink,
                    size: 11, color: _kAccentSoft),
              ],
            ),
          ),
        ),
      );
    }
    if (row.badges != null && row.badges!.isNotEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 4, // gap-1
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: [
            for (final badge in row.badges!)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2), // px-1.5 py-0.5
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4), // rounded
                  border: Border.all(
                      color: Colors.white.withAlpha(26)), // white/10
                  color: Colors.white.withAlpha(13), // bg-white/5
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                      fontSize: 12, color: _kZinc300), // text-zinc-300
                ),
              ),
          ],
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          if (row.importSource != null)
            TextSpan(
              text: '${row.importSource} · ',
              style: const TextStyle(
                  fontSize: 12, color: _kZinc400), // text-zinc-400
            ),
          TextSpan(
            text: row.value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.right,
    );
  }
}

const Color _kZinc300 = Color(0xFFD4D4D8);


/// Строка опции voice/read-комбо: лейбл + звезда-избранное + check
/// (renderOption-сниппет, 1-в-1 с DetailSidebar.svelte).
class _ComboOptionRow extends StatelessWidget {
  final _DetailSidebarState state;
  final PopoverOption<String> option;
  final bool selected;

  const _ComboOptionRow({
    required this.state,
    required this.option,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final t = state.readT();
    final isFavorite = state._comboIsFavorite(option.value);
    final isSelected = option.value == state.widget.watchedOnInput;

    return Row(
      children: [
        Expanded(
          child: Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // truncate
            style: TextStyle(
              fontSize: 12, // optionClass text-xs
              color: isSelected ? th.accentSoft : th.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Звезда-избранное (role=button, click не закрывает меню: тап уходит
        // в звезду — GestureDetector внутри опции).
        GestureDetector(
          onTap: () => state._toggleComboFavorite(option.value),
          child: Semantics(
            button: true,
            label: t.tr(isFavorite
                ? 'detail.unmarkFavorite'
                : 'detail.markFavorite'),
            child: Container(
              width: 20, // size-5
              height: 20,
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.star,
                size: 13,
                color: isFavorite ? _kAmber300 : th.textMuted,
              ),
            ),
          ),
        ),
        if (isSelected)
          Icon(LucideIcons.check, size: 14, color: th.accentSoft),
      ],
    );
  }
}
