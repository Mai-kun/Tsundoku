/// Desktop/mobile (dart:io) имплементация платформенного фасада: буфер —
/// super_clipboard, сохранение — file_picker (native save-dialog), внешние
/// ссылки — url_launcher (xdg-open и аналоги).
library;

// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart' show Color, Size;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/legacy.dart';

import 'platform_service.dart';

PlatformService platformService = const IoPlatformService();

class IoPlatformService implements PlatformService {
  const IoPlatformService();

  @override
  Future<void> initWindow() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(960, 640),
        center: true,
        backgroundColor: Color(0xFF0D0F14),
        skipTaskbar: false,
        title: 'Tsundoku',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  @override
  Future<void> copyText(String text) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem()..add(Formats.plainText(text));
    await clipboard.write([item]);
  }

  @override
  Future<void> copyImagePng(Uint8List pngBytes) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem(suggestedName: 'cover.png')
      ..add(Formats.png(pngBytes));
    await clipboard.write([item]);
  }

  @override
  Future<({Uint8List bytes, String mimeType})?> pasteImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();
    if (reader.canProvide(Formats.png)) {
      final completer = Completer<Uint8List?>();
      reader.getFile(Formats.png, (file) async {
        try {
          final bytes = await file.readAll();
          completer.complete(bytes);
        } catch (_) {
          completer.complete(null);
        }
      }, onError: (_) => completer.complete(null));
      final bytes = await completer.future;
      if (bytes != null && bytes.isNotEmpty) {
        return (bytes: bytes, mimeType: 'image/png');
      }
    }
    if (reader.canProvide(Formats.jpeg)) {
      final completer = Completer<Uint8List?>();
      reader.getFile(Formats.jpeg, (file) async {
        try {
          final bytes = await file.readAll();
          completer.complete(bytes);
        } catch (_) {
          completer.complete(null);
        }
      }, onError: (_) => completer.complete(null));
      final bytes = await completer.future;
      if (bytes != null && bytes.isNotEmpty) {
        return (bytes: bytes, mimeType: 'image/jpeg');
      }
    }
    return null;
  }

  @override
  Future<void> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    // file_picker на desktop открывает native save-dialog и пишет bytes в
    // выбранное место; null — пользователь отменил.
    await FilePicker.saveFile(fileName: suggestedName, bytes: bytes);
  }

  @override
  Future<({String name, Uint8List bytes})?> pickFile() async {
    final result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.any,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null) return null;
    return (name: file.name, bytes: file.bytes!);
  }

  @override
  Future<void> openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> closeWindow() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.close();
    }
  }
}
