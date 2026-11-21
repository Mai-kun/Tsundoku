/// Web/wasm (package:web, dart:js_interop) имплементация платформенного
/// фасада: navigator.clipboard, blob-download через <a download>,
/// window.open. dart:io недоступен — ничего из него не импортируется.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'platform_service.dart';

final PlatformService platformService = const WebPlatformService();

class WebPlatformService implements PlatformService {
  const WebPlatformService();

  @override
  Future<void> copyText(String text) async {
    await web.window.navigator.clipboard.writeText(text).toDart;
  }

  @override
  Future<void> copyImagePng(Uint8List pngBytes) async {
    final blob =
        web.Blob([pngBytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
    final items = JSObject();
    items['image/png'] = blob;
    await web.window.navigator.clipboard
        .write([web.ClipboardItem(items)].toJS)
        .toDart;
  }

  @override
  Future<void> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    // 1-в-1 с Svelte-якорем: blob → objectURL → <a download> → click.
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = suggestedName;
    anchor.rel = 'noopener';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  @override
  Future<void> openExternalUrl(String url) async {
    web.window.open(url, '_blank', 'noopener');
  }
}
