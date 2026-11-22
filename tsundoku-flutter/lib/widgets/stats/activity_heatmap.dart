/// Порт `mediatracker-ui/src/widgets/stats/ActivityHeatmap.svelte`.
///
/// Годовая тепловая карта активности: 53 недели × 7 дней, Monday-offset
/// заполнение, 5 уровней интенсивности, легенда и итоговые счётчики.
library;

import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

/// Один день сетки (или заполнитель до понедельника первой недели).
class _Cell {
  final DateTime? date;
  final String? iso;
  final num count;
  const _Cell(this.date, this.iso, this.count);

  static const _Cell empty = _Cell(null, null, 0);
}

/// Уровень интенсивности (1-в-1 с Svelte intensity()).
Color _intensity(num count, Color accentBright) {
  if (count == 0) return Colors.white.withAlpha(10); // bg-white/[0.04]
  if (count <= 2) return accentBright.withAlpha((255 * 0.35).round());
  if (count <= 5) return accentBright.withAlpha((255 * 0.65).round());
  if (count <= 9) return accentBright;
  return const Color(0xFF818CF8); // bg-[#818cf8]
}

class ActivityHeatmap extends ConsumerWidget {
  /// `Record<string, number>` — ISO yyyy-MM-dd → количество действий.
  final Map<String, num> dailyActivity;

  /// Инъекция «сегодня» для детерминированных тестов; null → DateTime.now().
  final DateTime? today;

  const ActivityHeatmap({super.key, required this.dailyActivity, this.today});

  static const double _gap = 4; // gap-1
  static const double _minGridWidth = 760; // min-w-[760px]

  List<_Cell> _cells(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final days = <_Cell>[];
    for (var i = 0; i < 365; i++) {
      final date = today.subtract(Duration(days: 364 - i));
      final iso = DateFormat('yyyy-MM-dd').format(date);
      days.add(_Cell(date, iso, dailyActivity[iso] ?? 0));
    }
    // JS getDay(): 0=воскресенье; смещение до понедельника.
    final mondayOffset = (days.first.date!.weekday % 7 + 6) % 7;
    return [
      ...List.filled(mondayOffset, _Cell.empty),
      ...days,
    ];
  }

  String _formatDate(DateTime date, Locale locale) {
    initializeDateFormatting(locale.wire, null);
    // Intl.DateTimeFormat(locale, { day:'numeric', month:'short',
    // year:'numeric' }).
    return DateFormat('d MMM y', locale.wire).format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final th = TsundokuTheme.of(context);
    final cells = _cells(today ?? DateTime.now());
    final totalActivity = dailyActivity.values.fold<num>(0, (s, c) => s + c);
    final totalLabel = t.tf('stats.heatmapTotal', [totalActivity]);

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: const Color(0xFF151A26), // bg-[#151a26]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.tr('stats.heatmapTitle'),
                style: TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                totalLabel,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFA5B4FC), // text-[#a5b4fc]
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // mb-4
          LayoutBuilder(builder: (context, constraints) {
            final available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : _minGridWidth;
            final gridWidth = available < _minGridWidth
                ? _minGridWidth
                : available;
            final cellSize = (gridWidth - 52 * _gap) / 53;
            final grid = Row(
              children: [
                for (var w = 0; w < 53; w++)
                  Padding(
                    padding: EdgeInsets.only(left: w == 0 ? 0 : _gap),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Builder(builder: (context) {
                            if (w * 7 + d >= cells.length) {
                              return SizedBox(
                                width: cellSize,
                                height: cellSize,
                              );
                            }
                            final cell = cells[w * 7 + d];
                            if (cell.date == null) {
                              return SizedBox(
                                width: cellSize,
                                height: cellSize,
                              );
                            }
                            return Tooltip(
                              message: t.tf('stats.heatmapTooltip', [
                                _formatDate(cell.date!, locale),
                                cell.count,
                              ]),
                              child: Container(
                                margin:
                                    const EdgeInsets.all(2), // m-0.5
                                width: cellSize - 4,
                                height: cellSize - 4,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(2),
                                  color: _intensity(
                                      cell.count, th.accentBright),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
              ],
            );
            if (available < _minGridWidth) {
              // overflow-x-auto.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                    width: _minGridWidth, height: 7 * cellSize, child: grid),
              );
            }
            return SizedBox(height: 7 * cellSize, child: grid);
          }),
          const SizedBox(height: 8), // mt-2
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8), // text-slate-400
                ),
              ),
              Row(
                children: [
                  Text(
                    t.tr('stats.less'),
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8), // text-slate-400
                    ),
                  ),
                  for (final color in [
                    Colors.white.withAlpha(10),
                    th.accentBright.withAlpha((255 * 0.35).round()),
                    th.accentBright.withAlpha((255 * 0.65).round()),
                    th.accentBright,
                    const Color(0xFF818CF8),
                  ])
                    Container(
                      width: 12, // size-3
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: color,
                      ),
                    ),
                  Text(
                    t.tr('stats.more'),
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
