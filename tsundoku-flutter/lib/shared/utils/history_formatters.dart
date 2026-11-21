/// 1:1 port of `mediatracker-ui/src/shared/utils/historyFormatters.ts`.
///
/// Форматтеры истории: статусы/оценки/события — 1-в-1; `i18n.t` → параметр
/// [I18nDictionary] (t); `Intl.DateTimeFormat` → `DateFormat` из intl с
/// локалью ru/en (решение #11). HISTORY_EVENT_ICONS → IconData из
/// lucide_icons_flutter (Icons.ts ⏭️ заменён нативно).
library;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart' show IconData;

import '../i18n/index.dart';
import '../types/enums.dart';
import '../types/models.dart';

String formatStatusName(String? status, I18nDictionary t) {
  if (status == null || status.isEmpty) return '—';
  switch (status) {
    case 'Planned':
    case '0':
      return t.tr('status.planned');
    case 'InProgress':
    case '1':
      return t.tr('status.inProgress');
    case 'Completed':
    case '2':
      return t.tr('status.completed');
    case 'OnHold':
    case '3':
      return t.tr('status.paused');
    case 'Dropped':
    case '4':
      return t.tr('status.dropped');
    default:
      return status;
  }
}

String formatScoreName(String? score, I18nDictionary t) {
  if (score == null || score.isEmpty || score == '0') return '—';
  return '$score ★';
}

String formatHistoryEventLabel(HistoryEvent event, I18nDictionary t) {
  switch (event.type) {
    case HistoryEventType.added:
      return t.tr('views.titleAdded');

    case HistoryEventType.deleted:
      return t.tr('views.titleDeleted');

    case HistoryEventType.statusChanged:
      final oldStatus = formatStatusName(event.oldValue, t);
      final newStatus = formatStatusName(event.newValue, t);
      return '${t.tr('views.statusPrefix')} $oldStatus → $newStatus';

    case HistoryEventType.scoreChanged:
      final oldScore = formatScoreName(event.oldValue, t);
      final newScore = formatScoreName(event.newValue, t);
      return '${t.tr('views.scorePrefix')} $oldScore → $newScore';

    case HistoryEventType.progressChanged:
      final isPages =
          (event.oldValue?.contains('стр') ?? false) ||
              (event.oldValue?.contains('pp') ?? false) ||
              (event.oldValue?.contains('page') ?? false) ||
              (event.newValue?.contains('стр') ?? false) ||
              (event.newValue?.contains('pp') ?? false) ||
              (event.newValue?.contains('page') ?? false);
      final prefix =
          isPages ? t.tr('views.readPrefix') : t.tr('views.progressPrefix');

      if (event.oldValue != null && event.newValue != null) {
        return '$prefix ${event.oldValue} → ${event.newValue}';
      }
      if (event.newValue != null) {
        return '$prefix ${event.newValue}';
      }
      return prefix;

    case HistoryEventType.achievementUnlocked:
      return '${t.tr('stats.achievements')} ${event.newValue ?? ''}'.trim();
  }
}

/// HISTORY_EVENT_ICONS: HistoryEventType → IconData (lucide 1-в-1).
const Map<HistoryEventType, IconData> historyEventIcons =
    <HistoryEventType, IconData>{
  HistoryEventType.added: LucideIcons.plus,
  HistoryEventType.statusChanged: LucideIcons.flag,
  HistoryEventType.scoreChanged: LucideIcons.star,
  HistoryEventType.progressChanged: LucideIcons.play,
  HistoryEventType.deleted: LucideIcons.trash2,
  HistoryEventType.achievementUnlocked: LucideIcons.star,
};

String formatHistoryTime(String value, Locale locale) {
  return _dateFormat(locale, 'HH:mm').format(DateTime.parse(value));
}

String formatHistoryDate(String value, Locale locale) {
  return _dateFormat(locale, 'yMMMMd').format(DateTime.parse(value));
}

DateFormat _dateFormat(Locale locale, String pattern) {
  // Данные локалей инициализируются один раз (intl требует для ru).
  initializeDateFormatting(locale.wire, null);
  return DateFormat(pattern, locale.wire);
}
