/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/tabs/RelatedTab.svelte`.
///
/// Таб «Связанное» — тонкая обёртка над RelatedPanel (вся логика там).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/types/index.dart';
import '../detail_types.dart';
import '../panels/related_panel.dart';

/// Таб «Связанное» (1-в-1 с RelatedTab.svelte).
class RelatedTab extends ConsumerWidget {
  final MediaItem media;
  final List<RelatedEntry> related;
  final bool loading;
  final Object? error;
  final RelatedViewMode viewMode;
  final List<RelationGroup> groups;
  final List<TimelineEntry> timeline;
  final VoidCallback onRetry;
  final void Function(RelatedViewMode mode) onSelectViewMode;

  /// Открывает локальный тайтл или превью-модал внешнего.
  final void Function(RelatedEntry entry) onOpen;
  final void Function(String source, {bool force}) onLoadFrom;

  const RelatedTab({
    super.key,
    required this.media,
    this.related = const [],
    this.loading = false,
    this.error,
    this.viewMode = RelatedViewMode.grouped,
    this.groups = const [],
    this.timeline = const [],
    required this.onRetry,
    required this.onSelectViewMode,
    required this.onOpen,
    required this.onLoadFrom,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RelatedPanel(
      media: media,
      related: related,
      loading: loading,
      error: error,
      viewMode: viewMode,
      groups: groups,
      timeline: timeline,
      onRetry: onRetry,
      onSelectViewMode: onSelectViewMode,
      onOpen: onOpen,
      onLoadFrom: onLoadFrom,
    );
  }
}
