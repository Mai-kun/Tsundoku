/// 1:1 port of `mediatracker-ui/src/features/import-media/ImportModal.svelte`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/import-media/import_panel.dart';
import 'package:tsundoku_flutter/shared/ui/modal.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_scroll.dart';

typedef ImportPanelBuilder = Widget Function(
  BuildContext context, {
  required VoidCallback onImportCompleted,
  required VoidCallback onClose,
  ValueChanged<String>? onNavigateToList,
  bool showCloseButton,
});

/// Modal dialog wrapping the import panel (Svelte: `Modal {isOpen} size="xl"`).
class ImportModal extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onImportCompleted;
  final ValueChanged<String>? onNavigateToList;
  final ImportPanelBuilder? panelBuilder;

  const ImportModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onImportCompleted,
    this.onNavigateToList,
    this.panelBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOpen) {
      return TsundokuModal(
        isOpen: false,
        onClose: onClose,
        size: ModalSize.xl,
        child: const SizedBox.shrink(),
      );
    }

    final panelWidget = panelBuilder != null
        ? panelBuilder!(
            context,
            onImportCompleted: onImportCompleted,
            onClose: onClose,
            onNavigateToList: onNavigateToList,
            showCloseButton: true,
          )
        : ImportPanel(
            onImportCompleted: onImportCompleted,
            onClose: onClose,
            onNavigateToList: onNavigateToList,
            showCloseButton: true,
          );

    return TsundokuModal(
      isOpen: true,
      onClose: onClose,
      size: ModalSize.xl,
      contentPadding: EdgeInsets.zero,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        padding: const EdgeInsets.all(24.0),
        child: TsundokuSmoothScrollView(
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 150),
            child: panelWidget,
          ),
        ),
      ),
    );
  }
}
