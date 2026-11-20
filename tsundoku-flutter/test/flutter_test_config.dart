import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Тестовая конфигурация `flutter test` (подхватывается автоматически).
///
/// Загружает настоящий шрифт Inter для widget/golden-тестов. Без этого `flutter
/// test` рендерит текст плейсхолдер-шрифтом "Ahem" (чёрные прямоугольники), что
/// делает golden-сравнения со Svelte-эталонами бессмысленными.
///
/// Файлы читаются относительно корня пакета: `flutter test` запускается с cwd
/// = корень пакета tsundoku-flutter.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadInterFont();
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
    final bytes = File('assets/fonts/$fileName.ttf').readAsBytesSync();
    // Движок (Skia) сопоставляет нужный face по OS/2-таблице файла при
    // запросе TextStyle.fontWeight; контроль этого поведения — в
    // test/goldens/font_loader_weight_test.dart.
    assert(() {
      // Ранний понятный сбой, если файл шрифта отсутствует.
      if (bytes.isEmpty) {
        throw StateError('Font asset is empty: assets/fonts/$fileName.ttf');
      }
      return true;
    }());
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
