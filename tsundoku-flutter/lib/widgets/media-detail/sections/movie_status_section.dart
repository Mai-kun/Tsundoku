/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/MovieStatusSection.svelte`.
///
/// Хронометраж и статус фильма: длительность (короткая + «~X ч. Y мин.»),
/// быстрая смена статуса (planned/completed), строка «где смотрено».
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';

/// Секция статуса фильма (1-в-1 с MovieStatusSection.svelte).
class MovieStatusSection extends ConsumerWidget {
  final MediaDetail media;
  final String statusLabel;
  final VoidCallback onEdit;
  final void Function(MediaStatus status)? onChangeStatus;

  const MovieStatusSection({
    super.key,
    required this.media,
    required this.statusLabel,
    required this.onEdit,
    this.onChangeStatus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);

    final isRu = locale.wire == 'ru';

    final duration =
        media.type == MediaType.movie ? (media.durationMinutes ?? 0) : 0;
    final hours = duration ~/ 60;
    final mins = duration % 60;
    final durationShort = duration > 0
        ? '$duration ${isRu ? 'мин.' : 'min.'}'
        : null;
    final durationLong = hours > 0
        ? (isRu ? '~$hours ч. $mins мин.' : '~${hours}h ${mins}m')
        : null;

    final watchedOn = media.watchedOn;

    final isPlanned = media.status == MediaStatus.planned;
    final isCompleted = media.status == MediaStatus.completed;

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: th.bgSurface, // panel-line
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
          Row(
            children: [
              Icon(LucideIcons.clapperboard,
                  size: 16, color: th.accentSoft), // text-accent-soft
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Text(
                  (isRu ? 'Хронометраж и статус' : 'Runtime & Status')
                      .toUpperCase(), // uppercase (CSS-класс в Svelte)
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.6, // tracking-wider
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
              ),
              _EditButton(label: t.tr('detailModal.edit'), onTap: onEdit),
            ],
          ),
          const SizedBox(height: 16), // space-y-4
          if (durationShort != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10, // gap-2.5
              children: [
                Text(
                  durationShort,
                  style: const TextStyle(
                    fontSize: 30, // text-3xl
                    fontWeight: FontWeight.w800, // font-extrabold
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (durationLong != null)
                  Text(
                    '($durationLong)',
                    style: const TextStyle(
                      fontSize: 14, // text-sm
                      fontWeight: FontWeight.w500, // font-medium
                      color: Color(0xFF94A3B8), // text-slate-400
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16), // space-y-4
          Padding(
            padding: const EdgeInsets.only(top: 4), // pt-1
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRu ? 'БЫСТРАЯ СМЕНА СТАТУСА' : 'QUICK STATUS CHANGE',
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    fontWeight: FontWeight.w600, // font-semibold
                    letterSpacing: 0.6, // tracking-wider
                    color: th.textMuted, // text-muted
                  ),
                ),
                const SizedBox(height: 8), // space-y-2
                Wrap(
                  spacing: 8, // gap-2
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(
                      label: t.tr('status.planned'),
                      selected: isPlanned,
                      selectedBg: th.accentBright, // bg-accent-bright
                      selectedRing: th.accentBright,
                      selectedFg: Colors.white,
                      checkIcon: isPlanned
                          ? const Icon(LucideIcons.check,
                              size: 13, color: Colors.white)
                          : null,
                      disabled: onChangeStatus == null,
                      onTap: () => onChangeStatus?.call(MediaStatus.planned),
                    ),
                    _StatusPill(
                      label: t.tr('status.completed'),
                      selected: isCompleted,
                      selectedBg:
                          const Color(0xE6059669), // bg-emerald-600/90
                      selectedRing:
                          const Color(0xFF10B981), // ring-emerald-500
                      selectedFg: Colors.white,
                      checkIcon: isCompleted
                          ? const Icon(LucideIcons.check,
                              size: 13, color: Colors.white)
                          : null,
                      disabled: onChangeStatus == null,
                      onTap: () => onChangeStatus?.call(MediaStatus.completed),
                    ),
                    if (!isPlanned && !isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4), // px-2.5 py-1
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0x4DFBBF24)), // amber-400/30
                          color:
                              const Color(0x1AFBBF24), // bg-amber-400/10
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w500, // font-medium
                            color: Color(0xFFFCD34D), // text-amber-300
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (watchedOn != null && watchedOn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16), // space-y-4
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8), // px-3 py-2
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withAlpha(15)),
                  color: Colors.black.withAlpha(38), // bg-black/15
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.eye,
                        size: 14, color: th.accentSoft), // text-accent-soft
                    const SizedBox(width: 8), // gap-2
                    Text(
                      isRu ? 'Где смотрено:' : 'Watched on:',
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        color: th.textMuted, // text-muted
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        watchedOn,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600, // font-semibold
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Кнопка редактирования: px-2 py-1 text-xs, hover:bg-white/[0.06].
class _EditButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _EditButton({required this.label, required this.onTap});

  @override
  State<_EditButton> createState() => _EditButtonState();
}

class _EditButtonState extends State<_EditButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // px-2 py-1
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              color: _hovered
                  ? Colors.white.withAlpha(15) // hover:bg-white/[0.06]
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.pencil,
                    size: 12,
                    color: _hovered
                        ? Colors.white // hover:text-white
                        : th.textMuted),
                const SizedBox(width: 4), // gap-1
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: _hovered ? Colors.white : th.textMuted,
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

/// Пилюля статуса: selected — filled+ring; idle — border-white/10.
class _StatusPill extends StatefulWidget {
  final String label;
  final bool selected;
  final Color selectedBg;
  final Color selectedRing;
  final Color selectedFg;
  final Widget? checkIcon;
  final bool disabled;
  final VoidCallback onTap;

  const _StatusPill({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.selectedRing,
    required this.selectedFg,
    required this.checkIcon,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // px-3 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            color: widget.selected
                ? widget.selectedBg
                : _hovered
                    ? Colors.white.withAlpha(26) // hover:bg-white/10
                    : Colors.white.withAlpha(8), // bg-white/[0.03]
            border: widget.selected
                ? Border.all(color: widget.selectedRing, width: 1) // ring-1
                : Border.all(color: Colors.white.withAlpha(26)), // white/10
            boxShadow: widget.selected
                ? const [
                    // shadow-sm
                    BoxShadow(
                      color: Color(0x0D000000),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.checkIcon != null) ...[
                widget.checkIcon!,
                const SizedBox(width: 6), // gap-1.5
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: widget.selected
                      ? widget.selectedFg
                      : _hovered
                          ? Colors.white // hover:text-white
                          : const Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
