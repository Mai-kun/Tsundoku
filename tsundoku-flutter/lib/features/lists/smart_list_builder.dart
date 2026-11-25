/// 1:1 port of `mediatracker-ui/src/features/lists/SmartListBuilder.svelte`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/media_labels.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/segmented_control.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';

class SmartListBuilder extends ConsumerStatefulWidget {
  final SmartListQuery query;
  final ValueChanged<SmartListQuery> onQueryChange;
  final List<MediaItem> allMedia;
  final ValueChanged<List<MediaItem>>? onMatchesChange;

  const SmartListBuilder({
    super.key,
    required this.query,
    required this.onQueryChange,
    required this.allMedia,
    this.onMatchesChange,
  });

  @override
  ConsumerState<SmartListBuilder> createState() => _SmartListBuilderState();
}

class _SmartListBuilderState extends ConsumerState<SmartListBuilder> {
  late final TextEditingController _creatorController;
  late final TextEditingController _minScoreController;
  late final TextEditingController _minRatingController;
  late final TextEditingController _yearFromController;
  late final TextEditingController _yearToController;
  late final TextEditingController _durationController;
  late final TextEditingController _episodesController;
  late final TextEditingController _pagesController;
  late final TextEditingController _chaptersController;
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    _creatorController =
        TextEditingController(text: widget.query.creatorContains ?? '');
    _minScoreController =
        TextEditingController(text: widget.query.minScore?.toString() ?? '');
    _minRatingController = TextEditingController(
        text: widget.query.minExternalRating?.toString() ?? '');
    _yearFromController = TextEditingController(
        text: widget.query.releaseYearFrom?.toString() ?? '');
    _yearToController = TextEditingController(
        text: widget.query.releaseYearTo?.toString() ?? '');
    _durationController = TextEditingController(
        text: widget.query.maxDurationMinutes?.toString() ?? '');
    _episodesController = TextEditingController(
        text: widget.query.maxEpisodes?.toString() ?? '');
    _pagesController =
        TextEditingController(text: widget.query.maxPages?.toString() ?? '');
    _chaptersController =
        TextEditingController(text: widget.query.maxChapters?.toString() ?? '');
    _limitController =
        TextEditingController(text: widget.query.limit?.toString() ?? '');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluateAndReport();
    });
  }

  @override
  void didUpdateWidget(covariant SmartListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query || widget.allMedia != oldWidget.allMedia) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _evaluateAndReport();
      });
    }
  }

  @override
  void dispose() {
    _creatorController.dispose();
    _minScoreController.dispose();
    _minRatingController.dispose();
    _yearFromController.dispose();
    _yearToController.dispose();
    _durationController.dispose();
    _episodesController.dispose();
    _pagesController.dispose();
    _chaptersController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  void _evaluateAndReport() {
    final matches = evaluateLocally(widget.allMedia, widget.query);
    widget.onMatchesChange?.call(matches);
  }

  void _toggleCategory(String cat) {
    final current = widget.query.categories ?? const <String>[];
    final next = current.contains(cat)
        ? current.where((c) => c != cat).toList()
        : [...current, cat];
    widget.onQueryChange(
        widget.query.copyWith(categories: next.isNotEmpty ? next : null));
  }

  void _toggleStatus(int status) {
    final current = widget.query.statuses ?? const <int>[];
    final next = current.contains(status)
        ? current.where((s) => s != status).toList()
        : [...current, status];
    widget.onQueryChange(
        widget.query.copyWith(statuses: next.isNotEmpty ? next : null));
  }

  void _applyPreset(SmartListQuery presetQuery) {
    widget.onQueryChange(presetQuery);
    _creatorController.text = presetQuery.creatorContains ?? '';
    _minScoreController.text = presetQuery.minScore?.toString() ?? '';
    _minRatingController.text =
        presetQuery.minExternalRating?.toString() ?? '';
    _yearFromController.text = presetQuery.releaseYearFrom?.toString() ?? '';
    _yearToController.text = presetQuery.releaseYearTo?.toString() ?? '';
    _durationController.text =
        presetQuery.maxDurationMinutes?.toString() ?? '';
    _episodesController.text = presetQuery.maxEpisodes?.toString() ?? '';
    _pagesController.text = presetQuery.maxPages?.toString() ?? '';
    _chaptersController.text = presetQuery.maxChapters?.toString() ?? '';
    _limitController.text = presetQuery.limit?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Presets
        _buildSection(
          title: t.tr('views.smartPresets'),
          showDivider: false,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                icon: '🏆',
                label: t.tr('views.smartPresetMasterpieces'),
                onTap: () => _applyPreset(const SmartListQuery(
                  minScore: 9,
                  sortBy: 'score',
                  sortOrder: 'desc',
                )),
              ),
              _buildPresetChip(
                icon: '🎬',
                label: t.tr('views.smartPresetMovieNight'),
                onTap: () => _applyPreset(const SmartListQuery(
                  categories: ['movie'],
                  statuses: [0],
                  maxDurationMinutes: 100,
                )),
              ),
              _buildPresetChip(
                icon: '⚡',
                label: t.tr('views.smartPresetShortAnime'),
                onTap: () => _applyPreset(const SmartListQuery(
                  categories: ['anime'],
                  statuses: [0],
                  maxEpisodes: 13,
                )),
              ),
              _buildPresetChip(
                icon: '💎',
                label: t.tr('views.smartPresetHighRated'),
                onTap: () => _applyPreset(const SmartListQuery(
                  statuses: [0],
                  minExternalRating: 8.0,
                  sortBy: 'externalRating',
                  sortOrder: 'desc',
                )),
              ),
              _buildPresetChip(
                icon: '📚',
                label: t.tr('views.smartPresetShortBooks'),
                onTap: () => _applyPreset(const SmartListQuery(
                  categories: ['book'],
                  statuses: [0],
                  maxPages: 250,
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Scope: categories + statuses + releaseStatus
        _buildSection(
          title: t.tr('views.smartSectionScope'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Categories
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ('game', t.tr('views.smartCategoryGame')),
                  ('anime', t.tr('views.smartCategoryAnime')),
                  ('manga', t.tr('views.smartCategoryManga')),
                  ('movie', t.tr('views.smartCategoryMovie')),
                  ('tvshow', t.tr('views.smartCategoryTvShow')),
                  ('book', t.tr('views.smartCategoryBook')),
                ].map((item) {
                  final active =
                      (widget.query.categories ?? const []).contains(item.$1);
                  return _buildFilterPill(
                    label: item.$2,
                    active: active,
                    activeColor: const Color(0xFFC4B5FD), // violet-300
                    activeBorderColor: const Color(0x668B5CF6), // border-violet-500/40
                    activeBgColor: const Color(0x268B5CF6), // bg-violet-500/15
                    onTap: () => _toggleCategory(item.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Statuses
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  (0, statusLabel(MediaStatus.planned, t)),
                  (1, statusLabel(MediaStatus.inProgress, t)),
                  (2, statusLabel(MediaStatus.completed, t)),
                  (3, statusLabel(MediaStatus.onHold, t)),
                  (4, statusLabel(MediaStatus.dropped, t)),
                ].map((item) {
                  final active =
                      (widget.query.statuses ?? const []).contains(item.$1);
                  return _buildFilterPill(
                    label: item.$2,
                    active: active,
                    activeColor: const Color(0xFFFCD34D), // amber-300
                    activeBorderColor: const Color(0x66F59E0B), // border-amber-500/40
                    activeBgColor: const Color(0x26F59E0B), // bg-amber-500/15
                    onTap: () => _toggleStatus(item.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Release Status
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 256),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartReleaseStatusLabel'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: widget.query.releaseStatus ?? '',
                      dropdownColor: const Color(0xFF1E2230),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F1219),
                        constraints:
                            const BoxConstraints(minHeight: 36, maxHeight: 36),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                      ),
                      items: [
                        ('', t.tr('views.smartReleaseStatusAny')),
                        ('FINISHED', t.tr('views.smartReleaseStatusFinished')),
                        ('RELEASING', t.tr('views.smartReleaseStatusReleasing')),
                        ('NOT_YET_RELEASED',
                            t.tr('views.smartReleaseStatusAnnounced')),
                      ].map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt.$1,
                          child: Text(opt.$2),
                        );
                      }).toList(),
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          releaseStatus: val != null && val.isNotEmpty ? val : null,
                        ));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Quality & Score
        _buildSection(
          title: t.tr('views.smartSectionQuality'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Min Score
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartMinScore'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: _minScoreController,
                      keyboardType: TextInputType.number,
                      placeholder: '1–10',
                      prefixIcon: const Icon(
                        LucideIcons.star,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val.trim());
                        widget.onQueryChange(widget.query.copyWith(
                          minScore: parsed,
                        ));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Min External Rating
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartMinExternalRating'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: _minRatingController,
                      keyboardType: TextInputType.number,
                      placeholder: '0–10',
                      prefixIcon: const Icon(
                        LucideIcons.star,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val.trim());
                        widget.onQueryChange(widget.query.copyWith(
                          minExternalRating: parsed,
                        ));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Only Unrated checkbox
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: InkWell(
                  onTap: () {
                    final next = !(widget.query.onlyUnrated ?? false);
                    widget.onQueryChange(widget.query.copyWith(
                      onlyUnrated: next ? true : null,
                    ));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: widget.query.onlyUnrated ?? false,
                        activeColor: const Color(0xFF8B5CF6),
                        onChanged: (val) {
                          widget.onQueryChange(widget.query.copyWith(
                            onlyUnrated: val == true ? true : null,
                          ));
                        },
                      ),
                      Text(
                        t.tr('views.smartOnlyUnrated'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Volumes (2x2 grid)
        _buildSection(
          title: t.tr('views.smartSectionVolumes'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildVolumeField(
                      label: t.tr('views.smartMaxDuration'),
                      hint: t.tr('views.smartMaxDurationPlaceholder'),
                      unit: t.tr('views.smartUnitMinutes'),
                      controller: _durationController,
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          maxDurationMinutes: int.tryParse(val.trim()),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildVolumeField(
                      label: t.tr('views.smartMaxEpisodes'),
                      hint: t.tr('views.smartMaxEpisodesPlaceholder'),
                      unit: t.tr('views.smartUnitEpisodes'),
                      controller: _episodesController,
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          maxEpisodes: int.tryParse(val.trim()),
                        ));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildVolumeField(
                      label: t.tr('views.smartMaxPages'),
                      hint: t.tr('views.smartMaxPagesPlaceholder'),
                      unit: t.tr('views.smartUnitPages'),
                      controller: _pagesController,
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          maxPages: int.tryParse(val.trim()),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildVolumeField(
                      label: t.tr('views.smartMaxChapters'),
                      hint: t.tr('views.smartMaxChaptersPlaceholder'),
                      unit: t.tr('views.smartUnitChapters'),
                      controller: _chaptersController,
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          maxChapters: int.tryParse(val.trim()),
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Period and authorship
        _buildSection(
          title: t.tr('views.smartSectionPeriod'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tr('views.smartYearFrom'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TsundokuTextField(
                          controller: _yearFromController,
                          keyboardType: TextInputType.number,
                          placeholder: '2000',
                          onChanged: (val) {
                            widget.onQueryChange(widget.query.copyWith(
                              releaseYearFrom: int.tryParse(val.trim()),
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tr('views.smartYearTo'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TsundokuTextField(
                          controller: _yearToController,
                          keyboardType: TextInputType.number,
                          placeholder: '2024',
                          onChanged: (val) {
                            widget.onQueryChange(widget.query.copyWith(
                              releaseYearTo: int.tryParse(val.trim()),
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tr('views.smartCreator'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TsundokuTextField(
                    controller: _creatorController,
                    placeholder: t.tr('views.smartCreatorPlaceholder'),
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    onChanged: (val) {
                      widget.onQueryChange(widget.query.copyWith(
                        creatorContains: val.trim().isNotEmpty ? val.trim() : null,
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 6. Sort and Limit
        _buildSection(
          title: t.tr('views.smartSectionSort'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartSortBy'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: widget.query.sortBy ?? 'createdAt',
                      dropdownColor: const Color(0xFF1E2230),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F1219),
                        constraints:
                            const BoxConstraints(minHeight: 36, maxHeight: 36),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                      ),
                      items: [
                        ('createdAt', t.tr('views.smartSortCreatedAt')),
                        ('score', t.tr('views.smartSortScore')),
                        ('externalRating', t.tr('views.smartSortExternalRating')),
                        ('releaseYear', t.tr('views.smartSortReleaseYear')),
                        ('title', t.tr('views.smartSortTitle')),
                      ].map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt.$1,
                          child: Text(opt.$2),
                        );
                      }).toList(),
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          sortBy: val ?? 'createdAt',
                        ));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartSortOrder'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: widget.query.sortOrder ?? 'desc',
                      dropdownColor: const Color(0xFF1E2230),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F1219),
                        constraints:
                            const BoxConstraints(minHeight: 36, maxHeight: 36),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                      ),
                      items: [
                        ('desc', t.tr('views.smartSortDesc')),
                        ('asc', t.tr('views.smartSortAsc')),
                      ].map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt.$1,
                          child: Text(opt.$2),
                        );
                      }).toList(),
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          sortOrder: val ?? 'desc',
                        ));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('views.smartLimit'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: _limitController,
                      keyboardType: TextInputType.number,
                      placeholder: '50',
                      onChanged: (val) {
                        widget.onQueryChange(widget.query.copyWith(
                          limit: int.tryParse(val.trim()),
                        ));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider) ...[
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
        ],
        TsundokuSectionHeader(title),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildPresetChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2230),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x0DFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool active,
    required Color activeColor,
    required Color activeBorderColor,
    required Color activeBgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(9999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: active ? activeBorderColor : const Color(0x1AFFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: active ? activeColor : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeField({
    required String label,
    required String hint,
    required String unit,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        TsundokuTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          placeholder: hint,
          suffix: Text(
            unit,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

bool matchesCategory(MediaItem item, String cat) {
  switch (cat) {
    case 'anime':
      return (item.type == MediaType.tvshow || item.type == MediaType.movie) &&
          item.isAnime == true;
    case 'tvshow':
      return item.type == MediaType.tvshow && item.isAnime != true;
    case 'movie':
      return item.type == MediaType.movie && item.isAnime != true;
    case 'game':
      return item.type == MediaType.game;
    case 'manga':
      return item.type == MediaType.manga;
    case 'book':
      return item.type == MediaType.book;
    default:
      return false;
  }
}

String getCreatorString(MediaItem item) {
  switch (item.type) {
    case MediaType.movie:
      return [item.studio, item.director]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
    case MediaType.tvshow:
    case MediaType.game:
      return item.studio ?? '';
    case MediaType.book:
    case MediaType.manga:
      return item.author ?? '';
  }
}

List<MediaItem> evaluateLocally(List<MediaItem> items, SmartListQuery q) {
  var result = items;
  if (q.categories != null && q.categories!.isNotEmpty) {
    result = result
        .where((item) => q.categories!.any((cat) => matchesCategory(item, cat)))
        .toList();
  }
  if (q.statuses != null && q.statuses!.isNotEmpty) {
    result = result
        .where((item) => q.statuses!.contains(item.status.value))
        .toList();
  }
  if (q.onlyUnrated == true) {
    result = result
        .where((item) => item.score == null || item.score! <= 0)
        .toList();
  } else {
    if (q.minScore != null) {
      result =
          result.where((item) => (item.score ?? 0) >= q.minScore!).toList();
    }
    if (q.maxScore != null) {
      result =
          result.where((item) => (item.score ?? 0) <= q.maxScore!).toList();
    }
  }
  if (q.minExternalRating != null) {
    result = result
        .where((item) => (item.externalRating ?? 0) >= q.minExternalRating!)
        .toList();
  }
  if (q.releaseYearFrom != null) {
    result = result.where((item) {
      final year = item.releaseYear ??
          (item.releaseDate != null
              ? DateTime.tryParse(item.releaseDate!)?.year
              : null);
      return year != null && year >= q.releaseYearFrom!;
    }).toList();
  }
  if (q.releaseYearTo != null) {
    result = result.where((item) {
      final year = item.releaseYear ??
          (item.releaseDate != null
              ? DateTime.tryParse(item.releaseDate!)?.year
              : null);
      return year != null && year <= q.releaseYearTo!;
    }).toList();
  }
  if (q.maxDurationMinutes != null) {
    result = result.where((item) {
      if (item.type == MediaType.movie) {
        return (item.durationMinutes ?? 0) > 0 &&
            item.durationMinutes! <= q.maxDurationMinutes!;
      }
      if (item.type == MediaType.tvshow) {
        final dur = item.episodeDurationMinutes ?? item.durationMinutes ?? 24;
        return dur <= q.maxDurationMinutes!;
      }
      return true;
    }).toList();
  }
  if (q.maxEpisodes != null) {
    result = result.where((item) {
      if (item.type == MediaType.tvshow) {
        return (item.totalEpisodesCount ?? 0) > 0 &&
            item.totalEpisodesCount! <= q.maxEpisodes!;
      }
      return true;
    }).toList();
  }
  if (q.maxPages != null) {
    result = result.where((item) {
      if (item.type == MediaType.book) {
        return (item.totalPages ?? 0) > 0 && item.totalPages! <= q.maxPages!;
      }
      return true;
    }).toList();
  }
  if (q.maxChapters != null) {
    result = result.where((item) {
      if (item.type == MediaType.manga) {
        return item.totalChapters != null &&
            item.totalChapters! > 0 &&
            item.totalChapters! <= q.maxChapters!;
      }
      return true;
    }).toList();
  }
  if (q.creatorContains != null && q.creatorContains!.trim().isNotEmpty) {
    final needle = q.creatorContains!.toLowerCase();
    result = result
        .where((item) => getCreatorString(item).toLowerCase().contains(needle))
        .toList();
  }

  final desc = q.sortOrder != 'asc';
  final sorted = [...result];
  sorted.sort((a, b) {
    switch (q.sortBy) {
      case 'score':
        final sa = a.score ?? 0;
        final sb = b.score ?? 0;
        return desc ? sb.compareTo(sa) : sa.compareTo(sb);
      case 'externalRating':
        final ra = a.externalRating ?? 0.0;
        final rb = b.externalRating ?? 0.0;
        return desc ? rb.compareTo(ra) : ra.compareTo(rb);
      case 'releaseYear':
        final ya = a.releaseYear ?? 0;
        final yb = b.releaseYear ?? 0;
        return desc ? yb.compareTo(ya) : ya.compareTo(yb);
      case 'title':
        return desc ? b.title.compareTo(a.title) : a.title.compareTo(b.title);
      case 'createdAt':
      default:
        final ta = DateTime.tryParse(a.createdAt)?.millisecondsSinceEpoch ?? 0;
        final tb = DateTime.tryParse(b.createdAt)?.millisecondsSinceEpoch ?? 0;
        return desc ? tb.compareTo(ta) : ta.compareTo(tb);
    }
  });

  if (q.limit != null && q.limit! > 0 && sorted.length > q.limit!) {
    return sorted.sublist(0, q.limit!);
  }
  return sorted;
}
