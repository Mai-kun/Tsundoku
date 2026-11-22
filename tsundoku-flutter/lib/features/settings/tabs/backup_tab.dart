/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "backup").
///
/// Вкладка «Резервная копия»:
/// - Экспорт полного архива медиатеки (SQLite + обложки) в .zip
/// - Экспорт таблицы данных (JSON / CSV)
/// - Восстановление из .zip архива с подтверждением и отображением размера файла
/// - Полный сброс медиатеки (Danger Zone) с обязательным вводом проверочного слова (УДАЛИТЬ)
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/ui/toast.dart';

class BackupTab extends ConsumerStatefulWidget {
  const BackupTab({super.key});

  @override
  ConsumerState<BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends ConsumerState<BackupTab> {
  bool _isExporting = false;
  String? _exportingTableFormat; // 'json' | 'csv' | null
  bool _isRestoring = false;
  bool _isResetting = false;

  void _toast({
    required String title,
    required String description,
    ToastType type = ToastType.info,
  }) {
    ref.read(toastStoreProvider.notifier).show(
          ToastOptions(title: title, description: description, type: type),
        );
  }

  String _formatTimestamp(DateTime dt, {bool includeTime = true}) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final date = '${dt.year}${pad(dt.month)}${pad(dt.day)}';
    if (!includeTime) return date;
    return '$date-${pad(dt.hour)}${pad(dt.minute)}${pad(dt.second)}';
  }

