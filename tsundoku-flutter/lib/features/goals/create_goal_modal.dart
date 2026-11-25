/// 1:1 port of `mediatracker-ui/src/features/goals/CreateGoalModal.svelte`.
///
/// Модалка создания цели: две вкладки — «Шаблоны» (быстрый выбор популярных целей)
/// и «Своя цель» (ручной ввод названия, года, целевого числа, категории через Select,
/// эмодзи-иконки и описания).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/dtos.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/popover_menu.dart';
import '../../shared/ui/text_field.dart';

class CreateGoalModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final int year;
  final VoidCallback onClose;
  final ValueChanged<GoalDto> onCreated;

  const CreateGoalModal({
    super.key,
    required this.isOpen,
    required this.year,
    required this.onClose,
    required this.onCreated,
  });

  @override
  ConsumerState<CreateGoalModal> createState() => _CreateGoalModalState();
}

class _CreateGoalModalState extends ConsumerState<CreateGoalModal> {
  String _tab = 'templates'; // 'templates' | 'custom'
  bool _busy = false;
  String _error = '';

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _iconController;
  late final TextEditingController _yearController;
  late final TextEditingController _targetController;
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _iconController = TextEditingController(text: '🎯');
    _yearController = TextEditingController(text: widget.year.toString());
    _targetController = TextEditingController(text: '10');
  }

  @override
  void didUpdateWidget(covariant CreateGoalModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      _tab = 'templates';
      _busy = false;
      _error = '';
      _titleController.text = '';
      _descriptionController.text = '';
      _iconController.text = '🎯';
      _yearController.text = widget.year.toString();
      _targetController.text = '10';
      _category = 'all';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _iconController.dispose();
    _yearController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _submit(CreateGoalPayload payload) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      final goal = await ref.read(apiClientProvider).createGoal(payload);
      if (!mounted) return;
      widget.onCreated(goal);
      widget.onClose();
    } catch (_) {
      if (!mounted) return;
      final t = ref.read(tProvider);
      setState(() {
        _error = t.tr('goals.modal.createFailed');
        _busy = false;
      });
    }
  }

  void _submitCustom() {
    final title = _titleController.text.trim();
    final targetCount = int.tryParse(_targetController.text.trim()) ?? 0;
    final year = int.tryParse(_yearController.text.trim()) ?? widget.year;
    final desc = _descriptionController.text.trim();
    final icon = _iconController.text.trim();

    if (title.isEmpty || targetCount < 1) return;

    _submit(CreateGoalPayload(
      title: title,
      description: desc.isNotEmpty ? desc : null,
      icon: icon.isNotEmpty ? icon : '🎯',
      year: year,
      targetCount: targetCount,
      category: _category,
      smartQueryJson: null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final tokens = Theme.of(context).extension<TsundokuTheme>()!;

    final goalYear = int.tryParse(_yearController.text.trim()) ?? widget.year;

    final categoryOptions = [
      PopoverOption(value: 'all', label: t.tr('goals.modal.categoryAll')),
      PopoverOption(value: 'book', label: t.tr('navigation.book')),
      PopoverOption(value: 'movie', label: t.tr('navigation.movie')),
      PopoverOption(value: 'anime', label: t.tr('navigation.anime')),
      PopoverOption(value: 'manga', label: t.tr('navigation.manga')),
      PopoverOption(value: 'game', label: t.tr('navigation.game')),
      PopoverOption(value: 'tvshow', label: t.tr('navigation.tvshow')),
    ];

    final templates = [
      (
        title: t.tf('goals.modal.templateBooks', [15]),
        icon: '📚',
        target: 15,
        category: 'book',
        smartQueryJson: null,
      ),
      (
        title: t.tf('goals.modal.templateGames', [10]),
        icon: '🎮',
        target: 10,
        category: 'game',
        smartQueryJson: null,
      ),
      (
        title: t.tf('goals.modal.templateAnime', [30]),
        icon: '🍥',
        target: 30,
        category: 'anime',
        smartQueryJson: null,
      ),
      (
        title: t.tf('goals.modal.templateRetro', [5]),
        icon: '🕹️',
        target: 5,
        category: 'movie',
        smartQueryJson: '{"releaseYearTo":1999,"sortOrder":"desc"}',
      ),
    ];

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0), // p-6
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal header
            Row(
              children: [
                Container(
                  width: 36, // size-9
                  height: 36,
                  decoration: BoxDecoration(
                    color: tokens.bgElevated,
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                    border: Border.all(
                        color: Colors.white.withAlpha(20)), // border-white/[0.08]
                  ),
                  child: const Icon(
                    LucideIcons.trophy,
                    size: 17,
                    color: Color(0xFF818CF8),
                  ),
                ),
                const SizedBox(width: 10), // gap-2.5
                Text(
                  t.tr('goals.modal.createTitle'),
                  style: TextStyle(
                    fontSize: 16, // text-base
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab switcher
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tab = 'templates'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _tab == 'templates'
                            ? tokens.accent.withAlpha(38)
                            : tokens.bgCard.withAlpha(153),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _tab == 'templates'
                              ? const Color(0xFF818CF8).withAlpha(102)
                              : Colors.white.withAlpha(26),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.sparkles,
                            size: 14,
                            color: _tab == 'templates'
                                ? const Color(0xFFA5B4FC)
                                : tokens.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.tr('goals.modal.templatesTab'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _tab == 'templates'
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _tab == 'templates'
                                  ? const Color(0xFFA5B4FC)
                                  : tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tab = 'custom'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == 'custom'
                            ? tokens.accent.withAlpha(38)
                            : tokens.bgCard.withAlpha(153),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _tab == 'custom'
                              ? const Color(0xFF818CF8).withAlpha(102)
                              : Colors.white.withAlpha(26),
                        ),
                      ),
                      child: Text(
                        t.tr('goals.modal.customTab'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _tab == 'custom'
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _tab == 'custom'
                              ? const Color(0xFFA5B4FC)
                              : tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Content
            if (_tab == 'templates')
              Column(
                children: templates.map((tmpl) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () {
                              _submit(CreateGoalPayload(
                                title: '${tmpl.title} $goalYear',
                                icon: tmpl.icon,
                                year: goalYear,
                                targetCount: tmpl.target,
                                category: tmpl.category,
                                smartQueryJson: tmpl.smartQueryJson,
                                description: null,
                              ));
                            },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.bgCard.withAlpha(153),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withAlpha(26)),
                        ),
                        child: Row(
                          children: [
                            Text(tmpl.icon,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tmpl.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              goalYear.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              // Custom tab fields
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title field
                  Text(
                    t.tr('goals.modal.titleField'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TsundokuTextField(
                    controller: _titleController,
                    maxLength: 120,
                    placeholder: '🎯',
                  ),
                  const SizedBox(height: 12),

                  // Year & Target Count
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('goals.modal.yearField'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TsundokuTextField(
                              controller: _yearController,
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('goals.modal.targetField'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TsundokuTextField(
                              controller: _targetController,
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Category & Icon
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('goals.modal.categoryField'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TsundokuSelect<String>(
                              id: 'goal-category',
                              height: 36,
                              options: categoryOptions,
                              value: _category,
                              onChange: (next) =>
                                  setState(() => _category = next),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('goals.modal.iconField'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TsundokuTextField(
                              controller: _iconController,
                              maxLength: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    t.tr('goals.modal.descriptionField'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TsundokuTextField(
                    controller: _descriptionController,
                    maxLength: 300,
                  ),
                ],
              ),

            // Error display
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB7185).withAlpha(26), // rose-400/10
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFB7185).withAlpha(64)),
                ),
                child: Row(
                  children: [
                    const Text('!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFECDD3))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFFECDD3)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Submit button for custom tab
            if (_tab == 'custom') ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submitCustom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5446CF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color: const Color(0xFF818CF8).withAlpha(102)),
                    ),
                  ),
                  child: Text(
                    t.tr('goals.modal.create'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
