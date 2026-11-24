import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_matrix/golden_matrix.dart';

/// Тестовая конфигурация `flutter test` (подхватывается автоматически).
///
/// 1. Вызывает `loadAppFonts()` из `golden_matrix`.
/// 2. Явно загружает через [FontLoader] все 6 весов шрифта `Inter`
///    (`assets/fonts/Inter-*.ttf`) и иконочный шрифт `lucide_icons_flutter`
///    (`packages/lucide_icons_flutter/...`), чтобы ни в одном Golden-тесте не
///    появлялись квадратики Ahem вместо текста или иконок.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  await _loadInterFont();
  await _loadLucideIconFonts();
  await testMain();
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
    final file = File('assets/fonts/$fileName.ttf');
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) {
      throw StateError('Font asset is empty: assets/fonts/$fileName.ttf');
    }
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadLucideIconFonts() async {
  final loadedFamilies = <String>{};
  try {
    final manifestRaw = await rootBundle.loadString('FontManifest.json');
    final manifest = jsonDecode(manifestRaw) as List<dynamic>;
    for (final entry in manifest) {
      if (entry is! Map<String, dynamic>) continue;
      final family = entry['family'] as String?;
      final fonts = entry['fonts'] as List<dynamic>?;
      if (family == null ||
          fonts == null ||
          fonts.isEmpty ||
          !family.startsWith('packages/lucide_icons_flutter/')) {
        continue;
      }
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
        loadedFamilies.add(family);
      }
    }
  } catch (_) {
    // Fallback ниже загрузит основной шрифт Lucide напрямую.
  }

  const primaryLucideFamily = 'packages/lucide_icons_flutter/Lucide';
  if (!loadedFamilies.contains(primaryLucideFamily)) {
    final loader = FontLoader(primaryLucideFamily);
    loader.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await loader.load();
  }
}
