/// Web/wasm (package:web, dart:js_interop) имплементация платформенного
/// фасада: navigator.clipboard, blob-download через <a download>,
/// window.open. dart:io недоступен — ничего из него не импортируется.
library;

import 'dart:async';
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
  Future<({String name, Uint8List bytes})?> pickFile() {
    // `fileInput.click()` + change → file.arrayBuffer(): 1-в-1 с Svelte onPick.
    final completer = Completer<({String name, Uint8List bytes})?>();
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.style.display = 'none';
    input.onChange.listen((_) async {
      final file = input.files?.item(0);
      if (file == null) {
        completer.complete(null);
        input.remove();
        return;
      }
      try {
        final buffer = await file.arrayBuffer().toDart;
        completer.complete((name: file.name, bytes: buffer.toDart.asUint8List()));
      } catch (_) {
        completer.complete(null);
      }
      input.remove();
    });
    web.document.body!.appendChild(input);
    input.click();
    return completer.future;
  }

  @override
  Future<void> openExternalUrl(String url) async {
    web.window.open(url, '_blank', 'noopener');
  }

  @override
  Future<void> closeWindow() async {
    web.window.close();
  }
}
