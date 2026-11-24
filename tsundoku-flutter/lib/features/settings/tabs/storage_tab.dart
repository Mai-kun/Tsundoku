/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "storage").
///
/// Вкладка «Хранилище»:
/// - Выбор режима хранения данных (По умолчанию / Portable / Свой путь)
/// - Перенос существующих данных при смене пути
/// - Отображение текущих путей (БД, обложки, логи)
/// - Сохранение с перезапуском бэкенда (waitForBackendRestart)
/// - Инструмент пересканирования франшиз (reindexFranchises)
/// - Управление постоянным кэшем поиска (статистика, очистка)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/api/server_restart.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/models.dart';
import '../../../shared/ui/confirm_dialog.dart';
import '../../../shared/ui/text_field.dart';
import '../../../shared/ui/toast.dart';

class StorageTab extends ConsumerStatefulWidget {
  const StorageTab({super.key});

  @override
  ConsumerState<StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends ConsumerState<StorageTab> {
  StorageSettings? _storage;
  bool _loading = false;
  String? _error;

  StorageMode _storageMode = StorageMode.defaultMode;
  late final TextEditingController _customPathController;
  bool _migrateExistingData = false;
  bool _isSavingStorage = false;

  // Franchise reindexing
  bool _franchiseRescanning = false;

  // Search cache
  SearchCacheInfoDto? _searchCacheInfo;
  bool _searchCacheClearing = false;

  @override
  void initState() {
    super.initState();
    _customPathController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStorage();
      _loadSearchCacheInfo();
    });
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _loadStorage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiClientProvider).getStorageSettings();
      if (mounted) {
        setState(() {
          _storage = res;
          _storageMode = res.mode;
          _customPathController.text = res.customPath ?? '';
          _migrateExistingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSearchCacheInfo() async {
    try {
      final res = await ref.read(apiClientProvider).getSearchCacheInfo();
      if (mounted) setState(() => _searchCacheInfo = res);
    } catch (_) {}
  }

  Future<void> _handleSaveStorage(I18nDictionary t) async {
    if (_isSavingStorage) return;
    setState(() => _isSavingStorage = true);
    final api = ref.read(apiClientProvider);

    try {
      final restartScheduled = await api.saveStorageSettings(
        StorageRequest(
          mode: _storageMode,
          customPath: _customPathController.text.trim(),
          migrateExistingData: _migrateExistingData,
        ),
      );

      _toast(
        title: t.tr('settingsModal.storage.savedToast'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );

      if (restartScheduled) {
        await waitForBackendRestart(
          api,
          true,
          onRestartingChange: (val) {
            ref.read(serverRestartProvider.notifier).setRestarting(val);
          },
        );
      }
      await _loadStorage();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isSavingStorage = false);
    }
  }

  Future<void> _handleRescanFranchises(I18nDictionary t) async {
    if (_franchiseRescanning) return;
    setState(() => _franchiseRescanning = true);
    try {
      await ref.read(apiClientProvider).reindexFranchises();
      _toast(
        title: t.tr('settingsModal.storage.franchiseDoneToast'),
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
      if (mounted) setState(() => _franchiseRescanning = false);
    }
  }

  Future<void> _handleClearSearchCache(I18nDictionary t) async {
    if (_searchCacheClearing) return;

    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'clear-search-cache',
        title: t.tr('settingsModal.storage.searchCacheConfirm'),
        confirmLabel: t.tr('settingsModal.storage.searchCacheClearButton'),
        danger: true,
      ),
    );
    if (!confirmed) return;

    setState(() => _searchCacheClearing = true);
    try {
      await ref.read(apiClientProvider).clearSearchCache();
      _toast(
        title: t.tr('settingsModal.storage.searchCacheClearedToast'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
      await _loadSearchCacheInfo();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _searchCacheClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final storage = _storage;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Description
            Text(
              t.tr('settingsModal.storage.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.storage.description'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: 20),

            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFFCA5A5)),
                ),
              ),

            if (_loading && storage == null)
              const Center(child: CircularProgressIndicator())
            else if (storage != null) ...[
              // Storage Mode Selection
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
                      t.tr('settingsModal.storage.title'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3 mode radio cards
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 600;
                        final cards = [
                          _buildModeCard(
                            mode: StorageMode.defaultMode,
                            icon: LucideIcons.server,
                            label: t.tr('settingsModal.storage.modeDefault'),
                            theme: theme,
                          ),
                          _buildModeCard(
                            mode: StorageMode.portable,
                            icon: LucideIcons.archive,
                            label: t.tr('settingsModal.storage.modePortable'),
                            theme: theme,
                          ),
                          _buildModeCard(
                            mode: StorageMode.custom,
                            icon: LucideIcons.folderOpen,
                            label: t.tr('settingsModal.storage.modeCustom'),
                            theme: theme,
                          ),
                        ];

                        if (isNarrow) {
                          return Column(
                            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList(),
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 8),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 8),
                            Expanded(child: cards[2]),
                          ],
                        );
                      },
                    ),

                    if (_storageMode == StorageMode.custom) ...[
                      const SizedBox(height: 16),
                      Text(
                        t.tr('settingsModal.storage.customPathLabel'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      TsundokuTextField(
                        controller: _customPathController,
                        placeholder: t.tr('settingsModal.storage.customPathPlaceholder'),
                      ),
                    ],

                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => setState(() => _migrateExistingData = !_migrateExistingData),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _migrateExistingData,
                            activeColor: theme.accent,
                            onChanged: (val) => setState(() => _migrateExistingData = val ?? false),
                          ),
                          Flexible(
                            child: Text(
                              t.tr('settingsModal.storage.migrateLabel'),
                              style: TextStyle(fontSize: 13, color: theme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Divider(color: Color(0x14FFFFFF)),
                    const SizedBox(height: 14),

                    // Directory paths
                    _buildPathRow(t.tr('settingsModal.storage.dbPathLabel'), storage.defaultDirectory, theme),
                    const SizedBox(height: 8),
                    _buildPathRow(t.tr('settingsModal.storage.coversPathLabel'), storage.portableDirectory, theme),
                    const SizedBox(height: 8),
                    _buildPathRow(t.tr('settingsModal.storage.logsPathLabel'), storage.defaultDirectory, theme),

                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSavingStorage ? null : () => _handleSaveStorage(t),
                      icon: _isSavingStorage
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const SizedBox.shrink(),
                      label: Text(
                        _isSavingStorage
                            ? t.tr('settingsModal.storage.saving')
                            : t.tr('settingsModal.storage.saveButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Franchise Rescan Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.gitFork, size: 18, color: Color(0xFFA5B4FC)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.tr('settingsModal.storage.franchiseRescanTitle'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.tr('settingsModal.storage.franchiseRescanDescription'),
                                style: TextStyle(fontSize: 12, height: 1.4, color: theme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _franchiseRescanning ? null : () => _handleRescanFranchises(t),
                      icon: _franchiseRescanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(LucideIcons.gitFork, size: 14),
                      label: Text(
                        t.tr('settingsModal.storage.franchiseRescanButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Persistent Search Cache Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.search, size: 18, color: Color(0xFFA5B4FC)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.tr('settingsModal.storage.searchCacheTitle'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.tr('settingsModal.storage.searchCacheDescription'),
                                style: TextStyle(fontSize: 12, height: 1.4, color: theme.textMuted),
                              ),
                              if (_searchCacheInfo != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(40),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white.withAlpha(15)),
                                  ),
                                  child: Text(
                                    '${_searchCacheInfo!.entryCount} записей, ${_searchCacheInfo!.imageFileCount} картинок (${_formatBytes(_searchCacheInfo!.fileSizeBytes + _searchCacheInfo!.imageFileSizeBytes)})',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: theme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _searchCacheClearing ? null : () => _handleClearSearchCache(t),
                      icon: _searchCacheClearing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(LucideIcons.trash2, size: 14),
                      label: Text(
                        t.tr('settingsModal.storage.searchCacheClearButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required StorageMode mode,
    required IconData icon,
    required String label,
    required TsundokuTheme theme,
  }) {
    final isSelected = _storageMode == mode;

    return InkWell(
      onTap: () => setState(() => _storageMode = mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.accent.withAlpha(35) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? theme.accent : Colors.white.withAlpha(20),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? theme.accent : theme.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : theme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathRow(String label, String path, TsundokuTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: theme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
