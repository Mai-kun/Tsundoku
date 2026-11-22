/// Платформенный фасад Tsundoku (§1.3 FLUTTER_MIGRATION.md): всё платформенное
/// (clipboard, файловые диалоги, внешние ссылки) — только через этот интерфейс,
/// никогда напрямую из виджетов/провайдеров.
///
/// Имплементация выбирается условным экспортом в `platform.dart`
/// (`platform_service_io.dart` / `platform_service_web.dart`).
library;

import 'dart:typed_data';

abstract interface class PlatformService {
  /// Инициализация параметров окна десктопного приложения (стартовый размер
  /// 1440×900, min 960×640, title "Tsundoku", тёмный фон #0d0f14).
  /// На Web — no-op.
  Future<void> initWindow();

  /// `navigator.clipboard.writeText` (копирование названия/URL обложки).
  Future<void> copyText(String text);

  /// `navigator.clipboard.write(image/png)` — копирование обложки в буфер.
  /// Байты уже перекодированы в PNG вызывающим кодом (dart:ui).
  Future<void> copyImagePng(Uint8List pngBytes);

  /// Чтение изображения из буфера обмена (Ctrl+V в галерее тайтла).
  /// Возвращает (bytes, mimeType) или null, если в буфере нет картинки.
  Future<({Uint8List bytes, String mimeType})?> pasteImage();

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
