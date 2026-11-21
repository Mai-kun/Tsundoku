/// Порт `mediatracker-ui/src/features/create-media/BookFormFields.svelte`.
///
/// Поля категории book: автор, формат, страницы/главы-тома (романы и ранобэ
/// измеряются главами/томами, остальное — страницами). ⬆️ Вытащен из Фазы 5
/// (зависимость CategoryFieldsModule, Фаза 4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';

class BookFormFields extends ConsumerWidget {
  final String author;
  final String totalPages;
  final String format;
  final String totalChapters;
  final String totalVolumes;
  final ValueChanged<String>? onAuthorChange;
  final ValueChanged<String>? onTotalPagesChange;
  final ValueChanged<String>? onFormatChange;
  final ValueChanged<String>? onTotalChaptersChange;
  final ValueChanged<String>? onTotalVolumesChange;

  const BookFormFields({
    super.key,
    required this.author,
    required this.totalPages,
    required this.format,
    required this.totalChapters,
    required this.totalVolumes,
    required this.onAuthorChange,
    required this.onTotalPagesChange,
    required this.onFormatChange,
    required this.onTotalChaptersChange,
    required this.onTotalVolumesChange,
  });

  // Романы и ранобэ измеряются главами/томами, остальное — страницами.
  bool get _isNovel => format == 'light_novel' || format == 'web_novel';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final formatOptions = <PopoverOption<String>>[
      PopoverOption(
          value: 'book',
          label: t.tr('createModal.fields.bookFormats.book')),
      PopoverOption(
          value: 'light_novel',
          label: t.tr('createModal.fields.bookFormats.light_novel')),
      PopoverOption(
          value: 'web_novel',
          label: t.tr('createModal.fields.bookFormats.web_novel')),
      PopoverOption(
          value: 'comics',
          label: t.tr('createModal.fields.bookFormats.comics')),
      PopoverOption(
          value: 'ebook',
          label: t.tr('createModal.fields.bookFormats.ebook')),
      PopoverOption(
          value: 'audiobook',
          label: t.tr('createModal.fields.bookFormats.audiobook')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.author'),
                child: CreateTextField(
                  value: author,
                  hint: t.tr('createModal.placeholders.author'),
                  onChange: (v) => onAuthorChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16), // gap-4
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.format'),
                child: TsundokuSelect<String>(
                  id: 'book-format-select',
                  options: formatOptions,
                  value: format.isEmpty ? 'book' : format,
                  onChange: (next) => onFormatChange?.call(next),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16), // space-y-4
        if (_isNovel)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TsundokuFormField(
                  label: t.tr('createModal.fields.totalChapters'),
                  child: CreateTextField(
                    value: totalChapters,
                    number: true,
                    onChange: (v) => onTotalChaptersChange?.call(v),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TsundokuFormField(
                  label: t.tr('createModal.fields.totalVolumes'),
                  child: CreateTextField(
                    value: totalVolumes,
                    number: true,
                    onChange: (v) => onTotalVolumesChange?.call(v),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TsundokuFormField(
                  label: t.tr('createModal.fields.totalPages'),
                  child: CreateTextField(
                    value: totalPages,
                    number: true,
                    onChange: (v) => onTotalPagesChange?.call(v),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
      ],
    );
  }
}
