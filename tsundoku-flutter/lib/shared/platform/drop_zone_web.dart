library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import 'drop_zone_types.dart';
export 'drop_zone_types.dart';

class PlatformDropZone extends StatelessWidget {
  final Widget child;
  final PlatformDropCallback onFilesDropped;
  final ValueChanged<bool>? onHoverChanged;
  final bool enabled;

  const PlatformDropZone({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.onHoverChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => onHoverChanged?.call(true),
      onDragExited: (_) => onHoverChanged?.call(false),
      onDragDone: (details) async {
        onHoverChanged?.call(false);
        final items = <PlatformDropFile>[];
        for (final file in details.files) {
          try {
            final bytes = await file.readAsBytes();
            items.add((
              name: file.name,
              bytes: bytes,
              path: file.path,
            ));
          } catch (_) {}
        }
        if (items.isNotEmpty) {
          onFilesDropped(items);
        }
      },
      child: child,
    );
  }
}
