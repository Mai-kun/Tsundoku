/// Заглушка фасада для платформ, где недоступны ни dart:io, ни
/// dart:js_interop (не встречается среди поддерживаемых целей — Linux,
/// Windows, Android, Web/wasm; файл нужен условному экспорту как default).
library;

import 'dart:typed_data';

import 'platform_service.dart';

final PlatformService platformService = _UnsupportedPlatformService();

class _UnsupportedPlatformService implements PlatformService {
  @override
  Future<void> copyText(String text) async => _unsupported();

  @override
  Future<void> copyImagePng(Uint8List pngBytes) async => _unsupported();

  @override
  Future<void> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async => _unsupported();

  @override
  Future<void> openExternalUrl(String url) async => _unsupported();

  @override
  Future<void> closeWindow() async => _unsupported();

  Never _unsupported() => throw UnsupportedError(
      'PlatformService недоступен на этой платформе (нет io и js_interop)');
}
