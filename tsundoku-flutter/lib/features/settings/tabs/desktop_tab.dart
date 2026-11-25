/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "desktop").
///
/// Вкладка «Приложение» (Desktop):
/// - Режим отображения (Окно приложения / Вкладка браузера)
/// - Действие при закрытии окна (Сворачивать в трей / Полный выход)
/// - Сброс запомненных решений в диалогах подтверждения (confirmMemory.clear)
/// - Кнопка завершения работы приложения (exitApp)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/ui/confirm_dialog.dart';
import '../../../shared/ui/toast.dart';
import '../../../shared/ui/tsundoku_scroll.dart';

class DesktopTab extends ConsumerStatefulWidget {
  const DesktopTab({super.key});

  @override
  ConsumerState<DesktopTab> createState() => _DesktopTabState();
}

class _DesktopTabState extends ConsumerState<DesktopTab> {
  AppSettings _appSettings = const AppSettings(
    launchMode: AppLaunchMode.appWindow,
    closeAction: AppCloseAction.minimizeToTray,
  );
  bool _saving = false;
  int _confirmMemoryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
      _loadConfirmMemory();
    });
  }

  void _toast({
    required String title,
    required String description,
    ToastType type = ToastType.info,
  }) {
    ref.read(toastStoreProvider.notifier).show(
          ToastOptions(title: title, description: description, type: type),
        );
  }

  Future<void> _loadSettings() async {
    try {
      final res = await ref.read(apiClientProvider).getAppSettings();
      if (mounted) setState(() => _appSettings = res);
    } catch (_) {
      // Use defaults if unavailable
    }
  }

  Future<void> _loadConfirmMemory() async {
    final count = await ref.read(confirmDialogProvider.notifier).rememberedCount();
    if (mounted) setState(() => _confirmMemoryCount = count);
  }

  Future<void> _updateAppSettings({
    AppLaunchMode? launchMode,
    AppCloseAction? closeAction,
  }) async {
    if (_saving) return;
    final next = _appSettings.copyWith(
      launchMode: launchMode,
      closeAction: closeAction,
    );
    setState(() {
      _appSettings = next;
      _saving = true;
    });

    final t = ref.read(tProvider);
    try {
      final updated = await ref.read(apiClientProvider).saveAppSettings(next);
      if (mounted) setState(() => _appSettings = updated);
      _toast(
        title: t.tr('settingsModal.closeBehavior.savedToast'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearConfirmMemory() async {
    final t = ref.read(tProvider);
    await ref.read(confirmDialogProvider.notifier).clearMemory();
    await _loadConfirmMemory();
    _toast(
      title: t.tr('settingsModal.confirmMemory.clearedTitle'),
      description: t.tr('settingsModal.confirmMemory.clearedDesc'),
      type: ToastType.success,
    );
  }

  Future<void> _handleExitApp() async {
    try {
      await ref.read(apiClientProvider).shutdownApp();
    } catch (_) {}
    await platformService.closeWindow();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final isAppWindow = _appSettings.launchMode == AppLaunchMode.appWindow;

    return TsundokuSmoothScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Launch Mode Section
            Text(
              t.tr('settingsModal.launchMode.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.launchMode.description'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.borderSubtle),
              ),
              child: Column(
                children: [
                  _buildRadioOption(
                    title: t.tr('settingsModal.launchMode.appWindow'),
                    description: t.tr('settingsModal.launchMode.appWindowDescription'),
                    isSelected: isAppWindow,
                    onTap: () => _updateAppSettings(launchMode: AppLaunchMode.appWindow),
                    theme: theme,
                  ),
                  const SizedBox(height: 10),
                  _buildRadioOption(
                    title: t.tr('settingsModal.launchMode.browserTab'),
                    description: t.tr('settingsModal.launchMode.browserTabDescription'),
                    isSelected: !isAppWindow,
                    onTap: () => _updateAppSettings(launchMode: AppLaunchMode.browserTab),
                    theme: theme,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Close Action Section
            Text(
              t.tr('settingsModal.closeBehavior.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.closeBehavior.description'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: 14),

            Opacity(
              opacity: isAppWindow ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.borderSubtle),
                ),
                child: Column(
                  children: [
                    _buildRadioOption(
                      title: t.tr('settingsModal.closeBehavior.tray'),
                      description: t.tr('settingsModal.closeBehavior.trayDescription'),
                      isSelected: _appSettings.closeAction == AppCloseAction.minimizeToTray,
                      onTap: isAppWindow
                          ? () => _updateAppSettings(closeAction: AppCloseAction.minimizeToTray)
                          : null,
                      theme: theme,
                    ),
                    const SizedBox(height: 10),
                    _buildRadioOption(
                      title: t.tr('settingsModal.closeBehavior.exit'),
                      description: t.tr('settingsModal.closeBehavior.exitDescription'),
                      isSelected: _appSettings.closeAction == AppCloseAction.exitAll,
                      onTap: isAppWindow
                          ? () => _updateAppSettings(closeAction: AppCloseAction.exitAll)
                          : null,
                      theme: theme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 3. Confirm Memory Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tr('settingsModal.confirmMemory.title'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.tf('settingsModal.confirmMemory.hint', [_confirmMemoryCount]),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textSecondary,
                      side: BorderSide(color: theme.borderSubtle),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _confirmMemoryCount > 0 ? _clearConfirmMemory : null,
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: Text(
                      t.tr('settingsModal.confirmMemory.clear'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. Exit App Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.borderSubtle),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900.withAlpha(80),
                  foregroundColor: const Color(0xFFFCA5A5),
                  side: const BorderSide(color: Color(0x66EF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _handleExitApp,
                icon: const Icon(LucideIcons.x, size: 15),
                label: Text(
                  t.tr('settingsModal.exitApp.button'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOption({
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback? onTap,
    required TsundokuTheme theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? theme.accent.withAlpha(25) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? theme.accent : Colors.white.withAlpha(20),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? theme.accent : Colors.white.withAlpha(80),
                  width: isSelected ? 5.0 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: theme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
