import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';
import 'package:tsundoku_flutter/widgets/stats/activity_heatmap.dart';
import 'package:tsundoku_flutter/widgets/stats/backlog_health.dart';
import 'package:tsundoku_flutter/widgets/stats/monthly_activity_chart.dart';
import 'package:tsundoku_flutter/widgets/stats/rating_psychology.dart';
import 'package:tsundoku_flutter/widgets/stats/stats_hero_banner.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/critical_divergence_card.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/drop_analytics_card.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/era_affinity_card.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_paradox_card.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_radar_chart.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/sunk_cost_card.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/taste_persona_card.dart';
import 'package:tsundoku_flutter/widgets/stats/time_distribution_donut.dart';
import 'package:tsundoku_flutter/widgets/stats/top_genres_bar.dart';
import 'package:tsundoku_flutter/widgets/stats/tracker_badges.dart';

enum _StatsTab { summary, taste }

/// 1:1 порт `mediatracker-ui/src/views/StatsView.svelte`.
///
/// Экран детальной статистики:
/// - Переключатель вкладок «Сводка» / «Профиль вкуса»
/// - Селектор области учета «Только завершённые» / «Вся библиотека» (uiSettings.statsScope)
/// - Вкладка «Сводка»: Hero banner, диаграмма времени, психология оценок,
///   помесячная активность, тепловая карта, топ жанров, индекс Цундоку, бейджи
/// - Вкладка «Профиль вкуса»: архетип вкуса, радар жанров, золотая эпоха,
///   синдром потерянного времени, анатомия дропа, я против мира, парадокс жанров
class StatsView extends ConsumerStatefulWidget {
  final int refreshKey;
  final ValueChanged<String>? onOpenMedia;
  final VoidCallback? onOpenStaleBacklog;

