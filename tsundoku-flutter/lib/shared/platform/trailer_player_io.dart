import 'dart:async';
import 'dart:io' show Platform;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

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
  static bool _mediaKitInitialized = false;

  Player? _player;
  VideoController? _controller;
  bool _loading = true;
  bool _disposed = false;
  bool _ageGated = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAndPlay());
  }

  @override
  void didUpdateWidget(covariant EmbeddedTrailerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final player = _player;
    _player = null;
    _controller = null;
    if (player != null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final oldPlayer = _player;
    _player = null;
    _controller = null;
    if (oldPlayer != null) {
      await oldPlayer.dispose();
    }
    if (!_disposed) {
      await _loadAndPlay();
    }
  }

  bool _isAgeGateError(Object error) {
    if (error is VideoRequiresPurchaseException) return true;
    final lower = error.toString().toLowerCase();
    return lower.contains('age') ||
        lower.contains('sign in') ||
        lower.contains('confirm your age') ||
        lower.contains('inappropriate');
  }

  Future<Uri?> _resolveStreamUri() async {
    final resolver = widget.streamResolver;
    if (resolver != null) {
      return resolver(widget.videoId);
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(widget.videoId);
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.withHighestBitrate().url;
      }
      if (manifest.videoOnly.isNotEmpty) {
        return manifest.videoOnly.withHighestBitrate().url;
      }
      return null;
    } finally {
      yt.close();
    }
  }

  Future<void> _loadAndPlay() async {
    if (_disposed) return;
    setState(() {
      _loading = true;
      _ageGated = false;
      _errorMessage = null;
    });

    try {
      final streamUri = await _resolveStreamUri();
      if (_disposed) return;

      if (streamUri == null) {
        throw VideoUnavailableException('No playable stream for ${widget.videoId}');
      }

      if (!_mediaKitInitialized) {
        MediaKit.ensureInitialized();
        _mediaKitInitialized = true;
      }

      final player = Player();
      final controller = VideoController(player);
      if (_disposed) {
        await player.dispose();
        return;
      }

      await player.open(Media(streamUri.toString()), play: true);
      if (_disposed) {
        await player.dispose();
        return;
      }

      setState(() {
        _player = player;
        _controller = controller;
        _loading = false;
      });
    } catch (error) {
      if (_disposed) return;
      final ageGated = _isAgeGateError(error);
      setState(() {
        _loading = false;
        _ageGated = ageGated;
        _errorMessage = ageGated
            ? 'Видео защищено возрастным ограничением'
            : 'Не удалось загрузить поток трейлера';
      });
      if (ageGated) {
        widget.onOpenExternal();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            )
          else if (controller != null)
            Video(
              controller: controller,
              fit: BoxFit.contain,
              fill: Colors.black,
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _ageGated ? LucideIcons.shieldAlert : LucideIcons.videoOff,
                      size: 24,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Не удалось воспроизвести трейлер',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onOpenExternal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(LucideIcons.arrowUpRight, size: 14),
                          label: const Text(
                            'Открыть в браузере',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => unawaited(_loadAndPlay()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withAlpha(51)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(LucideIcons.refreshCw, size: 14),
                          label: const Text(
                            'Повторить',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 10,
            right: 10,
            child: Tooltip(
              message: 'Открыть в браузере',
              child: Material(
                color: Colors.black.withAlpha(153),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: widget.onOpenExternal,
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
            ),
          ),
        ],
      ),
    );
  }
}
