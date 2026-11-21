/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/externalMapping.ts`.
///
/// Форма relation от сервера → view-model. Провайдерский вызов, GraphQL и
/// нормализация полей — на сервере; здесь только shaping view-model,
/// намеренно без i18n — вызывающий передаёт локализованный `relationType`.
library;

import '../../shared/types/index.dart' show ExternalRelation;
import 'detail_types.dart';

/// Серверная relation → RelatedEntry для UI related-таба.
RelatedEntry toRelatedEntry(ExternalRelation relation) {
  final media = relation.media;
  final score = media.rating;

  return RelatedEntry(
    id: media.externalId,
    rawRelationType: relation.relationType,
    title: media.title.isNotEmpty ? media.title : 'Title',
    originalTitle: media.originalTitle,
    romajiTitle: media.romajiTitle,
    coverUrl: media.coverUrl,
    type: media.type,
    format: media.format,
    year: media.releaseYear,
    releaseDate: media.releaseDate,
    endDate: media.endDate,
    releaseStatus: media.releaseStatus,
    score: score,
    ratings: (score != null && score > 0 && media.externalSource != null)
        ? [RatingBadge(source: media.externalSource!, score: score)]
        : null,
    description: media.description,
    trailerVideoId: media.trailerVideoId,
    duration: media.runtimeMinutes,
    episodes: media.totalCount,
    chapters: media.chapters,
    volumes: media.volumes,
    studio: media.studio,
    author: media.author,
    externalSource: media.externalSource,
  );
}
