/// 1:1 port of `mediatracker-ui/src/entities/media/model/mediaLabels.ts`.
///
/// statusBadgeClasses/sourceBadgeClasses (CSS-строки) → типизированные
/// [MediaStatusBadgeColors] / [SourceBadgeColors] с hex-значениями 1-в-1 из
/// CSS (решение #13); потребители (Фаза 2) собирают BoxDecoration из них.
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Color, IconData;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/types/enums.dart';
import '../../../shared/types/models.dart';

String statusLabel(MediaStatus status, I18nDictionary t) {
  switch (status) {
    case MediaStatus.planned:
      return t.tr('status.planned');
    case MediaStatus.inProgress:
      return t.tr('status.inProgress');
    case MediaStatus.completed:
      return t.tr('status.completed');
    case MediaStatus.onHold:
      return t.tr('status.paused');
    case MediaStatus.dropped:
      return t.tr('status.dropped');
  }
}

@immutable
class MediaStatusBadgeColors {
  final Color border;
  final Color background;
  final Color text;

  const MediaStatusBadgeColors({
    required this.border,
    required this.background,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      other is MediaStatusBadgeColors &&
      other.border == border &&
      other.background == background &&
      other.text == text;

  @override
  int get hashCode => Object.hash(border, background, text);
}

/// CSS-классы badge-ов → цвета (hex 1-в-1 из Tailwind-значений app.css).
const MediaStatusBadgeColors _inProgressColors = MediaStatusBadgeColors(
  border: Color(0x545446CF), // border-accent-bright/50
  background: Color(0x4D5446CF), // bg-accent-bright/30
  text: Color(0xFFA5B4FC), // text-[#a5b4fc]
);

const MediaStatusBadgeColors _completedColors = MediaStatusBadgeColors(
  border: Color(0x80047950), // border-emerald-700/50 (Tailwind emerald-700)
  background: Color(0xCC052E1A), // bg-emerald-950/80
  text: Color(0xFF6EE7B7), // text-emerald-300
);

const MediaStatusBadgeColors _onHoldColors = MediaStatusBadgeColors(
  border: Color(0x80B45309), // border-amber-700/50
  background: Color(0xCC451A03), // bg-amber-950/80
  text: Color(0xFFFCD34D), // text-amber-300
);

const MediaStatusBadgeColors _droppedColors = MediaStatusBadgeColors(
  border: Color(0x80BE123C), // border-rose-700/50
  background: Color(0xCC4C0519), // bg-rose-950/80
  text: Color(0xFFFDA4AF), // text-rose-300
);

const MediaStatusBadgeColors _defaultColors = MediaStatusBadgeColors(
  border: Color(0x803F3F46), // border-zinc-700/50
  background: Color(0xCC27272A), // bg-zinc-800/80
  text: Color(0xFFD4D4D8), // text-zinc-300
);

MediaStatusBadgeColors statusBadgeClasses(MediaStatus status) {
  switch (status) {
    case MediaStatus.inProgress:
      return _inProgressColors;
    case MediaStatus.completed:
      return _completedColors;
    case MediaStatus.onHold:
      return _onHoldColors;
    case MediaStatus.dropped:
      return _droppedColors;
    case MediaStatus.planned:
      return _defaultColors;
  }
}

String cardTypeLabel(MediaItem media, I18nDictionary t) {
  if (media.type == MediaType.tvshow && (media.isAnime ?? false)) {
    return t.tr('navigation.anime');
  }
  return t.tr('types.${media.type.wire}');
}

/// `new Intl.NumberFormat(i18n.current).format(value)`.
String formatNumber(num value, Locale locale) =>
    NumberFormat.decimalPattern(locale.wire).format(value);

String titleTooltip(String title) =>
    title.length > 100 ? '${title.substring(0, 97)}...' : title;

@immutable
class SourceBadgeColors {
  final Color border;
  final Color background;
  final Color text;

  const SourceBadgeColors({
    required this.border,
    required this.background,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      other is SourceBadgeColors &&
      other.border == border &&
      other.background == background &&
      other.text == text;

  @override
  int get hashCode => Object.hash(border, background, text);
}

Color _rgb(int r, int g, int b, [double a = 1.0]) =>
    Color.fromRGBO(r, g, b, a);

/// Per-source badge colours. Lives here because three views show them: the
/// library detail header, its sidebar rows and the search preview.
SourceBadgeColors sourceBadgeClasses(String src) {
  final source = src.toLowerCase();
  if (source.contains('anilist')) {
    return SourceBadgeColors(
      border: _rgb(2, 169, 255, 0.3),
      background: _rgb(2, 169, 255, 0.15),
      text: _rgb(2, 169, 255),
    );
  }
  if (source.contains('sociallib') ||
      source.contains('ranobelib') ||
      source.contains('mangalib') ||
      source.contains('animelib') ||
      source.contains('slashlib') ||
      source.contains('hentailib')) {
    return SourceBadgeColors(
      border: _rgb(236, 72, 153, 0.3),
      background: _rgb(236, 72, 153, 0.15),
      text: _rgb(244, 114, 182),
    );
  }
  if (source.contains('shikimori')) {
    return SourceBadgeColors(
      border: _rgb(46, 81, 162, 0.4),
      background: _rgb(46, 81, 162, 0.2),
      text: _rgb(104, 140, 228),
    );
  }
  if (source.contains('mangadex')) {
    return SourceBadgeColors(
      border: _rgb(255, 103, 64, 0.3),
      background: _rgb(255, 103, 64, 0.15),
      text: _rgb(255, 103, 64),
    );
  }
  if (source.contains('myanimelist') ||
      source.contains('jikan') ||
      source.contains('mal')) {
    return SourceBadgeColors(
      border: _rgb(46, 81, 162, 0.4),
      background: _rgb(46, 81, 162, 0.2),
      text: _rgb(125, 155, 240),
    );
  }
  if (source.contains('tmdb')) {
    return SourceBadgeColors(
      border: _rgb(1, 180, 228, 0.3),
      background: _rgb(1, 180, 228, 0.15),
      text: _rgb(49, 195, 239),
    );
  }
  if (source.contains('rawg')) {
    return SourceBadgeColors(
      border: _rgb(246, 94, 34, 0.3),
      background: _rgb(246, 94, 34, 0.15),
      text: _rgb(247, 144, 105),
    );
  }
  if (source.contains('steam')) {
    return SourceBadgeColors(
      border: _rgb(27, 40, 56, 0.6),
      background: _rgb(27, 40, 56, 0.7),
      text: _rgb(102, 192, 244),
    );
  }
  if (source.contains('igdb')) {
    return SourceBadgeColors(
      border: _rgb(145, 70, 255, 0.3),
      background: _rgb(145, 70, 255, 0.15),
      text: _rgb(177, 140, 255),
    );
  }
  if (source.contains('kitsu')) {
    return SourceBadgeColors(
      border: _rgb(253, 117, 92, 0.3),
      background: _rgb(253, 117, 92, 0.15),
      text: _rgb(255, 154, 134),
    );
  }
  if (source.contains('simkl')) {
    return SourceBadgeColors(
      border: _rgb(255, 255, 255, 0.14),
      background: _rgb(0, 0, 0, 0.5),
      text: _rgb(255, 255, 255),
    );
  }
  if (source.contains('imdb')) {
    return SourceBadgeColors(
      border: _rgb(245, 197, 24, 0.3),
      background: _rgb(245, 197, 24, 0.15),
      text: _rgb(245, 197, 24),
    );
  }
  if (source.contains('thetvdb') || source.contains('tvdb')) {
    return SourceBadgeColors(
      border: _rgb(66, 184, 131, 0.3),
      background: _rgb(66, 184, 131, 0.15),
      text: _rgb(92, 199, 154),
    );
  }
  if (source.contains('mangaupdate')) {
    return SourceBadgeColors(
      border: _rgb(59, 130, 246, 0.3),
      background: _rgb(59, 130, 246, 0.15),
      text: _rgb(96, 165, 250),
    );
  }
  if (source.contains('openlibrary')) {
    return SourceBadgeColors(
      border: _rgb(225, 217, 203, 0.25),
      background: _rgb(225, 217, 203, 0.1),
      text: _rgb(225, 217, 203),
    );
  }
  return SourceBadgeColors(
    border: _rgb(255, 255, 255, 0.12),
    background: _rgb(18, 21, 28), // var(--color-panel-line) = --bg-surface
    text: _rgb(251, 191, 36), // text-amber-400
  );
}

/// Иконка событием истории не является — источник: lucide (для избежания
/// tree-shaking warnings пакет подключён здесь явно).
// ignore: unused_element
const IconData _lucideAnchor = LucideIcons.bookmark;
