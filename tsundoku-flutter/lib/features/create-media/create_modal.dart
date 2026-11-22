library;

import 'package:material_ui/material_ui.dart';

import '../../shared/types/models.dart';
import '../edit-media/edit_media_workspace.dart';

/// Legacy entry point kept for the existing lazy import in `App`. The editor itself lives
/// in `features/edit-media/edit_media_workspace.dart` — a fullscreen spatial canvas of draggable
/// windows — and this thin adapter preserves the historical prop contract.
class CreateModal extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final ValueChanged<MediaItem> onCreated;
  final MediaItem? editingItem;

  const CreateModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onCreated,
    this.editingItem,
  });

  @override
  Widget build(BuildContext context) {
    return EditMediaWorkspace(
      isOpen: isOpen,
      onClose: onClose,
      onCreated: onCreated,
      editingItem: editingItem,
    );
  }
}
