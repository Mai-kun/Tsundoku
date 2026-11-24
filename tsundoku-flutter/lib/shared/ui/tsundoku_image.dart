import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/cover_url.dart';
import '../api/api.dart';

/// Resolves any image URL according to Tsundoku architecture:
/// 1. Relative paths (`/media-assets/...` or `/api/...`): prepended with [baseUrl].
/// 2. External HTTP/HTTPS URLs: ALWAYS wrapped via [proxiedExternalCoverUrl] + [baseUrl],
///    producing `http://127.0.0.1:{port}/api/external/image-proxy?url=...` so that
///    direct TLS connections to external CDNs are prevented, eliminating `HandshakeException`
///    and CDN 403/429 blocks.
/// 3. Local/proxied URLs already pointing to [baseUrl] or localhost are not double-wrapped.
String resolveTsundokuImageUrl(
  String? url,
  String baseUrl, {
  bool forceRefresh = false,
}) {
  if (url == null) return '';
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';

  final cleanBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  // Already prefixed with baseUrl?
  if (cleanBase.isNotEmpty && trimmed.startsWith(cleanBase)) {
    return trimmed;
  }

  // Already an absolute URL pointing to local server instance?
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
    if (trimmed.contains('/api/external/image-proxy') ||
        trimmed.contains('/media-assets/')) {
      return trimmed;
    }
  }

  // External HTTP/HTTPS URL: route through backend image proxy
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final proxiedPath = proxiedExternalCoverUrl(trimmed, forceRefresh: forceRefresh);
    if (cleanBase.isEmpty) {
      return proxiedPath;
    }
    return '$cleanBase$proxiedPath';
  }

  // Relative path (starts with /)
  if (trimmed.startsWith('/')) {
    if (cleanBase.isEmpty) return trimmed;
    return '$cleanBase$trimmed';
  }

  // Relative path without leading /
  if (cleanBase.isEmpty) return '/$trimmed';
  return '$cleanBase/$trimmed';
}

/// Unified image component replacing direct `Image.network` calls.
/// Automatically resolves relative paths against [apiBaseUrlProvider] and
/// routes all external images through the server's caching image-proxy.
class TsundokuImage extends ConsumerWidget {
  final String? src;
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final String? semanticLabel;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget? errorWidget;
  final Widget? placeholder;
  final bool forceRefresh;

  const TsundokuImage({
    super.key,
    this.src,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.errorBuilder,
    this.errorWidget,
    this.placeholder,
    this.forceRefresh = false,
  });

  Widget _defaultFallback(BuildContext context) {
    if (errorWidget != null) return errorWidget!;
    if (placeholder != null) return placeholder!;
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF151821),
      child: const Center(
        child: Icon(
          LucideIcons.image,
          size: 24,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveSrc = src ?? imageUrl;
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final resolvedUrl = resolveTsundokuImageUrl(
      effectiveSrc,
      baseUrl,
      forceRefresh: forceRefresh,
    );

    if (resolvedUrl.isEmpty) {
      if (errorBuilder != null) {
        return errorBuilder!(context, Exception('Empty image URL'), null);
      }
      return _defaultFallback(context);
    }

    return Image.network(
      resolvedUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticLabel,
      errorBuilder: (ctx, err, st) {
        if (errorBuilder != null) {
          return errorBuilder!(ctx, err, st);
        }
        return _defaultFallback(ctx);
      },
    );
  }
}
