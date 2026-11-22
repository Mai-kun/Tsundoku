/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "import").
///
/// Вкладка «Импорт»:
/// Встраивает ImportPanel с поддержкой всех 9 провайдеров (AniList, MangaLib,
/// MAL, Shikimori, Letterboxd, Goodreads, Steam, Anixart, CSV/JSON) и передачей колбеков.
library;

import 'package:material_ui/material_ui.dart';

import '../../import-media/import_panel.dart';

class ImportTab extends StatelessWidget {
  final VoidCallback? onImportCompleted;
  final ValueChanged<String>? onNavigateToList;
  final VoidCallback? onClose;

  const ImportTab({
    super.key,
    this.onImportCompleted,
    this.onNavigateToList,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 896), // max-w-4xl (Svelte standard)
          child: ImportPanel(
            onImportCompleted: onImportCompleted,
            onNavigateToList: (listId) {
              onClose?.call();
              onNavigateToList?.call(listId);
            },
            showCloseButton: false,
          ),
        ),
      ),
    );
  }
}
