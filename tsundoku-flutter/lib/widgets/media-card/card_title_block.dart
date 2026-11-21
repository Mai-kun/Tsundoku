/// 1:1 port of `mediatracker-ui/src/widgets/media-card/CardTitleBlock.svelte`.
///
/// Заголовок + единственная приглушённая строка (платформа/автор/тип).
/// TS-проп `onOpen` объявлен, но не деструктурируется в let {…} — мёртвый API,
/// не переносился (аналог решения #28).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/media_labels.dart';

class CardTitleBlock extends ConsumerWidget {
  final String title;

  /// Platform, author, media type — the single muted line under the title.
  final String subtitle;

  const CardTitleBlock({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, // min-w-0 (обрезка в flex)
      children: [
        Tooltip(
          // title={titleTooltip(title)}
          message: titleTooltip(title),
          child: Text(
            title,
            maxLines: 2, // line-clamp-2
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14, // text-sm
              height: 1.25, // leading-tight
              fontWeight: FontWeight.w600, // font-semibold
              color: Colors.white,
              shadows: [
                // drop-shadow-sm: 0 1px 1px rgb(0 0 0 / 0.05)
                Shadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 1),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2), // mt-0.5
          child: Text(
            subtitle,
            maxLines: 1, // line-clamp-1
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12, // text-xs
              color: Colors.white.withAlpha(153), // text-white/60
            ),
          ),
        ),
      ],
    );
  }
}
