import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

/// Контроль загрузки настоящего Inter (а не Ahem-плейсхолдера) в тестах.
///
/// Движок сопоставляет face по OS/2-таблице при запросе TextStyle.fontWeight.
/// Если бы загрузился единственный face (или Ahem), оба рендера были бы
/// попиксельно идентичны — тест упадёт с понятной диагностикой.
Future<Uint8List?> _renderText(WidgetTester tester, int weight) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Center(
          child: Text(
            'Tsundoku Цундоку 0123',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 40,
              fontWeight:
                  FontWeight.values.singleWhere((w) => w.value == weight),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) return null;
  final bytes = await tester
      .runAsync(() => image.toByteData(format: ImageByteFormat.png));
  return bytes?.buffer.asUint8List();
}

void main() {
  testWidgets('Inter: weights 400 and 700 render differently', (tester) async {
    final regular = await _renderText(tester, 400);
    final bold = await _renderText(tester, 700);

    expect(regular, isNotNull);
    expect(bold, isNotNull);
    expect(
      listEquals(regular, bold),
      isFalse,
      reason:
          'Inter w400 и w700 отрендерились попиксельно одинаково — похоже, '
          'в тестах грузится плейсхолдер-шрифт (Ahem) или один face без '
          'weight-маппинга. Проверь test/flutter_test_config.dart и assets/fonts.',
    );
  });

  testWidgets('Inter: w700 and w900 render differently', (tester) async {
    final bold = await _renderText(tester, 700);
    final black = await _renderText(tester, 900);
    expect(
      listEquals(bold, black),
      isFalse,
      reason: 'w700 и w900 совпали — весовая маппинг Inter неполный '
          '(ожидаются Inter-Bold.ttf и Inter-Black.ttf).',
    );
  });

  testWidgets('Icon fonts (Lucide & MaterialIcons) render distinct glyphs',
      (tester) async {
    Future<Uint8List?> renderIcon(IconData icon) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Center(child: Icon(icon, size: 40)),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      if (image == null) return null;
      final bytes = await tester
          .runAsync(() => image.toByteData(format: ImageByteFormat.png));
      return bytes?.buffer.asUint8List();
    }

    final lucideFilm = await renderIcon(LucideIcons.film);
    final lucideBook = await renderIcon(LucideIcons.bookOpen);
    final matCheck = await renderIcon(Icons.check);
    final matClose = await renderIcon(Icons.close);

    expect(lucideFilm, isNotNull);
    expect(lucideBook, isNotNull);
    expect(matCheck, isNotNull);
    expect(matClose, isNotNull);
    expect(
      listEquals(lucideFilm, lucideBook),
      isFalse,
      reason: 'Lucide-иконки отрендерились одинаково — шрифт Lucide не загружен.',
    );
    expect(
      listEquals(matCheck, matClose),
      isFalse,
      reason: 'MaterialIcons отрендерились одинаково — шрифт не загружен.',
    );
  });
}