  Future<void> _handleExportBackup(I18nDictionary t) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await ref.read(apiClientProvider).exportBackup();
      final filename = 'tsundoku-backup-${_formatTimestamp(DateTime.now())}.zip';
      await platformService.saveFile(suggestedName: filename, bytes: bytes);
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleExportTable(String format, I18nDictionary t) async {
    if (_exportingTableFormat != null) return;
    setState(() => _exportingTableFormat = format);
    try {
      final api = ref.read(apiClientProvider);
      final Uint8List bytes;
      if (format == 'json') {
        bytes = await api.exportLibraryJson();
      } else {
        bytes = await api.exportLibraryCsv();
      }
      final filename = 'tsundoku-library-${_formatTimestamp(DateTime.now(), includeTime: false)}.$format';
      await platformService.saveFile(suggestedName: filename, bytes: bytes);
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _exportingTableFormat = null);
    }
  }

  Future<void> _handlePickAndRestore(I18nDictionary t) async {
    if (_isRestoring) return;
    try {
      final picked = await platformService.pickFile();
      if (picked == null) return;

      if (!mounted) return;
      final confirmed = await _showRestoreConfirmDialog(context, picked.name, picked.bytes.length, t);
      if (confirmed != true) return;

      setState(() => _isRestoring = true);
      await ref.read(apiClientProvider).restoreBackup(picked.bytes, fileName: picked.name);

      _toast(
        title: t.tr('settingsModal.backup.restoreSuccess'),
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
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<bool?> _showRestoreConfirmDialog(
    BuildContext context,
    String fileName,
    int byteSize,
    I18nDictionary t,
  ) {
    final sizeMb = (byteSize / (1024 * 1024)).toStringAsFixed(2);
    final theme = TsundokuTheme.of(context);

    return showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC090B10),
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF151A26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(LucideIcons.triangleAlert, size: 20, color: Colors.amber),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.tr('settingsModal.backup.confirmModalTitle'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t.tr('settingsModal.backup.confirmModalWarning'),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: theme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.bgSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withAlpha(25)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  t.tr('settingsModal.backup.selectedFileLabel'),
                                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$fileName ($sizeMb MB)',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(false),
                      child: Text(
                        t.tr('settingsModal.backup.cancelButton'),
                        style: TextStyle(color: theme.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(dialogCtx).pop(true),
                      icon: const Icon(LucideIcons.triangleAlert, size: 14),
                      label: Text(t.tr('settingsModal.backup.confirmButton')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleResetModal(I18nDictionary t) async {
    if (_isResetting) return;

    final theme = TsundokuTheme.of(context);
    final confirmWord = t.tr('settingsModal.backup.confirmationWord');

    bool keepApiKeys = true;
    final textController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC090B10),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMatch = textController.text.trim() == confirmWord;

          return Dialog(
            backgroundColor: const Color(0xFF151A26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(LucideIcons.triangleAlert, size: 20, color: Colors.redAccent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.tr('settingsModal.backup.resetConfirmTitle'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.tr('settingsModal.backup.resetWarning'),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: theme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              InkWell(
                                onTap: () {
                                  setDialogState(() => keepApiKeys = !keepApiKeys);
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: keepApiKeys,
                                      activeColor: Colors.redAccent,
                                      onChanged: (val) {
                                        setDialogState(() => keepApiKeys = val ?? true);
                                      },
                                    ),
                                    Text(
                                      t.tr('settingsModal.backup.keepApiKeys'),
                                      style: TextStyle(fontSize: 12, color: theme.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                text: TextSpan(
                                  text: t.tr('settingsModal.backup.typeToConfirm'),
                                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                                  children: [
                                    const TextSpan(text: ' '),
                                    TextSpan(
                                      text: confirmWord,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: textController,
                                onChanged: (_) => setDialogState(() {}),
                                style: TextStyle(fontSize: 13, color: theme.textPrimary),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.bgSurface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: Colors.white.withAlpha(25)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: Colors.white.withAlpha(25)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: Colors.redAccent),
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(false),
                          child: Text(
                            t.tr('settingsModal.backup.cancelButton'),
                            style: TextStyle(color: theme.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.red.shade900.withAlpha(80),
                            disabledForegroundColor: Colors.white38,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: isMatch ? () => Navigator.of(dialogCtx).pop(true) : null,
                          icon: const Icon(LucideIcons.trash2, size: 14),
                          label: Text(t.tr('settingsModal.backup.resetConfirmButton')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      setState(() => _isResetting = true);
      try {
        await ref.read(apiClientProvider).resetAllData(keepApiKeys: keepApiKeys);
        _toast(
          title: t.tr('settingsModal.backup.resetSuccess'),
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
        if (mounted) setState(() => _isResetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Export Section (Neutral / Safe)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('settingsModal.backup.exportTitle'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.tr('settingsModal.backup.exportDescription'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isExporting ? null : () => _handleExportBackup(t),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.arrowDown, size: 14),
                  label: Text(
                    _isExporting
                        ? t.tr('settingsModal.backup.exporting')
                        : t.tr('settingsModal.backup.exportButton'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Data Table Export (JSON / CSV)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('settingsModal.backup.exportDataTitle'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.tr('settingsModal.backup.exportDataDescription'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo.shade300,
                        backgroundColor: Colors.indigo.shade500.withAlpha(25),
                        side: BorderSide(color: Colors.indigo.shade500.withAlpha(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _exportingTableFormat != null ? null : () => _handleExportTable('json', t),
                      icon: _exportingTableFormat == 'json'
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigoAccent),
                            )
                          : const Icon(LucideIcons.fileText, size: 14),
                      label: Text(
                        _exportingTableFormat == 'json'
                            ? t.tr('settingsModal.backup.exportingTable')
                            : t.tr('settingsModal.backup.exportJsonButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6EE7B7),
                        backgroundColor: const Color(0xFF10B981).withAlpha(25),
                        side: BorderSide(color: const Color(0xFF10B981).withAlpha(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _exportingTableFormat != null ? null : () => _handleExportTable('csv', t),
                      icon: _exportingTableFormat == 'csv'
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6EE7B7)),
                            )
                          : const Icon(LucideIcons.arrowDown, size: 14),
                      label: Text(
                        _exportingTableFormat == 'csv'
                            ? t.tr('settingsModal.backup.exportingTable')
                            : t.tr('settingsModal.backup.exportCsvButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Restore Section (Warning Zone - Amber)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withAlpha(64)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.triangleAlert, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text(
                      '${t.tr('settingsModal.backup.dangerZone')}: ${t.tr('settingsModal.backup.restoreTitle')}'.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.tr('settingsModal.backup.restoreDescription'),
                  style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade300,
                    backgroundColor: Colors.amber.shade500.withAlpha(25),
                    side: BorderSide(color: Colors.amber.shade500.withAlpha(100)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isRestoring ? null : () => _handlePickAndRestore(t),
                  icon: _isRestoring
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                        )
                      : const Icon(LucideIcons.rotateCcw, size: 14),
                  label: Text(
                    _isRestoring
                        ? t.tr('settingsModal.backup.restoring')
                        : t.tr('settingsModal.backup.selectFileButton'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Reset Section (Danger Zone - Rose)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withAlpha(64)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      '${t.tr('settingsModal.backup.dangerZone')}: ${t.tr('settingsModal.backup.resetTitle')}'.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.tr('settingsModal.backup.resetDescription'),
                  style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isResetting ? null : () => _handleResetModal(t),
                  icon: _isResetting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.trash2, size: 14),
                  label: Text(
                    _isResetting
                        ? t.tr('settingsModal.backup.resetting')
                        : t.tr('settingsModal.backup.resetButton'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
