/// Порт `mediatracker-ui/src/widgets/stats/taste-profile/GenreRadarChart.svelte`.
///
/// Радар вкуса:
/// - Заголовок `stats.taste.radarTitle` с иконкой Sparkles (#818cf8);
/// - Подзаголовок `stats.taste.radarHint`;
/// - Empty state при пустом axes (`stats.taste.emptyData`);
/// - Шестиугольная сетка CustomPainter (3 уровня: R/3, 2R/3, R = 100);
/// - Полигон данных с заливкой accent/25% и обводкой #818cf8;
/// - Точки вершин (r=4), бейджи средней оценки «★ X.X» (#c7d2fe);
/// - Подписи жанров по кругу с учётом labelAnchor (#94a3b8).
library;

import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_label.dart';

class GenreRadarChart extends ConsumerWidget {
  final List<RadarAxis> axes;

  const GenreRadarChart({super.key, required this.axes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151A26), // bg-[#151a26]
        border: Border.all(color: Colors.white.withAlpha(13)), // border-white/5
        borderRadius: BorderRadius.circular(12), // rounded-xl
      ),
      padding: const EdgeInsets.all(20), // p-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Шапка
          Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 16,
                color: Color(0xFF818CF8), // text-indigo-400
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                t.tr('stats.taste.radarTitle'),
                style: const TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w600, // font-semibold
                  letterSpacing: -0.2, // tracking-tight
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // mb-2
          Text(
            t.tr('stats.taste.radarHint'),
            style: const TextStyle(
              fontSize: 12, // text-xs
              color: Color(0xFF94A3B8), // text-slate-400
            ),
          ),
          const SizedBox(height: 12),

          // Радар или пустой стейт
          if (axes.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 256), // min-h-64
              alignment: Alignment.center,
              child: Text(
                t.tr('stats.taste.emptyData'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: theme.textSecondary, // text-muted
                ),
              ),
            )
          else
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448), // max-w-md
                child: AspectRatio(
                  aspectRatio: 430 / 340, // viewBox="-45 0 430 340"
                  child: CustomPaint(
                    painter: _RadarChartPainter(
                      axes: axes.length > 6 ? axes.sublist(0, 6) : axes,
                      t: t,
                      locale: locale,
                      accentColor: theme.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<RadarAxis> axes;
  final I18nDictionary t;
  final Locale locale;
  final Color accentColor;

  static const double centerCoord = 170.0;
  static const double maxR = 100.0;
  static const double vbMinX = -45.0;
  static const double vbMinY = 0.0;
  static const double vbW = 430.0;
  static const double vbH = 340.0;

  const _RadarChartPainter({
    required this.axes,
    required this.t,
    required this.locale,
    required this.accentColor,
  });

  static Offset _axisPoint(int index, double radius) {
    final angle = ((index * 60 - 90) * math.pi) / 180.0;
    return Offset(
      centerCoord + radius * math.cos(angle),
      centerCoord + radius * math.sin(angle),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Масштабирование координат viewBox (-45, 0, 430, 340) -> size
    final scaleX = size.width / vbW;
    final scaleY = size.height / vbH;
    final scale = math.min(scaleX, scaleY);

    canvas.save();
    canvas.translate(-vbMinX * scale, -vbMinY * scale);
    canvas.scale(scale, scale);

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withAlpha(20); // rgba(255,255,255,0.08)

    // 1. Сетка из 3 уровней
    const gridLevels = [maxR / 3, (maxR * 2) / 3, maxR];
    for (final level in gridLevels) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final pt = _axisPoint(i, level);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // 2. Оси (spokes)
    for (var i = 0; i < 6; i++) {
      final spoke = _axisPoint(i, maxR);
      canvas.drawLine(
        const Offset(centerCoord, centerCoord),
        spoke,
        gridPaint,
      );
    }

    // 3. Полигон данных
    if (axes.isNotEmpty) {
      final dataPath = Path();
      final points = <Offset>[];

      for (var i = 0; i < axes.length; i++) {
        final radius = (math.max(axes[i].volumeScore, 0.0) / 100.0) * maxR;
        final pt = _axisPoint(i, radius);
        points.add(pt);
        if (i == 0) {
          dataPath.moveTo(pt.dx, pt.dy);
        } else {
          dataPath.lineTo(pt.dx, pt.dy);
        }
      }
      dataPath.close();

      // Заливка
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = accentColor.withAlpha(64); // fill-opacity="0.25"
      canvas.drawPath(dataPath, fillPaint);

      // Обводка
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF818CF8); // stroke="#818cf8"
      canvas.drawPath(dataPath, strokePaint);

      // Точки вершин
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF818CF8);
      for (final pt in points) {
        canvas.drawCircle(pt, 4.0, dotPaint);
      }
    }

    // 4. Текстовые метки оценок и жанров
    for (var i = 0; i < axes.length; i++) {
      final axis = axes[i];
      final radius = (math.max(axis.volumeScore, 0.0) / 100.0) * maxR;

      // Оценка: ★ X.X
      if (axis.averageScore > 0) {
        final scorePoint = _axisPoint(i, radius + 16.0);
        final scorePainter = TextPainter(
          text: TextSpan(
            text: '★ ${axis.averageScore}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC7D2FE),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        scorePainter.paint(
          canvas,
          Offset(
            scorePoint.dx - scorePainter.width / 2,
            scorePoint.dy - scorePainter.height / 2,
          ),
        );
      }

      // Название жанра
      final labelPoint = _axisPoint(i, maxR + 30.0);
      final localizedGenre = genreLabel(axis.genre, t, locale);

      final cos = math.cos(((i * 60 - 90) * math.pi) / 180.0);
      final labelPainter = TextPainter(
        text: TextSpan(
          text: localizedGenre,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF94A3B8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      double labelX;
      if (cos.abs() < 0.35) {
        labelX = labelPoint.dx - labelPainter.width / 2; // middle
      } else if (cos > 0) {
        labelX = labelPoint.dx; // start
      } else {
        labelX = labelPoint.dx - labelPainter.width; // end
      }

      labelPainter.paint(
        canvas,
        Offset(labelX, labelPoint.dy - labelPainter.height / 2),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) {
    if (oldDelegate.axes.length != axes.length) return true;
    for (var i = 0; i < axes.length; i++) {
      if (oldDelegate.axes[i].genre != axes[i].genre ||
          oldDelegate.axes[i].volumeScore != axes[i].volumeScore ||
          oldDelegate.axes[i].averageScore != axes[i].averageScore) {
        return true;
      }
    }
    return oldDelegate.locale != locale || oldDelegate.accentColor != accentColor;
  }
}
