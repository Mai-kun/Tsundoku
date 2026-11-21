/// 1:1 port of `mediatracker-ui/src/shared/ui/Panel.svelte`.
///
/// bg-panel-line resolves through --color-panel-line → --bg-surface, so panels
/// repaint correctly under a future theme override.
/// `.panel` CSS: rounded-xl (12), border-subtle, bg-panel-line, p-4,
/// shadow-md; margin-bottom 1rem → внешние отступы решает вызывающий layout.
library;

import 'package:material_ui/material_ui.dart';
import '../theme/tsundoku_tokens.dart';
import '../theme/tsundoku_theme.dart';


class TsundokuPanel extends StatelessWidget {
  final Widget child;

  const TsundokuPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        color: th.bgSurface, // bg-panel-line → --bg-surface
        borderRadius:
            BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
        border: Border.all(color: th.borderSubtle),
        boxShadow: const [
          // shadow-md: 0 4px 6px -1px rgb(0 0 0/0.1), 0 2px 4px -2px rgb(0 0 0/0.1)
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 4),
            blurRadius: 6,
            spreadRadius: -1,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 2),
            blurRadius: 4,
            spreadRadius: -2,
          ),
        ],
      ),
      child: child,
    );
  }
}
