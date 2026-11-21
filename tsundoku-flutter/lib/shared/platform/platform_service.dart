/// Платформенный фасад Tsundoku (§1.3 FLUTTER_MIGRATION.md): всё платформенное
/// (clipboard, файловые диалоги, внешние ссылки) — только через этот интерфейс,
/// никогда напрямую из виджетов/провайдеров.
///
/// Имплементация выбирается условным экспортом в `platform.dart`
/// (`platform_service_io.dart` / `platform_service_web.dart`).
library;

import 'dart:typed_data';

abstract interface class PlatformService {
  /// `navigator.clipboard.writeText` (копирование названия/URL обложки).
  Future<void> copyText(String text);

  /// `navigator.clipboard.write(image/png)` — копирование обложки в буфер.
  /// Байты уже перекодированы в PNG вызывающим кодом (dart:ui).
  Future<void> copyImagePng(Uint8List pngBytes);

  /// Сохранение файла на диск: браузерная download-ссылка (web) или
  /// native save-dialog (desktop). [bytes] уже скачаны вызывающим кодом
  /// (dio, кроссплатформенно).
  Future<void> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  });

  /// `fileInput.click()` / file_picker: выбор файла пользователем.
  /// null — отмена/неподдерживаемая платформа.
  Future<({String name, Uint8List bytes})?> pickFile();

  /// `window.open(url, '_blank', 'noopener')` — открытие внешней страницы
  /// источника.
  Future<void> openExternalUrl(String url);

  /// `window.close()` — закрытие окна приложения (appExit: tray/exit).
  Future<void> closeWindow();
}
