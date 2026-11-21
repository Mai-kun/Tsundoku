/// 1:1 port of `mediatracker-ui/src/shared/ui/lightbox.svelte.ts`.
///
/// App-wide lightbox state. A single [ImageLightbox] lives at the top of
/// AppShell: per-section instances rendered the lightbox off-center; everything
/// routes through this store instead. Svelte writable → Riverpod Notifier.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ImageLightboxState {
  final String? url;

  /// Optional one-line caption (a person's name, a screenshot title) shown
  /// under the image.
  final String? caption;

  const ImageLightboxState({this.url, this.caption});

  bool get isOpen => url != null;
}

class LightboxController extends Notifier<ImageLightboxState> {
  @override
  ImageLightboxState build() => const ImageLightboxState();

  /// Open the global lightbox with the given (full-size) image URL and
  /// optional caption.
  void openLightbox(String? url, [String? caption]) {
    if (url == null || url.isEmpty) return;
    state = ImageLightboxState(url: url, caption: caption);
  }

  /// Close the global lightbox.
  void closeLightbox() {
    state = const ImageLightboxState();
  }
}

final lightboxProvider =
    NotifierProvider<LightboxController, ImageLightboxState>(
        LightboxController.new);
