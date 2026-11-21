/// 1:1 port of `mediatracker-ui/src/widgets/media-card/MediaCard.svelte`.
///
/// Диспетчер по типу медиа: Game/Book/Manga/Movie → соответствующая карточка,
/// остальное (tvshow) → TvShowCard. TS `{...rest}`-спред → единый
/// [MediaCardProps] (решение #33).
library;

import 'package:material_ui/material_ui.dart';

import '../../shared/types/enums.dart' show MediaType;
import '../../shared/types/models.dart';
import 'book_card.dart';
import 'card_types.dart';
import 'game_card.dart';
import 'manga_card.dart';
import 'movie_card.dart';
import 'tv_show_card.dart';

class MediaCard extends StatelessWidget {
  final MediaCardProps props;

  const MediaCard({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final MediaItem item = props.item;
    switch (item.type) {
      case MediaType.game:
        return GameCard(props: props);
      case MediaType.book:
        return BookCard(props: props);
      case MediaType.manga:
        return MangaCard(props: props);
      case MediaType.movie:
        return MovieCard(props: props);
      case MediaType.tvshow:
        return TvShowCard(props: props);
    }
  }
}
