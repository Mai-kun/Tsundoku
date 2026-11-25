import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class EmbeddedTrailerPlayer extends StatelessWidget {
  final String videoId;
  final String title;
  final VoidCallback onOpenExternal;
  final Future<Uri?> Function(String videoId)? streamResolver;

  const EmbeddedTrailerPlayer({
    super.key,
    required this.videoId,
    required this.title,
    required this.onOpenExternal,
    this.streamResolver,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(LucideIcons.externalLink, size: 15, color: Colors.white),
              label: const Text(
                'Открыть трейлер в браузере',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
