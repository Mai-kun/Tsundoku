/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/sections/ProgressCard.svelte`.
///
/// Карточка прогресса: SVG-кольцо с процентами, большой счётчик (tap →
/// ручной ввод), иерархия кнопок (− / +1 / +5 / Start), трек прогресса
/// (сегменты при малых total, непрерывный бар + drag-установка при больших),
/// milestone-точки 25/50/75/100, блок времени (мин/единица), pace-чипы с
/// оценкой даты завершения, completed-итог.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/media_labels.dart';
import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';

/// Категорийные акценты карточки: плоские цвета, без градиентов/glow
/// (deslop-проверка в Svelte следит за этим намеренно).
enum ProgressAccent { indigo, amber, teal, theme }

/// Цветовой набор акцента (аналог ACCENTS-записи в Svelte).
class ProgressAccentColors {
  final Color text;
  final Color stroke;
  final Color fill;
  final Color fillSoft;
  final Color buttonFill;
  final Color buttonHover;
  final Color buttonFg;
  final Color outlineBorder;
  final Color chipActiveBorder;
  final Color chipActiveBg;
  final Color chipActiveText;

  const ProgressAccentColors({
    required this.text,
    required this.stroke,
    required this.fill,
    required this.fillSoft,
    required this.buttonFill,
    required this.buttonHover,
    required this.buttonFg,
    required this.outlineBorder,
    required this.chipActiveBorder,
    required this.chipActiveBg,
    required this.chipActiveText,
  });
}

ProgressAccentColors _accentColors(ProgressAccent accent, TsundokuTheme th) {
  const indigo = Color(0xFF8B7CF6);
  const indigoHover = Color(0xFF7B6CEA);
  const amber = Color(0xFFF59E0B);
  const teal = Color(0xFF14B8A6);
  switch (accent) {
    case ProgressAccent.indigo:
      return ProgressAccentColors(
        text: indigo,
        stroke: indigo,
        fill: indigo,
        fillSoft: indigo.withAlpha(89), // /35
        buttonFill: indigo,
        buttonHover: indigoHover,
        buttonFg: Colors.white,
        outlineBorder: indigo.withAlpha(128), // /50
        chipActiveBorder: indigo.withAlpha(153), // /60
        chipActiveBg: indigo.withAlpha(38), // /15
        chipActiveText: indigo,
      );
    case ProgressAccent.amber:
      return ProgressAccentColors(
        text: amber,
        stroke: amber,
        fill: amber.withAlpha(230), // /90
        fillSoft: amber.withAlpha(89),
        buttonFill: amber.withAlpha(230),
        buttonHover: amber,
        buttonFg: Colors.black,
        outlineBorder: amber.withAlpha(128),
        chipActiveBorder: amber.withAlpha(153),
        chipActiveBg: amber.withAlpha(38),
        chipActiveText: amber,
      );
    case ProgressAccent.teal:
      return ProgressAccentColors(
        text: teal,
        stroke: teal,
        fill: teal.withAlpha(230),
        fillSoft: teal.withAlpha(89),
        buttonFill: teal.withAlpha(230),
        buttonHover: teal,
        buttonFg: Colors.black,
        outlineBorder: teal.withAlpha(128),
        chipActiveBorder: teal.withAlpha(153),
        chipActiveBg: teal.withAlpha(38),
        chipActiveText: teal,
      );
    case ProgressAccent.theme:
      return ProgressAccentColors(
        text: th.accentSoft, // text-accent-soft
        stroke: th.accent, // stroke-[var(--color-accent)]
        fill: th.accent, // bg-accent
        fillSoft: th.accent.withAlpha(89), // /35
        buttonFill: th.accent,
        buttonHover: th.accentHover, // hover:bg-accent-hover
        buttonFg: Colors.white,
        outlineBorder: th.accent.withAlpha(128),
        chipActiveBorder: th.accent.withAlpha(153),
        chipActiveBg: th.accent.withAlpha(38),
        chipActiveText: th.accentSoft,
      );
  }
}

const double _ringRadius = 48;
const int _segmentLimit = 36;
const List<int> _milestones = [25, 50, 75];

/// Карточка прогресса (1-в-1 с ProgressCard.svelte).
class ProgressCard extends ConsumerStatefulWidget {
  /// Uppercase section label: episodes / chapters / pages / hours.
  final String label;
  final int value;

  /// 0 means «unknown» (games): no ring, no bar, no time math.
  final int total;
  final double percent;

  /// Short unit after the total: ep. / ch. / pp. / h.
  final String unitShort;

  /// Caption verb for the consumed side: watched / read / played.
  final String doneLabel;
  final String remainLabel;

  /// Minutes per unit; null disables the whole time block (games).
  final int? minsPerUnit;

  /// Singular noun for the pacing caption: episode / chapter / page.
  final String? unitNoun;
  final List<int> paceOptions;
  final int paceDefault;
  final String startHint;
  final String? finishedAt;
  final String? totalTooltip;
  final ProgressAccent accent;
  final Object? error;
  final void Function(int delta) onStep;
  final void Function(int value)? onCounterChange;

  const ProgressCard({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    required this.percent,
    required this.unitShort,
    required this.doneLabel,
    required this.remainLabel,
    this.minsPerUnit,
    this.unitNoun,
    required this.paceOptions,
    this.paceDefault = 1,
    required this.startHint,
    this.finishedAt,
    this.totalTooltip,
    required this.accent,
    required this.error,
    required this.onStep,
    this.onCounterChange,
  });

  @override
  ConsumerState<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<ProgressCard> {
  /// The default pace is read once: the chip selection is user state, not a
  /// live derivation.
  late int _pace = widget.paceDefault;

  bool _isEditing = false;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // total может прийти с задержкой — контекст редактирования сбрасывать не
    // нужно (Svelte ведёт себя так же: стейт живёт своей жизнью).
  }

  double get _pct => math.min(100, math.max(0, widget.percent));
  bool get _isCompleted => widget.total > 0 && widget.value >= widget.total;
  bool get _isEmpty => widget.value == 0 && !_isCompleted;
  bool get _segmented => widget.total > 0 && widget.total <= _segmentLimit;
  int get _remainingUnits => math.max(0, widget.total - widget.value);

  int get _watchedMinutes =>
      widget.minsPerUnit != null && widget.minsPerUnit! > 0
          ? (widget.value * widget.minsPerUnit!).round()
          : 0;
  int get _totalMinutes =>
      widget.minsPerUnit != null && widget.minsPerUnit! > 0 && widget.total > 0
          ? (widget.total * widget.minsPerUnit!).round()
          : 0;
  int get _remainingMinutes =>
      widget.minsPerUnit != null && widget.minsPerUnit! > 0
          ? (_remainingUnits * widget.minsPerUnit!).round()
          : 0;

  int? get _daysAtPace =>
      (_pace > 0 && _remainingUnits > 0)
          ? (_remainingUnits / _pace).ceil()
          : null;

  String? _finishEstimate(I18nDictionary t, Locale locale) {
    final days = _daysAtPace;
    if (days == null) return null;
    final date = DateTime.now().add(Duration(days: days));
    initializeDateFormatting(locale.wire, null);
    final label = DateFormat('d MMMM', locale.wire).format(date);
    return t.tf('progress.finishAt', [label, days]);
  }

  String _doneCaption(I18nDictionary t, Locale locale) {
    if (widget.minsPerUnit != null && widget.minsPerUnit! > 0) {
      return '${widget.doneLabel} ${formatNumber(_watchedMinutes, locale)} ${t.tr('progress.minShort')}';
    }
    final caption =
        '${widget.doneLabel} ${formatNumber(widget.value, locale)} ${widget.unitShort}';
    return caption.trim();
  }

  String? _unitDurationCaption(I18nDictionary t, Locale locale) {
    final minsPerUnit = widget.minsPerUnit;
    if (minsPerUnit == null ||
        minsPerUnit <= 0 ||
        widget.unitNoun == null ||
        widget.total <= 0) {
      return null;
    }
    final mins =
        '${minsPerUnit.round()} ${t.tr('progress.minShort')}';
    return '${t.tf('progress.unitDuration', [widget.unitNoun!, mins])} · ${t.tf('progress.totalDuration', [_formatDuration(_totalMinutes, t)])}';
  }

  String? _finishedDateLabel(Locale locale) {
    final finishedAt = widget.finishedAt;
    if (finishedAt == null || finishedAt.isEmpty) return null;
    final date = DateTime.tryParse(finishedAt);
    if (date == null) return null;
    initializeDateFormatting(locale.wire, null);
    // dateStyle: medium ≈ 'd MMM y' (ru: «6 апр. 1997 г.»).
    return DateFormat('d MMM y', locale.wire).format(date);
  }

  String _formatDuration(int minutes, I18nDictionary t) {
    final hours = minutes ~/ 60;
    final mins = (minutes % 60).round();
    if (hours > 0 && mins > 0) return t.tf('progress.durationHM', [hours, mins]);
    if (hours > 0) return t.tf('progress.durationH', [hours]);
    return t.tf('progress.durationM', [mins]);
  }

  void _applyValue(int nextVal) {
    final clamped = math.max(
        0, widget.total > 0 ? math.min(nextVal, widget.total) : nextVal);
    if (clamped == widget.value) return;
    if (widget.onCounterChange != null) {
      widget.onCounterChange!(clamped);
    } else {
      widget.onStep(clamped - widget.value);
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
  }

  void _commitEditing(String editValue) {
    if (!_isEditing) return;
    setState(() => _isEditing = false);
    final parsed = int.tryParse(editValue);
    if (parsed != null) {
      _applyValue(parsed);
    }
  }

  int _valueFromPointer(double barWidth, double dx) {
    if (barWidth <= 0 || widget.total <= 0) return widget.value;
    final x = dx.clamp(0.0, barWidth);
    final ratio = x / barWidth;
    return (ratio * widget.total).round();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final a = _accentColors(widget.accent, th);
    final isCompleted = _isCompleted;

    final errorText = widget.error != null
        ? errorMessage(widget.error!, locale)
        : null;
    final finishEstimate = _finishEstimate(t, locale);
    final unitDurationCaption = _unitDurationCaption(t, locale);
    final finishedDateLabel = _finishedDateLabel(locale);

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
          color: isCompleted
              ? const Color(0x4D34D399) // border-emerald-400/30
              : Colors.white.withAlpha(15), // border-white/[0.06]
        ),
        color: th.bgSurface, // bg-[var(--color-panel-line)]
        boxShadow: const [
          // shadow-sm
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header zone: кольцо + счётчик + иерархия кнопок.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.total > 0) ...[
                SizedBox(
                  width: 104, // size-[104px]
                  height: 104,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: const Size.square(104),
                        painter: _RingPainter(
                          percent: _pct,
                          stroke: a.stroke,
                        ),
                      ),
                      Center(
                        child: Text(
                          '${_pct.round()}%',
                          style: const TextStyle(
                            fontSize: 18, // text-lg
                            fontWeight: FontWeight.w700, // font-bold
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16), // gap-4
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8, // gap-2
                      children: [
                        Text(
                          widget.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w700, // font-bold
                            letterSpacing: 0.6, // tracking-wider
                            color: Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                        if (isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2), // px-2 py-0.5
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(999), // rounded-full
                              border: Border.all(
                                  color:
                                      const Color(0x4D34D399)), // emerald-400/30
                              color:
                                  const Color(0x1A34D399), // emerald-400/10
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.check,
                                    size: 11, color: Color(0xFF6EE7B7)),
                                const SizedBox(width: 4), // gap-1
                                Text(
                                  t.tr('progress.completedBadge'),
                                  style: const TextStyle(
                                    fontSize: 11, // text-[11px]
                                    fontWeight: FontWeight.w700, // font-bold
                                    color: Color(0xFF6EE7B7), // emerald-300
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6), // space-y-1.5
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8, // gap-x-2
                      children: [
                        if (_isEditing)
                          _EditValueField(
                            value: widget.value,
                            total: widget.total,
                            onCommit: _commitEditing,
                            onCancel: () => setState(() => _isEditing = false),
                          )
                        else
                          _CounterButton(
                            value: widget.value,
                            locale: locale,
                            title: t.tr('progress.manualInputTitle'),
                            onTap: _startEditing,
                          ),
                        if (widget.total > 0)
                          Tooltip(
                            message: widget.totalTooltip ?? '',
                            child: Text(
                              '/ ${formatNumber(widget.total, locale)} ${widget.unitShort}',
                              style: TextStyle(
                                fontSize: 17, // text-[17px]
                                fontWeight: FontWeight.w600, // font-semibold
                                color: th.textMuted, // text-muted
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16), // gap-4
              // Control hierarchy: quiet −, filled +1, outlined +5; пустая
              // карточка — один Start (+1).
              Wrap(
                spacing: 6, // gap-1.5
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isCompleted) ...[
                    _QuietButton(
                      icon: LucideIcons.minus,
                      label: t.tr('card.decrement'),
                      accent: a,
                      disabled: widget.value <= 0,
                      onTap: () => widget.onStep(-1),
                    ),
                  ] else if (_isEmpty) ...[
                    _StartButton(
                      label: t.tr('progress.startButton'),
                      accent: a,
                      onTap: () => widget.onStep(1),
                    ),
                  ] else ...[
                    _QuietButton(
                      icon: LucideIcons.minus,
                      label: t.tr('card.decrement'),
                      accent: a,
                      disabled: widget.value <= 0,
                      onTap: () => widget.onStep(-1),
                    ),
                    _FilledButton(
                      label: '+1',
                      ariaLabel: '+1',
                      accent: a,
                      disabled: widget.total > 0 && widget.value >= widget.total,
                      onTap: () => widget.onStep(1),
                    ),
                    if (widget.total == 0 || widget.total - widget.value >= 5)
                      _OutlinedButton(
                        label: '+5',
                        ariaLabel: '+5',
                        accent: a,
                        disabled:
                            widget.total > 0 && widget.value >= widget.total,
                        onTap: () => widget.onStep(5),
                      ),
                  ],
                ],
              ),
            ],
          ),

          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 16), // space-y-4
              child: Semantics(
                liveRegion: true, // role="alert"
                child: Text(
                  errorText,
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    color: Color(0xFFFDA4AF), // text-rose-300
                  ),
                ),
              ),
            ),

          // 2. Progress track: сегменты для малых total, непрерывный бар +
          // drag для длинных; milestone-точки 25/50/75/100%.
          if (widget.total > 0) ...[
            const SizedBox(height: 16), // space-y-4
            // role="slider": aria-valuenow/min/max.
            Semantics(
              slider: true,
              label: widget.label,
              value: '${widget.value}/${widget.total}',
              child: LayoutBuilder(builder: (context, constraints) {
                final barWidth = constraints.maxWidth;
                return Listener(
                key: const ValueKey('progress-bar'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (widget.total <= 0) return;
                  setState(() => _isDragging = true);
                  _applyValue(_valueFromPointer(barWidth,
                      (event.localPosition).dx.clamp(0.0, barWidth)));
                },
                onPointerMove: (event) {
                  if (!_isDragging || widget.total <= 0) return;
                  _applyValue(_valueFromPointer(barWidth,
                      (event.localPosition).dx.clamp(0.0, barWidth)));
                },
                onPointerUp: (_) => _isDragging = false,
                onPointerCancel: (_) => _isDragging = false,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_segmented)
                        Row(
                          children: [
                            for (var i = 0; i < widget.total; i++)
                              Expanded(
                                child: Container(
                                  height: 10, // h-2.5
                                  margin: EdgeInsets.only(
                                      right: i == widget.total - 1
                                          ? 0
                                          : 3), // gap-[3px]
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: i < widget.value
                                        ? a.fill
                                        : i == widget.value
                                            ? a.fillSoft // animate-pulse ⏭️ (тон-пульс)
                                            : Colors.white.withAlpha(20),
                                  ),
                                ),
                              ),
                          ],
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 10, // h-2.5
                            color: Colors.white.withAlpha(20), // /[0.08]
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150), // 150ms
                                curve: Curves.easeOut,
                                width: barWidth * _pct / 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: a.fill,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6), // mt-1.5
                      SizedBox(
                        height: 6, // h-1.5
                        child: Stack(
                          children: [
                            for (final m in _milestones)
                              Positioned(
                                left:
                                    barWidth * m / 100 - 3, // -translate-x-1/2
                                top: 0,
                                child: Container(
                                  width: 6, // size-1.5
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _pct >= m
                                        ? Colors.white.withAlpha(102) // /40
                                        : Colors.white.withAlpha(38), // /15
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _pct >= 100
                                      ? Colors.white.withAlpha(102)
                                      : Colors.white.withAlpha(38),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 16), // space-y-4
            Row(
              children: [
                Text(
                  _doneCaption(t, locale),
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    color: th.textMuted, // text-muted
                  ),
                ),
                const Spacer(),
                if (!isCompleted)
                  Text(
                    t.tf('progress.remainingOf',
                        [_remainingUnits, widget.total]),
                    style: TextStyle(
                      fontSize: 11,
                      color: th.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ],

          // 3. Bottom zone: приглашение начать, блок времени + pace, итог.
          if (_isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16), // space-y-4
              child: Text(
                widget.startHint,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  color: Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            )
          else if (isCompleted) ...[
            if (widget.minsPerUnit != null &&
                widget.minsPerUnit! > 0 &&
                widget.total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16), // space-y-4
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12), // px-3.5 py-3
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12), // rounded-xl
                    border: Border.all(
                        color: const Color(0x3334D399)), // emerald-400/20
                    color: const Color(0x0F34D399), // emerald-400/[0.06]
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('progress.totalTimeLabel').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11, // text-[11px]
                                fontWeight: FontWeight.w600, // font-semibold
                                letterSpacing: 0.6, // tracking-wider
                                color: Color(0xB36EE7B7), // emerald-300/80
                              ),
                            ),
                            Text(
                              _formatDuration(_totalMinutes, t),
                              style: const TextStyle(
                                fontSize: 20, // text-xl
                                fontWeight: FontWeight.w700, // font-bold
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (finishedDateLabel != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              t.tr('progress.finishedOn'),
                              style: TextStyle(
                                fontSize: 11,
                                color: th.textMuted,
                              ),
                            ),
                            Text(
                              finishedDateLabel,
                              style: const TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w500, // font-medium
                                color: Color(0xFFE2E8F0), // text-slate-200
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ]
          else if (widget.minsPerUnit != null &&
              widget.minsPerUnit! > 0 &&
              widget.total > 0) ...[
            const SizedBox(height: 16), // space-y-4
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12), // px-3.5 py-3
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(15)),
                color: Colors.black.withAlpha(38), // bg-black/15
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12, // gap-x-3
                    runSpacing: 4, // gap-y-1
                    children: [
                      Text(
                        t.tr('progress.remainingTimeLabel').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          fontWeight: FontWeight.w600, // font-semibold
                          letterSpacing: 0.6, // tracking-wider
                          color: th.textMuted, // text-muted
                        ),
                      ),
                      Text(
                        _formatDuration(_remainingMinutes, t),
                        style: const TextStyle(
                          fontSize: 26, // text-[26px]
                          height: 1.0, // leading-none
                          fontWeight: FontWeight.w700, // font-bold
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (widget.minsPerUnit != null &&
                          widget.minsPerUnit! > 0 &&
                          _remainingUnits > 0)
                        Text(
                          '${widget.remainLabel} ${formatNumber(_remainingUnits, locale)} ${widget.unitShort}',
                          style: TextStyle(
                            fontSize: 12, // text-xs
                            color: th.textMuted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  if (unitDurationCaption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6), // mt-1.5
                      child: Text(
                        unitDurationCaption,
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          color: th.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.paceOptions.isNotEmpty && _remainingUnits > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16), // space-y-4
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6, // gap-1.5
                  runSpacing: 6,
                  children: [
                    Text(
                      '${t.tr('progress.paceLabel')}:',
                      style: TextStyle(
                        fontSize: 11, // text-[11px]
                        color: th.textMuted,
                      ),
                    ),
                    for (final p in widget.paceOptions)
                      _PaceChip(
                        value: p,
                        selected: _pace == p,
                        accent: a,
                        th: th,
                        onTap: () => setState(() => _pace = p),
                      ),
                    Text(
                      t.tf('progress.pacePerDay', [widget.unitShort]),
                      style: TextStyle(
                        fontSize: 11,
                        color: th.textMuted,
                      ),
                    ),
                    if (finishEstimate != null)
                      Text(
                        '→ $finishEstimate',
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// SVG-кольцо (viewBox 104×104, -rotate-90): трек white/0.07 + дуга
/// stroke-dasharray/offset с переходом 300ms.
class _RingPainter extends CustomPainter {
  final double percent;
  final Color stroke;

  _RingPainter({required this.percent, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white.withAlpha(18); // stroke-white/[0.07]
    canvas.drawCircle(center, _ringRadius, trackPaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    final rect = Rect.fromCircle(center: center, radius: _ringRadius);
    // -rotate-90: старт дуги сверху; доля = pct/100.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * percent / 100, false,
        progressPaint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.stroke != stroke;
}

/// Большой счётчик (counter-pop анимация 180ms при смене значения).
class _CounterButton extends StatelessWidget {
  final int value;
  final Locale locale;
  final String title;
  final VoidCallback onTap;

  const _CounterButton({
    required this.value,
    required this.locale,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(value), // {#key value} → pop на каждой смене
          tween: Tween(begin: 1.12, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Text(
            formatNumber(value, locale),
            style: const TextStyle(
              fontSize: 38, // text-[38px]
              height: 1.0, // leading-none
              fontWeight: FontWeight.w800, // font-extrabold
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Поле ручного ввода: h-10 w-24, 28px, autofocus + select.
class _EditValueField extends StatefulWidget {
  final int value;
  final int total;
  final void Function(String value) onCommit;
  final VoidCallback onCancel;

  const _EditValueField({
    required this.value,
    required this.total,
    required this.onCommit,
    required this.onCancel,
  });

  @override
  State<_EditValueField> createState() => _EditValueFieldState();
}

class _EditValueFieldState extends State<_EditValueField> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');
  late final FocusNode _focusNode = FocusNode(onKeyEvent: (node, event) {
    // Escape → отмена (Svelte: onkeydown Escape → isEditing = false).
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });

  @override
  void initState() {
    super.initState();
    // onblur={commitEditing}: потеря фокуса коммитит.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onCommit(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return SizedBox(
      width: 96, // w-24
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true, // use:focusOnMount
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 28, // text-[28px]
          fontWeight: FontWeight.w800, // font-extrabold
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.black.withAlpha(153), // bg-black/60
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10), // px-2
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withAlpha(26)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: th.accent), // focus:border-accent
          ),
        ),
        onSubmitted: widget.onCommit,
      ),
    );
  }
}

/// Quiet-кнопка (−): size-8, border-white/10, text-slate-400.
class _QuietButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final ProgressAccentColors accent;
  final bool disabled;
  final VoidCallback onTap;

  const _QuietButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label, // aria-label card.decrement
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: 32, // size-8
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(26)), // /10
          ),
          child: Icon(
            icon,
            size: 15,
            color: disabled
                ? Colors.white.withAlpha(102) // disabled:opacity-40
                : const Color(0xFF94A3B8), // text-slate-400
          ),
        ),
      ),
    );
  }
}

/// Filled-кнопка (+1): buttonFill, h-8 px-3.
class _FilledButton extends StatelessWidget {
  final String label;
  final String ariaLabel;
  final ProgressAccentColors accent;
  final bool disabled;
  final VoidCallback onTap;

  const _FilledButton({
    required this.label,
    required this.ariaLabel,
    required this.accent,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: ariaLabel,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 32, // h-8
          padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: disabled
                ? accent.buttonFill.withAlpha(102) // disabled:opacity-40
                : accent.buttonFill,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                color: accent.buttonFg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined-кнопка (+5): border accent/50, text accent, h-8 px-2.5.
class _OutlinedButton extends StatelessWidget {
  final String label;
  final String ariaLabel;
  final ProgressAccentColors accent;
  final bool disabled;
  final VoidCallback onTap;

  const _OutlinedButton({
    required this.label,
    required this.ariaLabel,
    required this.accent,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: ariaLabel,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 32, // h-8
          padding: const EdgeInsets.symmetric(horizontal: 10), // px-2.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.outlineBorder),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: disabled ? accent.text.withAlpha(102) : accent.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Start-кнопка пустой карточки: h-9 px-4 text-sm bold, buttonFill.
class _StartButton extends StatelessWidget {
  final String label;
  final ProgressAccentColors accent;
  final VoidCallback onTap;

  const _StartButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36, // h-9
        padding: const EdgeInsets.symmetric(horizontal: 16), // px-4
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: accent.buttonFill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14, // text-sm
                fontWeight: FontWeight.w700, // font-bold
                color: accent.buttonFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pace-чип: h-6 min-w-7, active — chipActive, idle — chipIdle.
class _PaceChip extends StatelessWidget {
  final int value;
  final bool selected;
  final ProgressAccentColors accent;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _PaceChip({
    required this.value,
    required this.selected,
    required this.accent,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected, // aria-pressed
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24, // h-6
          constraints: const BoxConstraints(minWidth: 28), // min-w-7
          padding: const EdgeInsets.symmetric(horizontal: 6), // px-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(
              color: selected ? accent.chipActiveBorder : Colors.white.withAlpha(26),
            ),
            color: selected ? accent.chipActiveBg : Colors.transparent,
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                color: selected
                    ? accent.chipActiveText
                    : const Color(0xFF94A3B8), // text-slate-400
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
