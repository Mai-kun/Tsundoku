/// 1:1 port of `mediatracker-ui/src/entities/media/ui/MediaStatusBadge.svelte`.
///
/// Круглая статус-кнопка 2.33rem: цвета из statusBadgeClasses, иконки lucide
/// (Bookmark/Play/Check/Pause/X), hover:brightness-125 и
/// has-[:popover-open]:ring-2 ring-indigo-400/70; смена статуса через
/// TsundokuPopoverMenu (5 опций в порядке statusOptions).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../model/media_labels.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/types/enums.dart';
import '../../../shared/ui/popover_menu.dart';

/// 1-в-1 с `statusOptions` в Svelte.
const List<MediaStatus> _statusOptions = <MediaStatus>[
  MediaStatus.planned,
  MediaStatus.inProgress,
  MediaStatus.completed,
  MediaStatus.onHold,
  MediaStatus.dropped,
];

class MediaStatusBadge extends ConsumerWidget {
  final String id;
  final MediaStatus status;
  final void Function(MediaStatus status) onSelect;

  const MediaStatusBadge({
    super.key,
    required this.id,
    required this.status,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);

    // Svelte добавляет случайный instanceId к popoverMenuId: в Flutter
    // позиционирование поповера живёт на GlobalKey, DOM-id не существует —
    // id оставлен для семантики/тестов.
    return TsundokuPopoverMenu<MediaStatus>(
      id: '$id-status-badge',
      options: <PopoverOption<MediaStatus>>[
        for (final value in _statusOptions)
          PopoverOption(value: value, label: statusLabel(value, t)),
      ],
      selected: status,
      onSelect: onSelect,
      label: statusLabel(status, t),
      trigger: (context, ctx) =>
          _StatusTrigger(status: status, isOpen: ctx.isOpen),
    );
  }
}

class _StatusTrigger extends StatefulWidget {
  final MediaStatus status;
  final bool isOpen;

  const _StatusTrigger({required this.status, required this.isOpen});

  @override
  State<_StatusTrigger> createState() => _StatusTriggerState();
}

class _StatusTriggerState extends State<_StatusTrigger> {
  /// hover:brightness-125 из Svelte.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = statusBadgeClasses(widget.status);
    final isOpen = widget.isOpen;

    // Размеры 1-в-1 с ветками Svelte; stroke-width шрифт-иконки не выражает —
    // единый вес (см. Пояснения в FLUTTER_MIGRATION.md).
    final (IconData icon, double size) = switch (widget.status) {
      MediaStatus.planned => (LucideIcons.bookmark, 20),
      MediaStatus.inProgress => (LucideIcons.play, 20),
      MediaStatus.completed => (LucideIcons.check, 21),
      MediaStatus.onHold => (LucideIcons.pause, 21),
      MediaStatus.dropped => (LucideIcons.x, 20),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 37.28, // h-[2.33rem] w-[2.33rem] @ 16px/rem
        height: 37.28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hovered
              ? Color.alphaBlend(Colors.white.withAlpha(30), colors.background)
              : colors.background,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
          boxShadow: [
            // has-[:popover-open]:ring-2 ring-indigo-400/70 — кольцо
            // 2px вокруг кнопки ТОЛЬКО когда поповер открыт.
            if (isOpen)
              const BoxShadow(
                color: Color(0xB3818CF8), // indigo-400/70 (#818cf8)
                spreadRadius: 2,
              ),
            // shadow-md: 0 4px 6px -1px rgb(0 0 0/0.1), 0 2px 4px -2px rgb(0 0 0/0.1)
            const BoxShadow(
              color: Color(0x1A000000),
              offset: Offset(0, 4),
              blurRadius: 6,
              spreadRadius: -1,
            ),
            const BoxShadow(
              color: Color(0x1A000000),
              offset: Offset(0, 2),
              blurRadius: 4,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Icon(icon, size: size, color: colors.text),
      ),
    );
  }
}
