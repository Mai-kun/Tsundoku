/// Порт `mediatracker-ui/src/features/edit-media/workspaceLayout.ts`.
///
/// Геометрия окон пространственного workspace редактирования. Всё
/// привязано к вьюпорту: сохранённая раскладка с большего экрана клампится
/// обратно в видимую область вместо того, чтобы окна улетали за экран.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Id окон workspace.
typedef WorkspaceWindowId = String; // 'main' | 'alt' | 'notes' | 'quotes' | 'images'

class WorkspaceRect {
  final double x;
  final double y;
  final double w;
  final double h;

  const WorkspaceRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  static WorkspaceRect fromJson(Map<String, dynamic> json) => WorkspaceRect(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

class OffsetPoint {
  final double x;
  final double y;

  const OffsetPoint(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is OffsetPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class WorkspaceSize {
  final double w;
  final double h;

  const WorkspaceSize({required this.w, required this.h});
}

class WorkspaceLayout {
  /// Центральный постер-узел: фиксированный размер, позиция — драг + persist.
  /// Поля мутабельны, как bindable-поля в loadLayout (merge сохранённого).
  OffsetPoint cover;
  Map<WorkspaceWindowId, WorkspaceRect> windows;

  WorkspaceLayout({required this.cover, required this.windows});
}

const List<String> kWorkspaceWindowIds = <String>[
  'main',
  'alt',
  'notes',
  'quotes',
  'images',
];

/// Центральный постер-узел: фиксированный размер, позиция — драг + persist.
const WorkspaceSize kCoverSize = WorkspaceSize(w: 220, h: 330);

const Map<WorkspaceWindowId, WorkspaceSize> kMinWindowSizes =
    <WorkspaceWindowId, WorkspaceSize>{
  'main': WorkspaceSize(w: 380, h: 320),
  'alt': WorkspaceSize(w: 280, h: 180),
  'notes': WorkspaceSize(w: 280, h: 180),
  'quotes': WorkspaceSize(w: 300, h: 200),
  'images': WorkspaceSize(w: 300, h: 240),
};

WorkspaceSize minWindowSize(WorkspaceWindowId id) => kMinWindowSizes[id]!;

/// Жёсткие границы вьюпорта: 16px боковой/нижний отступ, 64px — плавающий тулбар.
const double kSideMargin = 16;
const double kTopBar = 64;
const double kBottomMargin = 16;

WorkspaceRect clampWindowRect(
  WorkspaceRect rect,
  WorkspaceWindowId id,
  double viewportW,
  double viewportH,
) {
  final min = kMinWindowSizes[id]!;
  // Сначала размер: не шире/выше видимой полосы между жёсткими отступами.
  final w = rect.w
      .clamp(min.w, math.max(viewportW - 2 * kSideMargin, min.w))
      .toDouble();
  final h = rect.h
      .clamp(min.h, math.max(viewportH - kTopBar - kBottomMargin, min.h))
      .toDouble();
  // Затем позиция: весь rect остаётся в полосе, даже если это сжимает его ниже min.
  return WorkspaceRect(
    w: w,
    h: h,
    x: rect.x
        .clamp(kSideMargin, math.max(viewportW - kSideMargin - w, kSideMargin))
        .toDouble(),
    y: rect.y
        .clamp(kTopBar, math.max(viewportH - kBottomMargin - h, kTopBar))
        .toDouble(),
  );
}

OffsetPoint clampPoint(
  OffsetPoint point,
  double viewportW,
  double viewportH,
) {
  const w = 220.0; // kCoverSize.w (константный доступ к полю запрещён const-эвалюатором)
  const h = 330.0; // kCoverSize.h
  return OffsetPoint(
    point.x.clamp(
            kSideMargin, math.max(viewportW - kSideMargin - w, kSideMargin))
        .toDouble(),
    point.y.clamp(
            kTopBar, math.max(viewportH - kBottomMargin - h, kTopBar))
        .toDouble(),
  );
}

/// Композиция по умолчанию из таргет-мокапа: по два окна в боковых колонках,
/// окно альтернативных тайтлов над обложкой в центре. Координаты адаптируются
/// к вьюпорту.
WorkspaceLayout defaultLayout(double viewportW, double viewportH) {
  final cx = viewportW / 2;
  final bandTop = kTopBar + 20;
  final bandBottom = viewportH - kBottomMargin;
  final bandH = bandBottom - bandTop;

  // Три колонки: боковые фланкируют центральную (alt titles + cover).
  final centerW = math.min(470.0, math.max(360.0, viewportW * 0.29));
  final centerLeft = cx - centerW / 2;
  final centerRight = cx + centerW / 2;
  final sideW = math.min(520.0, math.max(kMinWindowSizes['main']!.w,
      math.max(centerLeft - 40 - 24, viewportW - kSideMargin - (centerRight + 40))));
  const leftX = 24.0;
  final rightX = centerRight + 40;

  // Левая колонка: basics (выше) над quotes; правая: notes над images.
  final mainH = (bandH * 0.58).floorToDouble();
  final quotesH = bandH - mainH - 16;
  final notesH = (bandH * 0.38).floorToDouble();
  final imagesH = bandH - notesH - 16;

  // Центральная колонка: alt titles под тулбаром, cover плавает ниже.
  final altH = math.min(260.0, bandH - kCoverSize.h - 60);

  return WorkspaceLayout(
    cover: clampPoint(
      OffsetPoint(cx - kCoverSize.w / 2, bandTop + altH + 40),
      viewportW,
      viewportH,
    ),
    windows: {
      'main': clampWindowRect(
        WorkspaceRect(x: leftX, y: bandTop, w: sideW, h: mainH),
        'main',
        viewportW,
        viewportH,
      ),
      'quotes': clampWindowRect(
        WorkspaceRect(x: leftX, y: bandTop + mainH + 16, w: sideW, h: quotesH),
        'quotes',
        viewportW,
        viewportH,
      ),
      'alt': clampWindowRect(
        WorkspaceRect(x: centerLeft, y: bandTop, w: centerW, h: altH),
        'alt',
        viewportW,
        viewportH,
      ),
      'notes': clampWindowRect(
        WorkspaceRect(x: rightX, y: bandTop, w: sideW, h: notesH),
        'notes',
        viewportW,
        viewportH,
      ),
      'images': clampWindowRect(
        WorkspaceRect(x: rightX, y: bandTop + notesH + 16, w: sideW, h: imagesH),
        'images',
        viewportW,
        viewportH,
      ),
    },
  );
}

/// v2: таргет-композиция (basics+quotes слева, alt titles+cover в центре,
/// notes+images справа). Бамп ключа применяет новую схему всем при открытии.
const String kEditWorkspaceStorageKey = 'tsundoku.editWorkspace.layout.v2';

/// localStorage → SharedPreferences (конвенция хранилища приложения).
Future<WorkspaceLayout> loadLayout(double viewportW, double viewportH) async {
  final layout = defaultLayout(viewportW, viewportH);
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kEditWorkspaceStorageKey);
    if (raw == null) return layout;
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return layout;
    final cover = parsed['cover'];
    if (cover is Map<String, dynamic> && cover['x'] is num && cover['y'] is num) {
      layout.cover = clampPoint(
        OffsetPoint(
            (cover['x'] as num).toDouble(), (cover['y'] as num).toDouble()),
        viewportW,
        viewportH,
      );
    }
    final windows = parsed['windows'];
    if (windows is Map<String, dynamic>) {
      for (final id in kWorkspaceWindowIds) {
        final rect = windows[id];
        if (rect is! Map<String, dynamic>) continue;
        final merged = WorkspaceRect(
          x: rect['x'] is num ? (rect['x'] as num).toDouble() : layout.windows[id]!.x,
          y: rect['y'] is num ? (rect['y'] as num).toDouble() : layout.windows[id]!.y,
          w: rect['w'] is num ? (rect['w'] as num).toDouble() : layout.windows[id]!.w,
          h: rect['h'] is num ? (rect['h'] as num).toDouble() : layout.windows[id]!.h,
        );
        layout.windows[id] = clampWindowRect(merged, id, viewportW, viewportH);
      }
    }
    return layout;
  } catch (_) {
    return layout;
  }
}

Future<void> saveLayout(WorkspaceLayout layout) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kEditWorkspaceStorageKey,
      jsonEncode(<String, Object?>{
        'cover': {'x': layout.cover.x, 'y': layout.cover.y},
        'windows': {
          for (final e in layout.windows.entries) e.key: e.value.toJson(),
        },
      }),
    );
  } catch (_) {
    // Приватный режим / квота: раскладка просто не запоминается.
  }
}
