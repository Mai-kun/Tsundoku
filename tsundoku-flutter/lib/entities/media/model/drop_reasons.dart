/// 1:1 port of `mediatracker-ui/src/entities/media/model/dropReasons.ts`.
library;

class DropReasonOption {
  final String key;
  final String labelRu;
  final String labelEn;
  final String? icon;
  final List<String>? mediaTypes; // если ограничено конкретными типами медиа

  const DropReasonOption({
    required this.key,
    required this.labelRu,
    required this.labelEn,
    this.icon,
    this.mediaTypes,
  });

  String label(String lang) => lang == 'ru' ? labelRu : labelEn;
}

const List<DropReasonOption> dropReasons = <DropReasonOption>[
  // Универсальные:
  DropReasonOption(
      key: 'boring',
      labelRu: 'Скучно / Затянуто',
      labelEn: 'Boring / Dragged out'),
  DropReasonOption(
      key: 'lost_interest',
      labelRu: 'Пропал интерес / Остыл',
      labelEn: 'Lost interest / Grew cold'),
  DropReasonOption(
      key: 'bad_plot',
      labelRu: 'Разочаровал сюжет / Слитый финал',
      labelEn: 'Disappointing plot / Ruined ending'),
  DropReasonOption(
      key: 'annoying_characters',
      labelRu: 'Бесячие персонажи / Клише',
      labelEn: 'Annoying characters / Cliches'),
  DropReasonOption(
      key: 'no_time',
      labelRu: 'Нехватка времени / Усталость',
      labelEn: 'No time / Burnout'),
  // Специфичные для игр (game):
  DropReasonOption(
      key: 'too_hard',
      labelRu: 'Непроходимо / Слишком сложно',
      labelEn: 'Too hard / Unbeatable',
      mediaTypes: ['game']),
  DropReasonOption(
      key: 'grind',
      labelRu: 'Унылый гринд / Однообразие',
      labelEn: 'Tiresome grind / Repetitive',
      mediaTypes: ['game']),
  DropReasonOption(
      key: 'bad_perf',
      labelRu: 'Баги / Плохая оптимизация',
      labelEn: 'Bugs / Poor optimization',
      mediaTypes: ['game']),
  // Специфичные для книг и манги (book, manga):
  DropReasonOption(
      key: 'bad_translation',
      labelRu: 'Ужасный / Машинный перевод',
      labelEn: 'Terrible / Machine translation',
      mediaTypes: ['book', 'manga']),
  DropReasonOption(
      key: 'art_downgrade',
      labelRu: 'Испортилась рисовка',
      labelEn: 'Art downgrade',
      mediaTypes: ['manga']),
  DropReasonOption(
      key: 'abandoned',
      labelRu: 'Заброшено автором / Заморожено',
      labelEn: 'Abandoned / On hiatus',
      mediaTypes: ['book', 'manga']),
  // Специфичные для аниме и сериалов (anime, tvshow):
  DropReasonOption(
      key: 'fillers',
      labelRu: 'Филлеры / Вода',
      labelEn: 'Fillers / Padding',
      mediaTypes: ['tvshow', 'anime']),
  // Другое:
  DropReasonOption(key: 'other', labelRu: 'Другая причина', labelEn: 'Other reason'),
];

final Map<String, DropReasonOption> _reasonMap = <String, DropReasonOption>{
  for (final reason in dropReasons) reason.key: reason,
};

List<DropReasonOption> getDropReasonsForMediaType(String? mediaType,
    {bool? isAnime}) {
  if (mediaType == null) return [...dropReasons];
  final normalizedType = mediaType.toLowerCase();

  return dropReasons.where((option) {
    final types = option.mediaTypes;
    if (types == null || types.isEmpty) return true;
    if (types.contains(normalizedType)) return true;
    if (isAnime == true && types.contains('anime')) return true;
    return false;
  }).toList();
}

String getDropReasonLabel(String key, {String lang = 'ru'}) {
  if (key.isEmpty || key == 'unspecified') {
    return lang == 'ru' ? 'Не указана' : 'Not specified';
  }
  final option = _reasonMap[key];
  if (option != null) {
    return option.label(lang).isNotEmpty ? option.label(lang) : option.labelRu;
  }
  return key;
}
