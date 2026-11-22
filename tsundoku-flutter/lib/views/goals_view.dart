/// 1:1 port of `mediatracker-ui/src/views/GoalsView.svelte`.
///
/// Экран целей и вызовов:
/// - Шапка: кольцевой индикатор общего прогресса (`_GoalSummaryRing`),
///   переключатель годов (предыдущий, текущий, следующий), кнопка «Новая цель»
/// - Сетка карточек `GoalCard` (1-3 колонки адаптивно)
/// - Стейты: загрузка, ошибка, пустое состояние («На этот год целей пока нет»)
/// - Хинт внизу: «Завершайте тайтлы — прогресс обновится сам»
/// - Интеграция с `CreateGoalModal` и подтверждение удаления цели через `confirmAction`
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../features/goals/create_goal_modal.dart';
import '../shared/api/api.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/types/dtos.dart';
import '../shared/ui/confirm_dialog.dart';
import '../shared/ui/toast.dart';
import '../widgets/goals/goal_card.dart';

class GoalsView extends ConsumerStatefulWidget {
  final int refreshKey;
  final ValueChanged<String> onOpenMedia;
  final VoidCallback onMediaChanged;

  const GoalsView({
    super.key,
    required this.refreshKey,
    required this.onOpenMedia,
    required this.onMediaChanged,
  });

  @override
  ConsumerState<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends ConsumerState<GoalsView> {
  late final int _currentYear;
  late final List<int> _years;

  late int _year;
  List<GoalDto> _goals = const [];
  bool _loading = true;
  Object? _loadError;
  bool _isCreateOpen = false;

  int _requestSequence = 0;
  int _lastLoadedYear = -1;
  int _lastLoadedRefreshKey = -1;

  @override
  void initState() {
    super.initState();
    _currentYear = DateTime.now().year;
    _years = [_currentYear - 1, _currentYear, _currentYear + 1];
    _year = _currentYear;
    _checkAndLoad();
  }

  @override
  void didUpdateWidget(covariant GoalsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      _checkAndLoad();
    }
  }

  void _checkAndLoad() {
    if (_year == _lastLoadedYear && widget.refreshKey == _lastLoadedRefreshKey) {
      return;
    }
    _lastLoadedYear = _year;
    _lastLoadedRefreshKey = widget.refreshKey;
    _loadGoals(++_requestSequence, _year);
  }

  Future<void> _loadGoals(int sequence, int targetYear) async {
    setState(() {
      _loading = _goals.isEmpty;
      _loadError = null;
    });

    try {
      final loaded = await ref.read(apiClientProvider).getGoals(targetYear);
      if (!mounted) return;
      if (sequence == _requestSequence) {
        setState(() {
          _goals = loaded;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (sequence == _requestSequence) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  int get _completedCount => _goals.where((g) => g.isCompleted).length;

  int get _overallPercent =>
      _goals.isEmpty ? 0 : ((_completedCount / _goals.length) * 100).round();

  Future<void> _removeGoal(GoalDto goal) async {
    final t = ref.read(tProvider);
    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-goal',
        title: t.tf('goals.deleteConfirm', [goal.title]),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    );
    if (!confirmed) return;

    try {
      await ref.read(apiClientProvider).deleteGoal(goal.id);
      if (!mounted) return;
      setState(() => _goals = _goals.where((g) => g.id != goal.id).toList());
      showToast(
        ref,
        ToastOptions(
          title: t.tr('goals.deleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('errors.unexpected'),
          description: t.tr('toast.descRetry'),
          type: ToastType.error,
        ),
      );
    }
  }

  void _onGoalCreated(GoalDto goal) {
    widget.onMediaChanged();
    _loadGoals(++_requestSequence, _year);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final tokens = Theme.of(context).extension<TsundokuTheme>()!;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Top Bar: Ring summary + Year switcher + Create button ──
                  _buildTopBar(t, tokens),
                  const SizedBox(height: 24),

                  // ── Content: Error / Empty / Grid ──────────────────────────
                  if (_loadError != null)
                    _buildErrorBox(t)
                  else if (_goals.isEmpty && !_loading)
                    _buildEmptyBox(t, tokens)
                  else
                    _buildGoalsGrid(t),
                ],
              ),
            ),
          ),
        ),

        // ── Modal ──────────────────────────────────────────────────
        if (_isCreateOpen)
          CreateGoalModal(
            isOpen: _isCreateOpen,
            year: _year,
            onClose: () => setState(() => _isCreateOpen = false),
            onCreated: _onGoalCreated,
          ),
      ],
    );
  }

  Widget _buildTopBar(I18nDictionary t, TsundokuTheme tokens) {
    final percent = _overallPercent;
    final done = _completedCount;
    final total = _goals.length;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: [
        // Left: Summary ring + text
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GoalSummaryRing(percent: percent),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.tf('goals.summaryOf', [done, total]),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.tr('goals.overallProgress'),
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Right: Year buttons + Create button
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            // Year switcher
            Container(
              decoration: BoxDecoration(
                color: tokens.bgElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _years.map((y) {
                  final isSelected = _year == y;
                  return InkWell(
                    onTap: () {
                      if (_year == y) return;
                      setState(() => _year = y);
                      _checkAndLoad();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? tokens.accentBright.withAlpha(51) // bg-accent-bright/20
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        y.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFFA5B4FC)
                              : tokens.textMuted,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Create button
            ElevatedButton.icon(
              onPressed: () => setState(() => _isCreateOpen = true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5446CF),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side:
                      BorderSide(color: const Color(0xFF818CF8).withAlpha(102)),
                ),
              ),
              icon: const Icon(LucideIcons.trophy, size: 16),
              label: Text(
                t.tr('goals.createGoal'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorBox(I18nDictionary t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFB7185).withAlpha(26), // rose-400/10
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFB7185).withAlpha(64)),
      ),
      child: Row(
        children: [
          const Text('!',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFECDD3))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.tr('goals.loadFailed'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFFECDD3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBox(I18nDictionary t, TsundokuTheme tokens) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: tokens.bgCard.withAlpha(128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withAlpha(26),
          style: BorderStyle.solid,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        t.tr('goals.empty'),
        style: TextStyle(
          fontSize: 14,
          color: tokens.textMuted,
        ),
      ),
    );
  }

  Widget _buildGoalsGrid(I18nDictionary t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1100
                ? 3
                : width >= 700
                    ? 2
                    : 1;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _goals.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
              ),
              itemBuilder: (context, index) {
                final goal = _goals[index];
                return GoalCard(
                  goal: goal,
                  onOpenMedia: widget.onOpenMedia,
                  onDelete: (g) => _removeGoal(g),
                );
              },
            );
          },
        ),
        if (_goals.isNotEmpty && _completedCount == 0) ...[
          const SizedBox(height: 16),
          Text(
            t.tr('goals.finishHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .extension<TsundokuTheme>()!
                  .textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Radial Progress Summary Ring ─────────────────────────────────────────────
class _GoalSummaryRing extends StatelessWidget {
  final int percent;

  const _GoalSummaryRing({required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(80, 80),
            painter: _RingPainter(percent: percent),
          ),
          Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int percent;

  _RingPainter({required this.percent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 34.0;
    const strokeWidth = 7.0;

    final trackPaint = Paint()
      ..color = const Color(0xFF2A3040)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    if (percent > 0) {
      final sweepAngle = (percent / 100.0) * 2 * math.pi;
      final progressPaint = Paint()
        ..color = const Color(0xFF818CF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent;
}
