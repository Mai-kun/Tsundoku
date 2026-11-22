/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "reading").
///
/// Вкладка «Темп чтения»:
/// - Скорость чтения книг (мин/стр) в диапазоне 0.2 – 10.0 (дефолт 1.5)
/// - Скорость чтения манги (мин/гл) в диапазоне 0.5 – 30.0 (дефолт 6.0)
/// - Валидация и сохранение через `uiSettingsProvider.notifier.setReadingSpeed`
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/ui/toast.dart';
import '../../../shared/utils/ui_settings.dart';

class ReadingTab extends ConsumerStatefulWidget {
  const ReadingTab({super.key});

  @override
  ConsumerState<ReadingTab> createState() => _ReadingTabState();
}

class _ReadingTabState extends ConsumerState<ReadingTab> {
  late final TextEditingController _bookPageController;
  late final TextEditingController _mangaChapterController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final uiSettings = ref.read(uiSettingsProvider);
    _bookPageController = TextEditingController(text: uiSettings.bookPageMinutes.toString());
    _mangaChapterController = TextEditingController(text: uiSettings.mangaChapterMinutes.toString());
  }

  @override
  void dispose() {
    _bookPageController.dispose();
    _mangaChapterController.dispose();
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

  Future<void> _handleSave(I18nDictionary t) async {
    if (_isSaving) return;

    final bookMin = double.tryParse(_bookPageController.text.trim().replaceAll(',', '.'));
    final mangaMin = double.tryParse(_mangaChapterController.text.trim().replaceAll(',', '.'));

    if (bookMin == null || bookMin < 0.2 || bookMin > 10.0) {
      _toast(
        title: t.tr('settingsModal.reading.bookSpeedValidation'),
        description: t.tr('toast.descValidation'),
        type: ToastType.error,
      );
      return;
    }

    if (mangaMin == null || mangaMin < 0.5 || mangaMin > 30.0) {
      _toast(
        title: t.tr('settingsModal.reading.mangaSpeedValidation'),
        description: t.tr('toast.descValidation'),
        type: ToastType.error,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(uiSettingsProvider.notifier).setReadingSpeed(bookMin, mangaMin);
      _toast(
        title: t.tr('settingsModal.reading.savedToast'),
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tr('settingsModal.reading.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.reading.description'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: 24),

            // Book Page Speed
            Text(
              t.tr('settingsModal.reading.bookPageMinutes'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _bookPageController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 14, color: theme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'По умолчанию: 1.5 мин/стр. Диапазон: 0.2 – 10.0',
              style: TextStyle(fontSize: 11, color: theme.textMuted),
            ),
            const SizedBox(height: 20),

            // Manga Chapter Speed
            Text(
              t.tr('settingsModal.reading.mangaChapterMinutes'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _mangaChapterController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 14, color: theme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'По умолчанию: 6.0 мин/гл. Диапазон: 0.5 – 30.0',
              style: TextStyle(fontSize: 11, color: theme.textMuted),
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSaving ? null : () => _handleSave(t),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      t.tr('settingsModal.reading.saveButton'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
