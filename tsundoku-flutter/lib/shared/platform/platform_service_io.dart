/// Desktop/mobile (dart:io) имплементация платформенного фасада: буфер —
/// super_clipboard, сохранение — file_picker (native save-dialog), внешние
/// ссылки — url_launcher (xdg-open и аналоги).
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;

import 'platform_service.dart';

final PlatformService platformService = const IoPlatformService();

class IoPlatformService implements PlatformService {
  const IoPlatformService();

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
    // Закрытие desktop-окна: текущее окно nativeapi (window_manager 0.7
    // re-export). window_manager за фасадом §1.3.
    final window = nativeapi.WindowManager.instance.getCurrent();
    if (window != null) {
      window.close(); // bool — fire-and-forget (не Future).
    }
  }
}
