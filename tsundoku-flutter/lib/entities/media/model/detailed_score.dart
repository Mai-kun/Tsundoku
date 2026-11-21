/// 1:1 port of `mediatracker-ui/src/entities/media/model/detailedScore.ts`.
library;

import 'dart:convert';

const List<String> criterionKeys = <String>[
  'story',
  'visuals',
  'characters',
  'sound',
  'pacing',
  'gameplay',
  'writing',
  'enjoyment',
];

bool isCriterionKey(String key) => criterionKeys.contains(key);

/// `DetailedScoreMap = Partial<Record<CriterionKey, number>>`.
typedef DetailedScoreMap = Map<String, int>;

/// Ось одного критерия с ru/en-подписью (1-в-1 с CriterionAxis).
class CriterionAxis {
  final String key;
  final String labelRu;
  final String labelEn;

  const CriterionAxis({
    required this.key,
    required this.labelRu,
    required this.labelEn,
  });

  String label(String lang) => lang == 'ru' ? labelRu : labelEn;
}

const List<CriterionAxis> gameAxes = <CriterionAxis>[
  CriterionAxis(key: 'gameplay', labelRu: 'Геймплей', labelEn: 'Gameplay'),
  CriterionAxis(key: 'story', labelRu: 'Сюжет и мир', labelEn: 'Story & Lore'),
  CriterionAxis(key: 'visuals', labelRu: 'Графика и арт', labelEn: 'Visuals & Art'),
  CriterionAxis(key: 'sound', labelRu: 'Музыка и звук', labelEn: 'Sound & OST'),
  CriterionAxis(key: 'enjoyment', labelRu: 'Удовольствие', labelEn: 'Enjoyment'),
];

const List<CriterionAxis> bookAxes = <CriterionAxis>[
  CriterionAxis(key: 'story', labelRu: 'Сюжет', labelEn: 'Story'),
  CriterionAxis(key: 'characters', labelRu: 'Персонажи', labelEn: 'Characters'),
  CriterionAxis(key: 'writing', labelRu: 'Слог и стиль', labelEn: 'Writing Style'),
  CriterionAxis(key: 'pacing', labelRu: 'Динамика', labelEn: 'Pacing'),
  CriterionAxis(key: 'enjoyment', labelRu: 'Впечатление', labelEn: 'Impact'),
];

const List<CriterionAxis> mangaAxes = <CriterionAxis>[
  CriterionAxis(key: 'story', labelRu: 'Сюжет', labelEn: 'Story'),
  CriterionAxis(key: 'visuals', labelRu: 'Рисовка', labelEn: 'Art'),
  CriterionAxis(key: 'characters', labelRu: 'Персонажи', labelEn: 'Characters'),
  CriterionAxis(key: 'pacing', labelRu: 'Динамика', labelEn: 'Pacing'),
  CriterionAxis(key: 'enjoyment', labelRu: 'Атмосфера', labelEn: 'Enjoyment'),
];

const List<CriterionAxis> screenAxes = <CriterionAxis>[
  CriterionAxis(key: 'story', labelRu: 'Сюжет', labelEn: 'Story'),
  CriterionAxis(key: 'visuals', labelRu: 'Визуал', labelEn: 'Visuals'),
  CriterionAxis(key: 'characters', labelRu: 'Персонажи', labelEn: 'Characters'),
  CriterionAxis(key: 'sound', labelRu: 'Звук и ОСТ', labelEn: 'Sound & OST'),
  CriterionAxis(key: 'pacing', labelRu: 'Динамика', labelEn: 'Pacing'),
];

List<CriterionAxis> getCriteriaAxes(String type) {
  final rawType = type.toLowerCase();
  if (rawType == 'game') return gameAxes;
  if (rawType == 'book') return bookAxes;
  if (rawType == 'manga') return mangaAxes;
  return screenAxes;
}

DetailedScoreMap parseDetailedScore(String? json) {
  if (json == null || json.isEmpty) return <String, int>{};
  dynamic parsed;
  try {
    parsed = jsonDecode(json);
  } catch (_) {
    return <String, int>{};
  }
  if (parsed is! Map<String, dynamic>) return <String, int>{};

  final result = <String, int>{};
  parsed.forEach((key, val) {
    if (isCriterionKey(key) && val is num && val.isFinite) {
      final rounded = val.round();
      if (rounded >= 1 && rounded <= 10) {
        result[key] = rounded;
      }
    }
  });
  return result;
}

String? serializeDetailedScore(DetailedScoreMap map) {
  if (map.isEmpty) return null;
  final clean = <String, int>{};
  map.forEach((key, val) {
    if (isCriterionKey(key) && val >= 1 && val <= 10) {
      clean[key] = val;
    }
  });
  if (clean.isEmpty) return null;
  return jsonEncode(clean);
}

/// `{ exact, rounded, count }` или null при пустой карте.
class DetailedAverage {
  final double exact;
  final int rounded;
  final int count;

  const DetailedAverage({
    required this.exact,
    required this.rounded,
    required this.count,
  });

  @override
  bool operator ==(Object other) =>
      other is DetailedAverage &&
      other.exact == exact &&
      other.rounded == rounded &&
      other.count == count;

  @override
  int get hashCode => Object.hash(exact, rounded, count);
}

DetailedAverage? computeDetailedAverage(DetailedScoreMap map) {
  var sum = 0;
  var count = 0;
  map.forEach((key, val) {
    if (isCriterionKey(key) && val >= 1 && val <= 10) {
      sum += val;
      count++;
    }
  });
  if (count == 0) return null;
  final avg = sum / count;
  final exact = (avg * 10).roundToDouble() / 10;
  final rounded = (avg.round()).clamp(1, 10);
  return DetailedAverage(exact: exact, rounded: rounded, count: count);
}
