import 'dart:ui_web' as ui_web;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

class EmbeddedTrailerPlayer extends StatefulWidget {
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
  State<EmbeddedTrailerPlayer> createState() => _EmbeddedTrailerPlayerState();
}

class _EmbeddedTrailerPlayerState extends State<EmbeddedTrailerPlayer> {
  static int _nextInstanceId = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    final id = _nextInstanceId++;
    _viewType = 'tsundoku-trailer-${widget.videoId}-$id';
    final embedUrl =
        'https://www.youtube-nocookie.com/embed/${Uri.encodeComponent(widget.videoId)}?autoplay=1';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.src = embedUrl;
      iframe.title = '${widget.title} trailer';
      iframe.style.border = '0';
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.allow = 'autoplay; encrypted-media; picture-in-picture';
      iframe.allowFullscreen = true;
      iframe.referrerPolicy = 'strict-origin-when-cross-origin';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        Positioned(
          top: 10,
          right: 10,
          child: _ExternalOpenChip(onTap: widget.onOpenExternal),
        ),
      ],
    );
  }
}

class _ExternalOpenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ExternalOpenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Открыть в браузере',
      child: Material(
        color: Colors.black.withAlpha(153),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(38)),
            ),
            child: const Icon(
              LucideIcons.arrowUpRight,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
