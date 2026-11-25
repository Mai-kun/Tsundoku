/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/PeopleSizeToggle.svelte`.
///
/// Иконочный переключатель компактного/крупного вида карточек людей;
/// cast и staff хранят размер отдельно (uiSettings).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/utils/ui_settings.dart';

/// Какой блок управляет переключателем (размеры хранятся раздельно).
enum PeopleBlock { cast, staff }

/// Переключатель размера карточек людей (1-в-1 с PeopleSizeToggle.svelte).
class PeopleSizeToggle extends ConsumerWidget {
  /// Storage key (media category): anime / manga / movie / tvshow / game / book.
  final String category;
  final PeopleBlock block;

  const PeopleSizeToggle({
    super.key,
    required this.category,
    required this.block,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final settings = ref.watch(uiSettingsProvider);

    // getCastSize/getStaffSize живут на контроллере; состояние берём из
    // стейт-карт (реактивный watch) — по умолчанию крупный вид (large).
    PeopleCardSize sizeFor(PeopleSizeMap map) =>
        map[category] ?? PeopleCardSize.large;
    final isLarge = block == PeopleBlock.cast
        ? sizeFor(settings.castSizeByCategory) == PeopleCardSize.large
        : sizeFor(settings.staffSizeByCategory) == PeopleCardSize.large;

    Future<void> setSize(PeopleCardSize size) async {
      final notifier = ref.read(uiSettingsProvider.notifier);
      if (block == PeopleBlock.cast) {
        await notifier.setCastSize(category, size);
      } else {
        await notifier.setStaffSize(category, size);
      }
    }

    return Container(
      padding: const EdgeInsets.all(2), // p-0.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(color: Colors.white.withAlpha(21)), // /[0.08]
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(
            icon: LucideIcons.list,
            tooltip: t.tr('detail.compactViewTooltip'),
            active: !isLarge, // aria-pressed={!isLarge}
            activeColor: th.accent,
            th: th,
            onTap: () => setSize(PeopleCardSize.compact),
          ),
          const SizedBox(width: 2), // gap-0.5
          _ToggleChip(
            icon: LucideIcons.layoutGrid,
            tooltip: t.tr('detail.largeViewTooltip'),
            active: isLarge,
            activeColor: th.accent,
            th: th,
            onTap: () => setSize(PeopleCardSize.large),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.th,
    required this.onTap,
  });

  @override
  State<_ToggleChip> createState() => _ToggleChipState();
}

class _ToggleChipState extends State<_ToggleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        selected: widget.active, // aria-pressed
        label: widget.tooltip, // aria-label
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 24, // size-6
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
                color: widget.active
                    ? widget.activeColor // bg-accent
                    : _hovered
                        ? Colors.white.withAlpha(13) // hover:bg-white/5
                        : Colors.transparent,
              ),
              child: Icon(
                widget.icon,
                size: 14,
                color: widget.active
                    ? Colors.white // text-white
                    : _hovered
                        ? Colors.white // hover:text-white
                        : widget.th.textMuted, // text-muted
              ),
            ),
          ),
        ),
      ),
    );
  }
}
