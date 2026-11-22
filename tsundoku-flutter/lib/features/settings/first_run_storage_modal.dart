/// 1:1 port of `mediatracker-ui/src/features/settings/FirstRunStorageModal.svelte`.
///
/// Визард первого запуска: выбор места хранения данных (системная папка,
/// portable рядом с программой или произвольный путь), вызов saveStorageSettings
/// и ожидание перезапуска бэкенда через waitForBackendRestart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/api/server_restart.dart';
import '../../shared/i18n/index.dart';
import '../../shared/types/models.dart';
import '../../shared/ui/modal.dart';

class FirstRunStorageModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final VoidCallback? onSaved;

  const FirstRunStorageModal({
    super.key,
    this.isOpen = true,
    this.onSaved,
  });

  @override
  ConsumerState<FirstRunStorageModal> createState() =>
      _FirstRunStorageModalState();
}

class _FirstRunStorageModalState extends ConsumerState<FirstRunStorageModal> {
  bool _loading = true;
  bool _saving = false;
  StorageMode _mode = StorageMode.defaultMode;
  late final TextEditingController _customPathController;
  StorageSettings? _settings;

  @override
  void initState() {
    super.initState();
    _customPathController = TextEditingController();
    if (widget.isOpen) {
      _loadSettings();
    }
  }

  @override
  void didUpdateWidget(FirstRunStorageModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getStorageSettings();
      if (mounted) {
        setState(() {
          _settings = res;
          _mode = res.mode;
          if (res.customPath != null && res.customPath!.isNotEmpty) {
            _customPathController.text = res.customPath!;
          }
        });
      }
    } catch (_) {
      // Ignored: first-run can proceed with defaults
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    final customPath = _customPathController.text.trim();
    if (_mode == StorageMode.custom && customPath.isEmpty) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final restartScheduled = await api.saveStorageSettings(
        StorageRequest(
          mode: _mode,
          customPath: _mode == StorageMode.custom ? customPath : '',
          migrateExistingData: false,
        ),
      );

      await waitForBackendRestart(
        api,
        restartScheduled,
        onRestartingChange: (val) {
          ref.read(serverRestartProvider.notifier).setRestarting(val);
        },
      );

      widget.onSaved?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: () {},
      closable: false,
      size: ModalSize.md,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x266366F1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x336366F1)),
                  ),
                  child: const Icon(
                    LucideIcons.server,
                    size: 20,
                    color: Color(0xFF818CF8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('settings.storageSetupRequired'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.tr('settingsModal.storage.description'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Content
            if (_saving) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.tr('settings.storageApplying'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_loading) ...[
              const SizedBox(
                height: 160,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Option cards
              Column(
                children: [
                  _buildOptionCard(
                    mode: StorageMode.defaultMode,
                    icon: LucideIcons.server,
                    title: t.tr('settings.storageDefault'),
                    subtitle: _settings?.defaultDirectory ??
                        '~/.local/share/Tsundoku',
                  ),
                  const SizedBox(height: 10),
                  _buildOptionCard(
                    mode: StorageMode.portable,
                    icon: LucideIcons.archive,
                    title: t.tr('settings.storagePortable'),
                    subtitle: _settings?.portableDirectory ?? './data',
                  ),
                  const SizedBox(height: 10),
                  _buildOptionCard(
                    mode: StorageMode.custom,
                    icon: LucideIcons.folderOpen,
                    title: t.tr('settings.storageCustom'),
                    subtitle: t.tr('settingsModal.storage.customPathLabel'),
                  ),
                  if (_mode == StorageMode.custom) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customPathController,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0x0AFFFFFF),
                        hintText: t
                            .tr('settingsModal.storage.customPathPlaceholder'),
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0x806366F1)),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Action button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed: (_saving ||
                            (_mode == StorageMode.custom &&
                                _customPathController.text.trim().isEmpty))
                        ? null
                        : _handleSave,
                    child: Text(
                      t.tr('settings.storageConfirm'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required StorageMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _mode == mode;

    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x266366F1) : const Color(0x05FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0x996366F1)
                : const Color(0x1AFFFFFF),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFF818CF8)
                  : const Color(0xFF94A3B8),
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
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
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
