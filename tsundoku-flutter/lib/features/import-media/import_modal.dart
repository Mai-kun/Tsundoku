/// 1:1 port of `mediatracker-ui/src/features/import-media/ImportModal.svelte`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/ui/modal.dart';

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
        : _DefaultImportModalContent(
            onImportCompleted: onImportCompleted,
            onClose: onClose,
            onNavigateToList: onNavigateToList,
          );

    return TsundokuModal(
      isOpen: true,
      onClose: onClose,
      size: ModalSize.xl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
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

class _DefaultImportModalContent extends ConsumerWidget {
  final VoidCallback onImportCompleted;
  final VoidCallback onClose;
  final ValueChanged<String>? onNavigateToList;

  const _DefaultImportModalContent({
    required this.onImportCompleted,
    required this.onClose,
    this.onNavigateToList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x1A6366F1), // indigo-500/10
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x336366F1)), // indigo-500/20
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.folderInput,
                      size: 20,
                      color: Color(0xFF818CF8), // indigo-400
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  t.tr('importModal.title'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: const Icon(
                LucideIcons.x,
                size: 18,
                color: Color(0xFF94A3B8), // slate-400
              ),
              onPressed: onClose,
            ),
          ],
        ),
      ],
    );
  }
}
