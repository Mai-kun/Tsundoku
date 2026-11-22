/// Порт `mediatracker-ui/src/features/edit-media/modules/BaseMediaModule.svelte`.
///
/// Block 1 — базовые данные вне категории: тип, название, оценка, статус и
/// даты начала/завершения. Всё приходит через bindable-пропы, поэтому модуль
/// рендерится где угодно (большой edit-модал, быстрый поповер, отдельный
/// экран), не зная о стейте модалки.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/media_labels.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';

/// Поля ввода базовых данных. Каждый TextBinding синхронизирует контроллер
/// с внешним значением (Svelte `$bindable`).
class _TextBinding extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChange;
  final String? placeholder;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _TextBinding({
    required this.value,
    required this.onChange,
    this.placeholder,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  State<_TextBinding> createState() => _TextBindingState();
}

class _TextBindingState extends State<_TextBinding> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TextBinding oldWidget) {
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
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      style: TextStyle(
        fontSize: 14, // text-sm
        fontWeight: FontWeight.w400,
        color: th.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // px-3 h-10
        filled: true,
        fillColor: th.bgSurface, // bg-field
        border: _fieldBorder(th),
        enabledBorder: _fieldBorder(th),
        focusedBorder: _fieldBorder(th, focused: true),
        hintText: widget.placeholder,
        hintStyle: TextStyle(color: th.textMuted),
      ),
    );
  }
}

OutlineInputBorder _fieldBorder(TsundokuTheme th, {bool focused = false}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(8), // rounded-lg
      borderSide: BorderSide(
        color: focused
            ? th.accent.withAlpha(153) // focus:border-accent
            : Colors.white.withAlpha(26), // border-white/10
        width: 1,
      ),
    );

/// Лейбл над полем: `text-sm font-medium space-y-1.5`.
class _FieldLabel extends StatelessWidget {
  final String label;

  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6), // space-y-1.5
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14, // text-sm
          fontWeight: FontWeight.w500,
          color: th.textPrimary, // text-ink
        ),
      ),
    );
  }
}

class BaseMediaModule extends ConsumerStatefulWidget {
  final bool flat;

  /// Префикс id внутренних Select'ов (несколько инстансов на странице).
  final String idPrefix;
  final MediaType type;
  final String title;
  final String score;
  final MediaStatus status;
  final String startedAt;
  final String finishedAt;

  final ValueChanged<MediaType>? onTypeChange;
  final ValueChanged<String>? onTitleChange;
  final ValueChanged<String>? onScoreChange;
  final ValueChanged<MediaStatus>? onStatusChange;
  final ValueChanged<String>? onStartedAtChange;
  final ValueChanged<String>? onFinishedAtChange;

  const BaseMediaModule({
    super.key,
    this.flat = false,
    this.idPrefix = 'edit-media',
    required this.type,
    required this.title,
    required this.score,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.onTypeChange,
    required this.onTitleChange,
    required this.onScoreChange,
    required this.onStatusChange,
    required this.onStartedAtChange,
    required this.onFinishedAtChange,
  });

  @override
  ConsumerState<BaseMediaModule> createState() => _BaseMediaModuleState();
}

class _BaseMediaModuleState extends ConsumerState<BaseMediaModule> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);

    final statusOptions = MediaStatus.values
        .map((s) => PopoverOption<MediaStatus>(
              value: s,
              label: statusLabel(s, t),
            ))
        .toList();

    return ModuleCard(
      flat: widget.flat,
      title: t.tr('createModal.modules.base'),
      count: null,
      icon: const Icon(LucideIcons.layers, size: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: type + title (sm:grid-cols-2).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('createModal.fields.type')),
                    TsundokuSelect<String>(
                      id: '${widget.idPrefix}-type',
                      options: kEditMediaTypes
                          .map((w) => PopoverOption<String>(
                                value: w,
                                label: t.tr('types.$w'),
                              ))
                          .toList(),
                      value: widget.type.wire,
                      onChange: (next) => widget.onTypeChange
                          ?.call(MediaType.fromWire(next)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12), // gap-3
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('createModal.fields.title')),
                    _TextBinding(
                      value: widget.title,
                      placeholder: t.tr('createModal.placeholders.title'),
                      onChange: (v) => widget.onTitleChange?.call(v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          // Row 2: score + status.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('createModal.fields.score')),
                    _TextBinding(
                      value: widget.score,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}$')),
                      ],
                      onChange: (v) => widget.onScoreChange?.call(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('status.label')),
                    TsundokuSelect<MediaStatus>(
                      id: '${widget.idPrefix}-status',
                      options: statusOptions,
                      value: widget.status,
                      onChange: (next) => widget.onStatusChange?.call(next),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 3: startedAt + finishedAt (нативный showDatePicker с читаемым
          // форматом, кнопкой очистки и сохранением ISO-8601 YYYY-MM-DD для API).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('createModal.fields.startedAt')),
                    _DatePickerField(
                      label: t.tr('createModal.fields.startedAt'),
                      value: widget.startedAt,
                      onChange: (v) => widget.onStartedAtChange?.call(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(t.tr('createModal.fields.finishedAt')),
                    _DatePickerField(
                      label: t.tr('createModal.fields.finishedAt'),
                      value: widget.finishedAt,
                      onChange: (v) => widget.onFinishedAtChange?.call(v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Нативный выбор даты (showDatePicker) с читаемым форматированием,
/// сохранением ISO-8601 для API и кнопкой быстрой очистки.
class _DatePickerField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChange;
  final String label;

  const _DatePickerField({
    required this.value,
    required this.onChange,
    required this.label,
  });

  DateTime? get _parsedDate {
    if (value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _formatDisplay(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _parsedDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1), // accent indigo
              surface: Color(0xFF1E232E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final iso =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      onChange(iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _parsedDate;
    final th = TsundokuTheme.of(context);
    final displayText = date != null ? _formatDisplay(date) : '—';

    return InkWell(
      onTap: () => _pickDate(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.calendar,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null ? th.textPrimary : th.textMuted,
                ),
              ),
            ),
            if (value.isNotEmpty)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                icon: const Icon(
                  LucideIcons.x,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
                onPressed: () => onChange(''),
                tooltip: 'Очистить',
              ),
          ],
        ),
      ),
    );
  }
}
