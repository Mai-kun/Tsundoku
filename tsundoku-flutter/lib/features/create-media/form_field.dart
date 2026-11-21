/// Порт `mediatracker-ui/src/features/create-media/FormField.svelte`.
///
/// Обёртка поля формы: лейбл + контрол. `text-ink space-y-1.5 text-sm
/// font-medium`. Имя `TsundokuFormField` — конфликт с Flutter `FormField`.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

/// Лейбл над полем формы (upper-level обёртка `<label>` Svelte).
class TsundokuFormField extends StatelessWidget {
  final String label;
  final Widget child;

  const TsundokuFormField({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6), // space-y-1.5
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w500,
              color: th.textPrimary, // text-ink
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Границы полей форм create/edit (rounded-lg, border-white/10,
/// focus:border-accent).
OutlineInputBorder createFieldBorder(
  TsundokuTheme th, {
  bool focused = false,
}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: focused
            ? th.accent.withAlpha(153)
            : Colors.white.withAlpha(26), // border-white/10
        width: 1,
      ),
    );

/// Общие InputDecoration полей форм (h-10, px-3, text-sm, bg-field).
InputDecoration createFieldDecoration(
  TsundokuTheme th, {
  String? hint,
  bool dense = false,
}) =>
    InputDecoration(
      isDense: dense,
      filled: true,
      fillColor: th.bgSurface, // bg-field
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: createFieldBorder(th),
      enabledBorder: createFieldBorder(th),
      focusedBorder: createFieldBorder(th, focused: true),
      hintText: hint,
      hintStyle: TextStyle(color: th.textMuted), // placeholder:text-muted
    );

/// Стиль текста полей форм (text-sm font-normal).
TextStyle createFieldTextStyle(TsundokuTheme th) => TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: th.textPrimary,
    );

/// Числовой форматтер полей форм (type=number min=0: только цифры).
TextInputFormatter createNumberFormatter() =>
    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}$'));

/// Bindable-текстовое поле форм create/edit (аналог `<input bind:value>`).
class CreateTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChange;
  final String? hint;
  final bool number;
  final TextInputType? keyboardType;

  const CreateTextField({
    super.key,
    required this.value,
    required this.onChange,
    this.hint,
    this.number = false,
    this.keyboardType,
  });

  @override
  State<CreateTextField> createState() => _CreateTextFieldState();
}

class _CreateTextFieldState extends State<CreateTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant CreateTextField oldWidget) {
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
      keyboardType:
          widget.keyboardType ?? (widget.number ? TextInputType.number : null),
      inputFormatters: widget.number ? [createNumberFormatter()] : null,
      style: createFieldTextStyle(th),
      decoration: createFieldDecoration(th, hint: widget.hint),
    );
  }
}
