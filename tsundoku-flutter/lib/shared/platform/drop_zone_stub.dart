library;

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
    return child;
  }
}
