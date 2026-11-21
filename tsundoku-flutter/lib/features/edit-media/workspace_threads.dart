/// Порт `mediatracker-ui/src/features/edit-media/workspaceThreads.ts`.
///
/// Живые нити пространственного workspace. Якоря выбирают ближайшую грань
/// карточки автоматически и отдают нормаль грани, чтобы контрольные точки
/// выходили из карточки по касательной. Каждая контрольная точка — пружина,
/// отстающая от цели, с лёгкой органической синус-волной сверху: кабели
/// дышат, провисают и изгибаются как гибкие нити.
library;

import 'dart:math' as math;

class ThreadRect {
  final double x;
  final double y;
  final double w;
  final double h;

  const ThreadRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class AnchorPair {
  final double sx;
  final double sy;

  /// Наружная нормаль стартовой грани (единичный вектор касательной выхода).
  final double snx;
  final double sny;

  final double ex;
  final double ey;

  /// Наружная нормаль конечной грани (входная касательная).
  final double enx;
  final double eny;

  const AnchorPair({
    required this.sx,
    required this.sy,
    required this.snx,
    required this.sny,
    required this.ex,
    required this.ey,
    required this.enx,
    required this.eny,
  });
}

/// Грань rect, из которой выходит нить: 0 = лево, 1 = верх, 2 = право, 3 = низ.
typedef Face = int;

const Map<int, ({double x, double y})> kFaceNormals = <int, ({double x, double y})>{
  0: (x: -1, y: 0),
  1: (x: 0, y: -1),
  2: (x: 1, y: 0),
  3: (x: 0, y: 1),
};

({double x, double y}) _centerOf(ThreadRect rect) =>
    (x: rect.x + rect.w / 2, y: rect.y + rect.h / 2);

({double x, double y}) _facePoint(ThreadRect rect, Face face) {
  switch (face) {
    case 0:
      return (x: rect.x, y: rect.y + rect.h / 2);
    case 1:
      return (x: rect.x + rect.w / 2, y: rect.y);
    case 2:
      return (x: rect.x + rect.w, y: rect.y + rect.h / 2);
    default: // 3
      return (x: rect.x + rect.w / 2, y: rect.y + rect.h);
  }
}

/// Выбирает грань выхода на `from` и входа на `to` по вектору между центрами:
/// доминантная ось побеждает — кабель всегда выходит через ребро карточки, а
/// не из угла. Нормали граней едут вместе с контрольными точками.
AnchorPair nearestFaceAnchors(ThreadRect from, ThreadRect to) {
  final a = _centerOf(from);
  final b = _centerOf(to);
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  Face fromFace;
  Face toFace;
  if (dx.abs() >= dy.abs()) {
    fromFace = dx >= 0 ? 2 : 0;
    toFace = dx >= 0 ? 0 : 2;
  } else {
    fromFace = dy >= 0 ? 3 : 1;
    toFace = dy >= 0 ? 1 : 3;
  }
  final start = _facePoint(from, fromFace);
  final end = _facePoint(to, toFace);
  final sn = kFaceNormals[fromFace]!;
  final en = kFaceNormals[toFace]!;
  return AnchorPair(
    sx: start.x,
    sy: start.y,
    snx: sn.x,
    sny: sn.y,
    ex: end.x,
    ey: end.y,
    enx: en.x,
    eny: en.y,
  );
}

/// Анимированный кабель. Концы и обе контрольные точки — пружины к целям;
/// цели контролей выходят из грани по касательной, несут лёгкий провис и
/// дышат синус-волной (фаза сдвинута на нить), так что покоящиеся кабели
/// держат мягкую органическую кривую.
class ThreadSpring {
  final int wavePhase;

  double _ax;
  double _ay;
  double _bx;
  double _by;
  double _c1x;
  double _c1y;
  double _c2x;
  double _c2y;

  ThreadSpring(AnchorPair target, this.wavePhase)
      : _ax = target.sx,
        _ay = target.sy,
        _bx = target.ex,
        _by = target.ey,
        _c1x = target.sx,
        _c1y = target.sy,
        _c2x = target.ex,
        _c2y = target.ey {
    final c = controlTargets(target, 0);
    _c1x = c.$1;
    _c1y = c.$2;
    _c2x = c.$3;
    _c2y = c.$4;
  }

  /// Касательные цели контролей: выступ вдоль нормали грани, лёгкий провис
  /// вниз и деликатный синус-«дыхание» (фаза своя на нить — кабели не качаются
  /// синхронно).
  (double, double, double, double) controlTargets(AnchorPair t, double timeMs) {
    final dist = math.sqrt(
        (t.ex - t.sx) * (t.ex - t.sx) + (t.ey - t.sy) * (t.ey - t.sy));
    final protrusion = math.min(math.max(dist * 0.32, 28.0), 110.0);
    final sag = math.min(dist * 0.08, 26.0);
    final sway = math.sin(timeMs * 0.0018 + wavePhase) * 8;
    final sway2 = math.sin(timeMs * 0.0018 + wavePhase + 1.7) * 8;
    return (
      t.sx + t.snx * (protrusion + sway),
      t.sy + t.sny * (protrusion + sway) + sag,
      t.ex + t.enx * (protrusion - sway2),
      t.ey + t.eny * (protrusion - sway2) + sag,
    );
  }

  /// Тянет концы и контроли к свежим целям и возвращает кубический bezier-путь
  /// (прямых сегментов не бывает — каждая связь это `C`-кривая).
  String step(AnchorPair target, double timeMs, double k) {
    _ax += (target.sx - _ax) * k;
    _ay += (target.sy - _ay) * k;
    _bx += (target.ex - _bx) * k;
    _by += (target.ey - _by) * k;

    final c = controlTargets(target, timeMs);
    _c1x += (c.$1 - _c1x) * k;
    _c1y += (c.$2 - _c1y) * k;
    _c2x += (c.$3 - _c2x) * k;
    _c2y += (c.$4 - _c2y) * k;

    final d =
        'M ${_ax.toStringAsFixed(1)} ${_ay.toStringAsFixed(1)} C ${_c1x.toStringAsFixed(1)} ${_c1y.toStringAsFixed(1)}, ${_c2x.toStringAsFixed(1)} ${_c2y.toStringAsFixed(1)}, ${_bx.toStringAsFixed(1)} ${_by.toStringAsFixed(1)}';
    return d;
  }
}
