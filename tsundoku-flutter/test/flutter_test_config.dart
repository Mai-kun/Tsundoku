import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тестовая конфигурация `flutter test` (подхватывается автоматически).
///
/// Загружает реальные шрифты приложения (`Inter`) и иконок (`Lucide` из
/// `lucide_icons_flutter`, `MaterialIcons`) из `FontManifest.json` перед
/// выполнением тестов. Без этого `flutter test` рендерит текст и иконки
/// плейсхолдер-шрифтом "Ahem" (белые прямоугольники).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loadedFamilies = await _loadAppFontsFromManifest();
  if (!loadedFamilies.contains('Inter')) {
    await _loadInterFont();
  }
  await testMain();
}

/// Загружает все шрифты, объявленные в `FontManifest.json` (включая пакетные
/// иконочные шрифты вроде `packages/lucide_icons_flutter/Lucide` и
/// `MaterialIcons`).
Future<Set<String>> _loadAppFontsFromManifest() async {
  final loaded = <String>{};
  try {
    final manifestRaw = await rootBundle.loadString('FontManifest.json');
    final manifest = jsonDecode(manifestRaw) as List<dynamic>;
    for (final entry in manifest) {
      if (entry is! Map<String, dynamic>) continue;
      final family = entry['family'] as String?;
      final fonts = entry['fonts'] as List<dynamic>?;
      if (family == null || fonts == null || fonts.isEmpty) continue;

      final loader = FontLoader(family);
      var hasAssets = false;
      for (final font in fonts) {
        if (font is! Map<String, dynamic>) continue;
        final asset = font['asset'] as String?;
        if (asset == null || asset.isEmpty) continue;
        loader.addFont(rootBundle.load(asset));
        hasAssets = true;
      }
      if (hasAssets) {
        await loader.load();
        loaded.add(family);
      }
    }
  } catch (_) {
    // Fallback на прямой загрузчик Inter, если manifest недоступен.
  }
  return loaded;
}

/// Веса Inter, объявленные в pubspec.yaml (1:1 с mediatracker-ui).
const Map<int, String> _interWeights = <int, String>{
  400: 'Inter-Regular',
  500: 'Inter-Medium',
  600: 'Inter-SemiBold',
  700: 'Inter-Bold',
  800: 'Inter-ExtraBold',
  900: 'Inter-Black',
};

Future<void> _loadInterFont() async {
  final loader = FontLoader('Inter');
  for (final String fileName in _interWeights.values) {
    final bytes = File('assets/fonts/$fileName.ttf').readAsBytesSync();
    assert(() {
      if (bytes.isEmpty) {
        throw StateError('Font asset is empty: assets/fonts/$fileName.ttf');
      }
      return true;
    }());
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
