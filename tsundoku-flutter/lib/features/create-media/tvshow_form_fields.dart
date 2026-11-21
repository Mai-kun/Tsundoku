/// Порт `mediatracker-ui/src/features/create-media/TvShowFormFields.svelte`.
///
/// Поля категории tvshow: студия, сеть, чекбокс «Это аниме?» и редактор
/// сезонов (seasonNumber/title/totalEpisodes, add/remove). ⬆️ Вытащен из
/// Фазы 5 (зависимость CategoryFieldsModule, Фаза 4).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class TvShowFormFields extends ConsumerStatefulWidget {
  final String studio;
  final String network;
  final bool isAnime;
  final List<SeasonDraft> seasons;
  final ValueChanged<String>? onStudioChange;
  final ValueChanged<String>? onNetworkChange;
  final ValueChanged<bool>? onIsAnimeChange;
  final ValueChanged<List<SeasonDraft>>? onSeasonsChange;

  const TvShowFormFields({
    super.key,
    required this.studio,
    required this.network,
    required this.isAnime,
    required this.seasons,
    required this.onStudioChange,
    required this.onNetworkChange,
    required this.onIsAnimeChange,
    required this.onSeasonsChange,
  });

  @override
  ConsumerState<TvShowFormFields> createState() => _TvShowFormFieldsState();
}

class _TvShowFormFieldsState extends ConsumerState<TvShowFormFields> {
  void _addSeason() {
    widget.onSeasonsChange?.call([
      ...widget.seasons,
      SeasonDraft(
        seasonNumber: '${widget.seasons.length + 1}',
        title: '',
        totalEpisodes: '',
      ),
    ]);
  }

  void _removeSeason(int index) {
    widget.onSeasonsChange?.call(
      List<SeasonDraft>.from(widget.seasons)..removeAt(index),
    );
  }

  void _updateSeason(int index, SeasonDraft season) {
    widget.onSeasonsChange?.call(
      List<SeasonDraft>.from(widget.seasons)..[index] = season,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.studio'),
                child: CreateTextField(
                  value: widget.studio,
                  hint: t.tr('createModal.placeholders.studio'),
                  onChange: (v) => widget.onStudioChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16), // gap-4
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.network'),
                child: CreateTextField(
                  value: widget.network,
                  hint: t.tr('createModal.placeholders.network'),
                  onChange: (v) => widget.onNetworkChange?.call(v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Чекбокс «Это аниме?».
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onIsAnimeChange?.call(!widget.isAnime),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: widget.isAnime,
                  onChanged: (v) => widget.onIsAnimeChange?.call(v ?? false),
                  activeColor: th.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t.tr('createModal.fields.isAnime'),
                style: TextStyle(fontSize: 14, color: th.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Редактор сезонов (bg-field/50, rounded-xl, border-white/10, p-3).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12), // p-3
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
                color: Colors.white.withAlpha(26)), // border-white/10
            color: th.bgSurface.withAlpha(128), // bg-field/50
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.tr('navigation.seasons'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: th.textPrimary, // text-ink
                      ),
                    ),
                  ),
                  // «+ Добавить сезон».
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _addSeason,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus,
                            size: 14, color: th.accentSoft), // text-accent-soft
                        const SizedBox(width: 6), // gap-1.5
                        Text(
                          t.tr('createModal.addSeason'),
                          style: TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w600,
                            color: th.accentSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12), // space-y-3
              for (var index = 0; index < widget.seasons.length; index++) ...[
                Padding(
                  padding: EdgeInsets.only(
                      bottom: index == widget.seasons.length - 1 ? 0 : 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // sm:grid-cols-[5rem_1fr_7rem_auto]
                      SizedBox(
                        width: 56,
                        child: _SeasonField(
                          value: widget.seasons[index].seasonNumber,
                          number: true,
                          ariaLabel: t.tr('createModal.fields.season'),
                          onChange: (v) => _updateSeason(
                            index,
                            widget.seasons[index].copyWith(seasonNumber: v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      Expanded(
                        child: _SeasonField(
                          value: widget.seasons[index].title,
                          hint: t.tr('createModal.placeholders.season'),
                          onChange: (v) => _updateSeason(
                            index,
                            widget.seasons[index].copyWith(title: v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96, // 7rem
                        child: _SeasonField(
                          value: widget.seasons[index].totalEpisodes,
                          number: true,
                          hint: t.tr('createModal.fields.episodes'),
                          onChange: (v) => _updateSeason(
                            index,
                            widget.seasons[index].copyWith(totalEpisodes: v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Кнопка удаления сезона (hover rose).
                      GestureDetector(
                        onTap: () => _removeSeason(index),
                        child: Container(
                          width: 36, // h-9 w-9
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(LucideIcons.minus,
                              size: 16, color: th.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Поле строки сезона (h-9, px-2, focus:border-accent).
class _SeasonField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChange;
  final String? hint;
  final bool number;
  final String? ariaLabel;

  const _SeasonField({
    required this.value,
    required this.onChange,
    this.hint,
    this.number = false,
    this.ariaLabel,
  });

  @override
  State<_SeasonField> createState() => _SeasonFieldState();
}

class _SeasonFieldState extends State<_SeasonField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SeasonField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return TextField(
      controller: _controller,
      onChanged: widget.onChange,
      keyboardType: widget.number ? TextInputType.number : null,
      inputFormatters: widget.number
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}$'))]
          : null,
      style: createFieldTextStyle(th),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: th.bgSurface, // bg-field
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // px-2 h-9
        border: createFieldBorder(th),
        enabledBorder: createFieldBorder(th),
        focusedBorder: createFieldBorder(th, focused: true),
        hintText: widget.hint,
        hintStyle: TextStyle(color: th.textMuted),
      ),
    );
  }
}
