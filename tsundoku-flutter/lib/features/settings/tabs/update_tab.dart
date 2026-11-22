/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "update").
///
/// Вкладка «Обновление»:
/// - Проверка наличия обновлений приложения (checkAppUpdate).
/// - Отображение текущей версии, новой версии, release notes.
/// - Автообновление (applyAppUpdate) и ожидание перезапуска бэкенда (waitForBackendRestart).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/api/server_restart.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/ui/toast.dart';

class UpdateTab extends ConsumerStatefulWidget {
  const UpdateTab({super.key});

  @override
  ConsumerState<UpdateTab> createState() => _UpdateTabState();
}

class _UpdateTabState extends ConsumerState<UpdateTab> {
  UpdateCheckResult? _updateCheck;
  bool _isChecking = false;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCheckUpdate());
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

  Future<void> _handleCheckUpdate() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final res = await ref.read(apiClientProvider).checkAppUpdate();
      if (mounted) setState(() => _updateCheck = res);
    } catch (e) {
      final t = ref.read(tProvider);
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _handleApplyUpdate() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    final api = ref.read(apiClientProvider);
    final t = ref.read(tProvider);

    try {
      await api.applyAppUpdate();
      _toast(
        title: 'Обновление применено, сервер перезапускается...',
        description: t.tr('toast.descActionDone'),
        type: ToastType.info,
      );

      await waitForBackendRestart(
        api,
        true,
        onRestartingChange: (val) {
          ref.read(serverRestartProvider.notifier).setRestarting(val);
        },
      );

      _toast(
        title: 'Сервер успешно перезапущен',
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
      await _handleCheckUpdate();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final update = _updateCheck;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  t.tr('settingsModal.tabs.update'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textPrimary,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textSecondary,
                    side: BorderSide(color: theme.borderSubtle),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _isChecking ? null : _handleCheckUpdate,
                  icon: const Icon(LucideIcons.refreshCw, size: 13),
                  label: const Text('Проверить снова', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_isChecking)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Проверка...',
                    style: TextStyle(fontSize: 14, color: theme.textMuted),
                  ),
                ],
              )
            else if (update != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Версия: ${update.currentVersion}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (update.isUpdateAvailable && update.canSelfUpdate) ...[
                      Text(
                        'Доступна версия ${update.latestVersion ?? ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF34D399), // emerald-400
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isApplying ? null : _handleApplyUpdate,
                        icon: _isApplying
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.download, size: 14),
                        label: Text(
                          _isApplying ? 'Обновление...' : 'Обновить и перезапустить',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (update.releaseNotes != null && update.releaseNotes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(50),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withAlpha(15)),
                          ),
                          child: Text(
                            update.releaseNotes!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: theme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ] else if (update.isUpdateAvailable) ...[
                      const Text(
                        'Обновление доступно, но автообновление недоступно.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF87171), // rose-400
                        ),
                      ),
                      if (update.releaseUrl != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.accent,
                            side: BorderSide(color: theme.accent.withAlpha(100)),
                          ),
                          onPressed: () => platformService.openExternalUrl(update.releaseUrl!),
                          icon: const Icon(LucideIcons.externalLink, size: 14),
                          label: const Text('Перейти к релизу на GitHub'),
                        ),
                      ],
                    ] else ...[
                      Text(
                        'Установлена актуальная версия.',
                        style: TextStyle(fontSize: 13, color: theme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
