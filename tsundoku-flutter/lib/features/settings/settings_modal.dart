/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte`.
///
/// Модальное окно настроек (размер xl): может открываться как оверлей-модалка
/// с заголовком и кнопкой закрытия, так и работать во встроенном режиме
/// `embedded: true` (полноэкранный SettingsView). Поддерживает выбор 10 вкладок:
/// источники, поиск, бэкап, импорт, читалка, обновления, хранилище, внешний вид,
/// десктопные настройки и API-токены.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../shared/ui/modal.dart';
import '../../views/settings_view.dart';

class SettingsModal extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback? onImportCompleted;
  final ValueChanged<String>? onNavigateToList;
  final void Function(String sourceId, String? type)? onTestSearch;
  final bool embedded;
  final SettingsTab initialTab;

  const SettingsModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.onImportCompleted,
    this.onNavigateToList,
    this.onTestSearch,
    this.embedded = false,
    this.initialTab = SettingsTab.sources,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!embedded && !isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);

    final innerContent = SettingsView(
      initialTab: initialTab,
      onImportCompleted: onImportCompleted,
      onNavigateToList: onNavigateToList,
      onTestSearch: onTestSearch,
    );

    if (embedded) {
      return innerContent;
    }

    return TsundokuModal(
      isOpen: isOpen,
      onClose: onClose,
      size: ModalSize.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0x266366F1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.settings,
                        size: 20,
                        color: Color(0xFFA5B4FC),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t.tr('settingsModal.title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  color: const Color(0xFF94A3B8),
                  hoverColor: const Color(0x1AFFFFFF),
                  tooltip: t.tr('common.close'),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Body: SettingsView inside scroll/panel
          Expanded(
            child: innerContent,
          ),
        ],
      ),
    );
  }
}
