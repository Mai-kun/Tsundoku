import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_threads.dart';

void main() {
  group('nearestFaceAnchors', () {
    test('горизонтальный доминант: выход справа, вход слева', () {
      final anchors = nearestFaceAnchors(
        const ThreadRect(x: 0, y: 0, w: 100, h: 50),
        const ThreadRect(x: 300, y: 0, w: 100, h: 50),
      );
      // Старт: правая грань from (x=100, y=25).
      expect(anchors.sx, 100);
      expect(anchors.sy, 25);
      expect(anchors.snx, 1);
      expect(anchors.sny, 0);
      // Конец: левая грань to (x=300, y=25).
      expect(anchors.ex, 300);
      expect(anchors.ey, 25);
      expect(anchors.enx, -1);
      expect(anchors.eny, 0);
    });

    test('вертикальный доминант: выход снизу, вход сверху', () {
      final anchors = nearestFaceAnchors(
        const ThreadRect(x: 0, y: 0, w: 100, h: 50),
        const ThreadRect(x: 10, y: 200, w: 100, h: 50),
      );
      expect(anchors.sx, 50);
      expect(anchors.sy, 50);
      expect(anchors.snx, 0);
      expect(anchors.sny, 1);
      expect(anchors.ex, 60);
      expect(anchors.ey, 200);
      expect(anchors.enx, 0);
      expect(anchors.eny, -1);
    });

    test('обратный горизонталь: from правее to — выход слева, вход справа', () {
      final anchors = nearestFaceAnchors(
        const ThreadRect(x: 500, y: 0, w: 100, h: 50),
        const ThreadRect(x: 100, y: 0, w: 100, h: 50),
      );
      expect(anchors.sx, 500); // левая грань from
      expect(anchors.snx, -1);
      expect(anchors.ex, 200); // правая грань to
      expect(anchors.enx, 1);
    });

    test('dy=dx: горизонталь выигрывает (>=)', () {
      final anchors = nearestFaceAnchors(
        const ThreadRect(x: 0, y: 0, w: 100, h: 100),
        const ThreadRect(x: 200, y: 200, w: 100, h: 100),
      );
      expect(anchors.snx, 1); // правая грань
      expect(anchors.sny, 0);
    });
  });

  group('ThreadSpring', () {
    test('step: пружина подтягивает концы к цели и даёт C-кривую', () {
      final target = AnchorPair(
        sx: 100, sy: 50, snx: 1, sny: 0,
        ex: 300, ey: 50, enx: -1, eny: 0,
      );
      final spring = ThreadSpring(target, 0);
      final d = spring.step(target, 0, 0.2);
      // Кривая начинается в старой точке (0-констр), к цели ещё не дотянулась.
      expect(d, startsWith('M 100.0 50.0'));
      expect(d, contains(' C '));
      // После многих шагов концы сходятся к цели.
      var last = d;
      for (var i = 0; i < 200; i++) {
        last = spring.step(target, i * 16.0, 0.2);
      }
      expect(last, startsWith('M 100.0 50.0'));
      expect(last, endsWith('300.0 50.0'));
    });

    test('controlTargets: выступ по нормали + провис, дыхание по времени', () {
      const target = AnchorPair(
        sx: 100, sy: 50, snx: 1, sny: 0,
        ex: 300, ey: 50, enx: -1, eny: 0,
      );
      final spring = ThreadSpring(target, 0);
      final (c1x, c1y, c2x, c2y) = spring.controlTargets(target, 0);
      // dist=200: protrusion = min(max(64, 28), 110) = 64; sway=sin(0)*8=0.
      expect(c1x, 100 + 64);
      // Провис: min(200*0.08, 26) = 16.
      expect(c1y, 50 + 16);
      // sway2 = sin(1.7)*8 ≈ 7.97.
      expect(c2x, closeTo(300 - 64 + 7.97, 0.05));
      expect(c2y, 50 + 16);
      // Другая фаза времени меняет цели (дыхание).
      final (c1x2, _, c2x2, _) = spring.controlTargets(target, 1000);
      expect(c1x2, isNot(c1x));
      expect(c2x2, isNot(c2x));
    });
  });
}
