/// 1:1 port of `mediatracker-ui/src/entities/media/ui/Placeholder404.svelte`.
///
/// Тонкая обёртка над [MediaCoverPlaceholder]: label опционален, undefined →
/// дефолт `activity.coverMissing` внутри плейсхолдера (1-в-1 с Svelte-пропом).
library;

import 'package:material_ui/material_ui.dart';

import '../../../shared/ui/media_cover_placeholder.dart';

class Placeholder404 extends StatelessWidget {
  final String? label;

  const Placeholder404({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return MediaCoverPlaceholder(label: label);
  }
}