  const StatsView({
    super.key,
    this.refreshKey = 0,
    this.onOpenMedia,
    this.onOpenStaleBacklog,
  });

  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  _StatsTab _activeTab = _StatsTab.summary;
  AdvancedStats? _stats;
  TasteProfile? _profile;
  bool _loading = true;
  Object? _loadError;
  Object? _profileError;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    final scope = ref.read(uiSettingsProvider).statsScope;
    _loadStats(++_requestSequence, scope);
  }

  @override
  void didUpdateWidget(covariant StatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey) {
      final scope = ref.read(uiSettingsProvider).statsScope;
      _loadStats(++_requestSequence, scope);
    }
  }

  Future<void> _loadStats(int sequence, String scope) async {
    setState(() {
      _loading = true;
      _loadError = null;
      _profileError = null;
    });

    final api = ref.read(apiClientProvider);

    try {
      final results = await Future.wait([
        api
            .getAdvancedStats(scope: scope)
            .then<Object?>((v) => v, onError: (e) => e),
        api
            .getTasteProfile(scope: scope)
            .then<Object?>((v) => v, onError: (e) => e),
      ]);

      if (sequence != _requestSequence || !mounted) return;

      final statsResult = results[0];
      final profileResult = results[1];

      setState(() {
        if (statsResult is AdvancedStats) {
          _stats = statsResult;
        } else {
          _stats = null;
          _loadError = statsResult;
        }

        if (profileResult is TasteProfile) {
          _profile = profileResult;
        } else {
          _profile = null;
          _profileError = profileResult;
        }

        _loading = false;
      });
    } catch (e) {
      if (sequence != _requestSequence || !mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _retry() {
    final scope = ref.read(uiSettingsProvider).statsScope;
    _loadStats(++_requestSequence, scope);
  }

  void _setScope(String scope) {
    final currentScope = ref.read(uiSettingsProvider).statsScope;
    if (currentScope == scope) return;
    ref.read(uiSettingsProvider.notifier).setStatsScope(scope);
    _loadStats(++_requestSequence, scope);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;
    final currentScope = ref.watch(uiSettingsProvider).statsScope;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1152), // max-w-6xl
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              // Шапка с переключателями вкладок и области учета
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSm = constraints.maxWidth >= 640; // sm:flex-row

                  final tabList = Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(8), // bg-white/[0.03]
                      border: Border.all(
                        color: Colors.white.withAlpha(13), // border-white/5
                      ),
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                    ),
                    padding: const EdgeInsets.all(4), // p-1
                    child: Row(
                      mainAxisSize: isSm ? MainAxisSize.min : MainAxisSize.max,
                      children: [
                        _TabButton(
                          icon: LucideIcons.barChart3,
                          label: t.tr('stats.tabSummary'),
                          isActive: _activeTab == _StatsTab.summary,
                          accentColor: theme.accentBright,
                          onTap: () => setState(
                            () => _activeTab = _StatsTab.summary,
                          ),
                          isFullWidth: !isSm,
                        ),
                        const SizedBox(width: 4),
                        _TabButton(
                          icon: LucideIcons.sparkles,
                          label: t.tr('stats.tabTaste'),
                          isActive: _activeTab == _StatsTab.taste,
                          accentColor: theme.accentBright,
                          onTap: () => setState(
                            () => _activeTab = _StatsTab.taste,
                          ),
                          isFullWidth: !isSm,
                        ),
                      ],
                    ),
                  );

                  final scopeRadios = Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(8), // bg-white/[0.03]
                      border: Border.all(
                        color: Colors.white.withAlpha(13), // border-white/5
                      ),
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                    ),
                    padding: const EdgeInsets.all(4), // p-1
                    child: Row(
                      mainAxisSize: isSm ? MainAxisSize.min : MainAxisSize.max,
                      children: [
                        _ScopeButton(
                          label: t.tr('stats.scopeCompleted'),
                          isActive: currentScope == 'completed',
                          activeBgColor: const Color(0x3310B981), // emerald-500/20
                          activeTextColor: const Color(0xFF6EE7B7), // emerald-300
                          onTap: () => _setScope('completed'),
                          isFullWidth: !isSm,
                        ),
                        const SizedBox(width: 4),
                        _ScopeButton(
                          label: t.tr('stats.scopeAll'),
                          isActive: currentScope == 'all',
                          activeBgColor: const Color(0x33F59E0B), // amber-500/20
                          activeTextColor: const Color(0xFFFCD34D), // amber-300
                          onTap: () => _setScope('all'),
                          isFullWidth: !isSm,
                        ),
                      ],
                    ),
                  );

                  if (isSm) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [tabList, scopeRadios],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tabList,
                        const SizedBox(height: 12),
                        scopeRadios,
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 24), // space-y-6

              // Тело экрана: загрузка / ошибка / контент вкладки
              if (_loading)
                const _StatsSkeleton()
              else if (_activeTab == _StatsTab.summary)
                if (_loadError != null)
                  _ErrorBox(
                    errorText: errorMessage(_loadError!, locale),
                    retryLabel: t.tr('common.retry'),
                    accentColor: theme.accent,
                    onRetry: _retry,
                  )
                else if (_stats != null) ...[
                  StatsHeroBanner(stats: _stats!),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isLg = constraints.maxWidth >= 1024; // lg:grid-cols-12
                      if (isLg) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151A26),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(13),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(20),
                                child: TimeDistributionDonut(stats: _stats!),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151A26),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(13),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(20),
                                child: RatingPsychology(stats: _stats!),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF151A26),
                                border: Border.all(
                                  color: Colors.white.withAlpha(13),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: TimeDistributionDonut(stats: _stats!),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF151A26),
                                border: Border.all(
                                  color: Colors.white.withAlpha(13),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: RatingPsychology(stats: _stats!),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  MonthlyActivityChart(completions: _stats!.monthlyCompletions),
                  const SizedBox(height: 24),
                  ActivityHeatmap(
                    dailyActivity: _stats!.dailyActivity,
                  ),
                  const SizedBox(height: 24),
                  TopGenresBar(
                    genres: _stats!.topGenres,
                    genresByType: _stats!.topGenresByType,
                  ),
                  const SizedBox(height: 24),
                  BacklogHealth(
                    stats: _stats!,
                    onMediaChanged: () {
                      final scope = ref.read(uiSettingsProvider).statsScope;
                      _loadStats(++_requestSequence, scope);
                    },
                    onOpenStaleBacklog: widget.onOpenStaleBacklog,
                  ),
                  const SizedBox(height: 24),
                  TrackerBadges(stats: _stats!),
                ] else
                  const SizedBox.shrink()
              else if (_activeTab == _StatsTab.taste)
                if (_profileError != null)
                  _ErrorBox(
                    errorText: errorMessage(_profileError!, locale),
                    retryLabel: t.tr('common.retry'),
                    accentColor: theme.accent,
                    onRetry: _retry,
                  )
                else if (_profile != null) ...[
                  TastePersonaCard(persona: _profile!.persona),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isLg = constraints.maxWidth >= 1024; // lg:grid-cols-2
                      if (isLg) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GenreRadarChart(axes: _profile!.genreRadar),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: EraAffinityCard(eras: _profile!.eraAffinity),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            GenreRadarChart(axes: _profile!.genreRadar),
                            const SizedBox(height: 24),
                            EraAffinityCard(eras: _profile!.eraAffinity),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SunkCostCard(sunkCost: _profile!.sunkCost),
                  if (_profile!.dropAnalytics != null) ...[
                    const SizedBox(height: 24),
                    DropAnalyticsCard(analytics: _profile!.dropAnalytics!),
                  ],
                  const SizedBox(height: 24),
                  CriticalDivergenceCard(
                    divergence: _profile!.divergence,
                    onOpenMedia: widget.onOpenMedia,
                  ),
                  const SizedBox(height: 24),
                  GenreParadoxCard(paradox: _profile!.genreParadox),
                ],
            ],
          ),
        ),
      );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
    required this.isFullWidth,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36, // h-9
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withAlpha(77) // bg-accent-bright/30
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return isFullWidth ? Expanded(child: content) : content;
  }
}

class _ScopeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeBgColor;
  final Color activeTextColor;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _ScopeButton({
    required this.label,
    required this.isActive,
    required this.activeBgColor,
    required this.activeTextColor,
    required this.onTap,
    required this.isFullWidth,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36, // h-9
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? activeBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? activeTextColor : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );

    return isFullWidth ? Expanded(child: content) : content;
  }
}

class _ErrorBox extends StatelessWidget {
  final String errorText;
  final String retryLabel;
  final Color accentColor;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.errorText,
    required this.retryLabel,
    required this.accentColor,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 288), // min-h-72
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0DF43F5E), // bg-rose-500/5
        border: Border.all(color: const Color(0x1AF43F5E)), // border-rose-500/10
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            errorText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFFDA4AF), // text-rose-300
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: accentColor,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onRetry,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.refreshCw,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      retryLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero skeleton
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),

        // Donut & Psychology skeleton
        Row(
          children: [
            Expanded(
              child: Container(
                height: 256,
                decoration: BoxDecoration(
                  color: const Color(0xFF151A26),
                  border: Border.all(color: Colors.white.withAlpha(13)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Container(
                height: 256,
                decoration: BoxDecoration(
                  color: const Color(0xFF151A26),
                  border: Border.all(color: Colors.white.withAlpha(13)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Monthly chart & heatmap skeleton
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF151A26),
            border: Border.all(color: Colors.white.withAlpha(13)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFF151A26),
            border: Border.all(color: Colors.white.withAlpha(13)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }
}
