/// 1:1 port of `mediatracker-ui/src/features/update-progress/statusPromotionToast.svelte.ts`.
///
/// The 0 → 1 promotion toast (rule 1 of the status contract). Progress just
/// moved from 0 to 1 and the status was auto-flipped to InProgress, so the
/// user gets one interactive notice with three persisted outcomes: OK
/// (accept), Undo (full revert) and Keep status (progress stays).
///
/// `toastStore.show` — модуль Фазы 1 (shared/ui/toast), поэтому показ
/// передаётся через инъекцию [StatusPromotionToastShower] (решение #15):
/// Фаза 1 подключит реальный toast, тесты — мок-колбек.
library;

import '../../shared/i18n/index.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';

class StatusPromotionHandlers {
  /// Undo: progress back to 0 AND status back to the previous one — both
  /// persisted.
  final void Function() undo;

  /// Keep-status: progress stays, the previous status is restored — persisted.
  final void Function() keepStatus;

  const StatusPromotionHandlers({required this.undo, required this.keepStatus});
}

/// Спецификация показа интерактивного тоста (эквивалент вызова toastStore.show).
class StatusPromotionToastSpec {
  final String title;
  final String description;
  final String type;
  final int durationMs;
  final bool showOk;
  final void Function() undo;
  final List<StatusPromotionToastAction> actions;

  const StatusPromotionToastSpec({
    required this.title,
    required this.description,
    required this.type,
    required this.durationMs,
    required this.showOk,
    required this.undo,
    required this.actions,
  });
}

class StatusPromotionToastAction {
  final String id;
  final String label;
  final void Function() onClick;

  const StatusPromotionToastAction({
    required this.id,
    required this.label,
    required this.onClick,
  });
}

typedef StatusPromotionToastShower = void Function(StatusPromotionToastSpec spec);

/// `notifyAutoInProgress(item, previousStatus, handlers)` — спецификация
/// показа + инъекция shower.
void notifyAutoInProgress(
  MediaItem item,
  MediaStatus previousStatus, {
  required StatusPromotionHandlers handlers,
  required StatusPromotionToastShower show,
  I18nDictionary? t,
  Locale locale = Locale.ru,
}) {
  final dict = t ?? I18nDictionary(locale);
  show(StatusPromotionToastSpec(
    title: dict.tr('toast.statusAutoChangedTitle'),
    description:
        dict.tf('toast.statusAutoChangedDesc', [item.title.trim().isEmpty ? item.type.wire : item.title.trim()]),
    type: 'info',
    durationMs: 8000,
    showOk: true,
    undo: handlers.undo,
    actions: [
      StatusPromotionToastAction(
        id: 'keepStatus',
        label: dict.tr('toast.keepStatus'),
        onClick: handlers.keepStatus,
      ),
    ],
  ));
}
