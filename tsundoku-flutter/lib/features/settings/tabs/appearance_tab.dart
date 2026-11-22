/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "appearance").
///
/// Вкладка «Внешний вид»:
/// - Выбор иконки приложения (Основная Tsundoku / Альтернативная)
/// - Превью акцентных тем (Coming Soon)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/utils/ui_settings.dart';

class AppearanceTab extends ConsumerWidget {
  const AppearanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final uiSettings = ref.watch(uiSettingsProvider);
    final currentLocale = ref.watch(i18nProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Description
            Text(
              t.tr('settingsModal.appearance.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.appearance.description'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: 24),

            // 1. Language Selector
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentLocale == Locale.ru ? 'Язык интерфейса' : 'Interface Language',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentLocale == Locale.ru
                        ? 'Выберите основной язык для элементов управления и навигации'
                        : 'Choose the primary language for controls and navigation',
                    style: TextStyle(fontSize: 12, color: theme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildLangButton(
                        label: 'Русский',
                        locale: Locale.ru,
                        isSelected: currentLocale == Locale.ru,
                        onTap: () => ref.read(i18nProvider.notifier).setLocale(Locale.ru),
                        theme: theme,
                      ),
                      const SizedBox(width: 12),
                      _buildLangButton(
                        label: 'English',
                        locale: Locale.en,
                        isSelected: currentLocale == Locale.en,
                        onTap: () => ref.read(i18nProvider.notifier).setLocale(Locale.en),
                        theme: theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // App Icon Picker
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tr('settingsModal.appearance.appIconTitle'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.tr('settingsModal.appearance.appIconDescription'),
                    style: TextStyle(fontSize: 12, color: theme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 500;
                      final defaultCard = _buildIconCard(
                        iconId: 'default',
                        title: t.tr('settingsModal.appearance.iconDefaultTitle'),
                        description: t.tr('settingsModal.appearance.iconDefaultDescription'),
                        isSelected: uiSettings.appIcon == 'default',
                        onTap: () => ref.read(uiSettingsProvider.notifier).setAppIcon('default'),
                        theme: theme,
                      );
                      final altCard = _buildIconCard(
                        iconId: 'alt',
                        title: t.tr('settingsModal.appearance.iconAltTitle'),
                        description: t.tr('settingsModal.appearance.iconAltDescription'),
                        isSelected: uiSettings.appIcon == 'alt',
                        onTap: () => ref.read(uiSettingsProvider.notifier).setAppIcon('alt'),
                        theme: theme,
                      );

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: defaultCard),
                            const SizedBox(width: 16),
                            Expanded(child: altCard),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          defaultCard,
                          const SizedBox(height: 12),
                          altCard,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Accent Color (Coming Soon)
            Opacity(
              opacity: 0.6,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.tr('settingsModal.appearance.accentColorTitle'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Text(
                            t.tr('settingsModal.appearance.comingSoon').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: theme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.tr('settingsModal.appearance.accentColorDescription'),
                      style: TextStyle(fontSize: 12, color: theme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _buildColorSwatch(const Color(0xFF8B5CF6)), // violet
                        const SizedBox(width: 10),
                        _buildColorSwatch(const Color(0xFF10B981)), // emerald
                        const SizedBox(width: 10),
                        _buildColorSwatch(const Color(0xFF06B6D4)), // cyan
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLangButton({
    required String label,
    required Locale locale,
    required bool isSelected,
    required VoidCallback onTap,
    required TsundokuTheme theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x1A6366F1) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0x996366F1) : Colors.white.withAlpha(20),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? LucideIcons.checkCircle2 : LucideIcons.globe,
              size: 16,
              color: isSelected ? const Color(0xFF818CF8) : theme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : theme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconCard({
    required String iconId,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    required TsundokuTheme theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0x1A6366F1) : Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? const Color(0x996366F1) : Colors.white.withAlpha(25),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    iconId == 'default' ? 'assets/images/default.png' : 'assets/images/alt.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Image.network(
                      iconId == 'default' ? '/icons/default.png' : '/icons/alt.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: Colors.white.withAlpha(10),
                        child: Icon(
                          iconId == 'default' ? LucideIcons.box : LucideIcons.sparkles,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(fontSize: 12, height: 1.3, color: theme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.check, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildColorSwatch(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
    );
  }
}
