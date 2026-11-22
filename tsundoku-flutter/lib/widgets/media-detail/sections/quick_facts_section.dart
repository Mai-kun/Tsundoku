/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/QuickFactsSection.svelte`.
///
/// Быстрые факты: чипы тип/язык/страна/статус/объём. Intl.DisplayNames в
/// Dart отсутствует — статичные карты языков (как в Svelte-литералах) и
/// регионов, фолбэк на сырой код; флаги — regional-indicator по codePoint
/// (решение #50).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';

/// Названия языков (1-в-1 с картой Svelte) + региональный фолбэк.
const Map<String, String> _languageNames = {
  'en': 'English',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'ru': 'Russian',
  'fr': 'French',
  'es': 'Spanish',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
};

const Map<String, String> _languageFlags = {
  'en': '🇺🇸',
  'ja': '🇯🇵',
  'ko': '🇰🇷',
  'zh': '🇨🇳',
  'ru': '🇷🇺',
  'fr': '🇫🇷',
  'es': '🇪🇸',
  'de': '🇩🇪',
  'it': '🇮🇹',
  'pt': '🇵🇹',
};

/// Распространённые регионы (Intl.DisplayNames недоступен — решение #50).
const Map<String, String> _regionNames = {
  'US': 'США',
  'JP': 'Япония',
  'KR': 'Южная Корея',
  'CN': 'Китай',
  'RU': 'Россия',
  'FR': 'Франция',
  'ES': 'Испания',
  'DE': 'Германия',
  'IT': 'Италия',
  'PT': 'Португалия',
  'GB': 'Великобритания',
  'CA': 'Канада',
};

/// Флаг из ISO-кода (regional indicator symbols, 127397 + код символа).
String _flagFromCode(String code) {
  if (code.length != 2) return '';
  return String.fromCharCodes(
      code.codeUnits.map((c) => 127397 + c));
}

/// Русская плюрализация (1-в-1 с counted()).
String counted(
  int count,
  String enSingular,
  String enPlural,
  String ruSingular,
  String ruFew,
  String ruMany, {
  required String localeWire,
}) {
  if (localeWire == 'en') {
    return '$count ${count == 1 ? enSingular : enPlural}';
  }
  final lastTwo = count % 100;
  final last = count % 10;
  final word = (lastTwo >= 11 && lastTwo <= 14)
      ? ruMany
      : last == 1
          ? ruSingular
          : (last >= 2 && last <= 4)
              ? ruFew
              : ruMany;
  return '$count $word';
}

/// Быстрые факты (1-в-1 с QuickFactsSection.svelte).
class QuickFactsSection extends ConsumerWidget {
  final MediaDetail media;

  const QuickFactsSection({super.key, required this.media});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);

    final typeWire = media.type.wire;
    String typeLabel;
    if (typeWire == 'game') {
      typeLabel = t.tr('detail.formatGame');
    } else if (typeWire == 'book') {
      typeLabel = t.tr('detail.formatBook');
    } else if (typeWire == 'manga') {
      typeLabel = t.tr('detail.formatManga');
    } else if ((typeWire == 'movie' || typeWire == 'tvshow') &&
        (media.isAnime ?? false)) {
      typeLabel = t.tr('detail.formatAnime');
    } else {
      typeLabel =
          typeWire == 'movie' ? t.tr('detail.formatMovie') : t.tr('detail.formatSeries');
    }

    String? statusLabel;
    final status = media.releaseStatus?.replaceAll('_', ' ').trim().toLowerCase();
    if (status != null && status.isNotEmpty) {
      if (status == 'releasing' ||
          status == 'returning series' ||
          status == 'ongoing') {
        statusLabel = t.tr('detail.statusOngoing');
      } else if (status == 'finished' ||
          status == 'ended' ||
          status == 'released') {
        statusLabel = t.tr('detail.statusFinished');
      } else if (status == 'not yet released' ||
          status == 'planned' ||
          status == 'announced' ||
          status == 'upcoming') {
        statusLabel = t.tr('detail.statusAnnounced');
      } else {
        statusLabel = media.releaseStatus;
      }
    }

    String? measure;
    if (typeWire == 'movie' && (media.durationMinutes ?? 0) > 0) {
      measure = '${media.durationMinutes} ${t.tr('detail.minShort')}';
    } else if (typeWire == 'tvshow' &&
        media.durationMinutes != null &&
        media.durationMinutes! > 0) {
      measure = '${media.durationMinutes} ${t.tr('detail.minPerEp')}';
    } else if (typeWire == 'book' && (media.totalPages ?? 0) > 0) {
      measure = counted(media.totalPages ?? 0, 'page', 'pages', 'страница',
          'страницы', 'страниц',
          localeWire: locale.wire);
    } else if (typeWire == 'manga') {
      final parts = <String>[
        if (media.totalVolumes != null && media.totalVolumes! > 0)
          counted(media.totalVolumes!, 'volume', 'volumes', 'том', 'тома',
              'томов',
              localeWire: locale.wire),
        if (media.totalChapters != null && media.totalChapters! > 0)
          counted(media.totalChapters!, 'chapter', 'chapters', 'глава',
              'главы', 'глав',
              localeWire: locale.wire),
      ];
      measure = parts.isNotEmpty ? parts.join(' · ') : null;
    } else if (typeWire == 'tvshow' && media.totalEpisodesCount != null && media.totalEpisodesCount! > 0) {
      measure = counted(media.totalEpisodesCount!, 'episode', 'episodes',
          'серия', 'серии', 'серий',
          localeWire: locale.wire);
    } else if (typeWire == 'game' && media.hoursPlayed != null && media.hoursPlayed! > 0) {
      measure = counted(media.hoursPlayed!, 'hour', 'hours', 'час', 'часа',
          'часов',
          localeWire: locale.wire);
    }

    // Язык: карта литералов → фолбэк на сырой код (Intl.DisplayNames ⏭️).
    String? language;
    final langValue = media.originalLanguage?.trim();
    if (langValue != null && langValue.isNotEmpty) {
      final code = langValue.toLowerCase();
      final name = _languageNames[code] ?? langValue;
      final flag = _languageFlags[code];
      language = flag != null ? '$flag $name' : name;
    }

    // Страна: карта регионов → фолбэк код; флаг по codePoint.
    String? country;
    final countryValue = media.countryOfOrigin?.trim().toUpperCase();
    if (countryValue != null && countryValue.isNotEmpty) {
      final name = _regionNames[countryValue] ?? countryValue;
      final flag = _flagFromCode(countryValue);
      country = flag.isNotEmpty ? '$flag $name' : name;
    }

    final chips = <String>[
      typeLabel,
      ?language,
      ?country,
      ?statusLabel,
      ?measure,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.tr('detail.quickFacts').toUpperCase(),
          style: TextStyle(
            fontSize: 12, // text-xs
            fontWeight: FontWeight.w600, // font-semibold
            letterSpacing: 1.68, // tracking-[0.14em]
            color: th.textMuted, // text-muted
          ),
        ),
        const SizedBox(height: 8), // space-y-2
        Wrap(
          spacing: 8, // gap-2
          runSpacing: 8,
          children: [
            for (final chip in chips)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6), // px-3 py-1.5
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  border: Border.all(
                      color: Colors.white.withAlpha(13)), // border-white/5
                  color: th.bgSurface.withAlpha(153), // bg-surface/60
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: th.textMuted, // text-muted
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
