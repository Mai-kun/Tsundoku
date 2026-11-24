import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_tokens.dart';

/// Unified text input component adhering 1:1 to Svelte styling:
/// - Single-line default: 36px height, font-size 13px, padding (12px, 8px)
/// - Background #0f1219 (bg-field)
/// - Subtle border white/10 (0x1AFFFFFF), radius 8px
/// - Placeholder text-muted/60, focus border accent/60
/// - Supports prefixIcon, suffix, obscureText, multiline, width, height.
class TsundokuTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final bool multiline;
  final int? minLines;
  final int? maxLines;
  final double? width;
  final double? height;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool readOnly;
  final int? maxLength;

  const TsundokuTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.labelText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.multiline = false,
    this.minLines,
    this.maxLines,
    this.width,
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.style,
    this.textAlign = TextAlign.start,
    this.readOnly = false,
    this.maxLength,
  });

  @override
  State<TsundokuTextField> createState() => _TsundokuTextFieldState();
}

class _TsundokuTextFieldState extends State<TsundokuTextField> {
  TextEditingController? _internalController;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController(text: widget.initialValue ?? ''));

  @override
  void didUpdateWidget(TsundokuTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        widget.initialValue != null &&
        widget.initialValue != oldWidget.initialValue) {
      _effectiveController.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final effectiveHeight = widget.multiline ? null : (widget.height ?? 36.0);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0x1AFFFFFF)), // white/10
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: th.accent.withAlpha(153), // accent/60
      ),
    );

    final disabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0x0DFFFFFF)),
    );

    final textStyle = widget.style ??
        TextStyle(
          fontSize: 13,
          color: th.textPrimary,
          fontWeight: FontWeight.w400,
        );

    final hintStyle = TextStyle(
      fontSize: 13,
      color: th.textMuted.withAlpha(153), // text-muted/60
      fontWeight: FontWeight.w400,
    );

    Widget field = TextField(
      controller: _effectiveController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType ??
          (widget.multiline ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      minLines: widget.multiline
          ? (widget.minLines ??
              (widget.maxLines != null && widget.maxLines! < 3
                  ? widget.maxLines
                  : 3))
          : 1,
      maxLines: widget.multiline ? widget.maxLines : 1,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: textStyle,
      cursorColor: th.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        counterText: '',
        fillColor: const Color(0xFF0F1219), // #0f1219 / bg-field
        hintText: widget.placeholder,
        hintStyle: hintStyle,
        labelText: widget.labelText,
        labelStyle: hintStyle,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        prefixIcon: widget.prefixIcon,
        prefixIconConstraints: const BoxConstraints(minWidth: 32, maxHeight: 36),
        suffixIcon: widget.suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 32, maxHeight: 36),
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        disabledBorder: disabledBorder,
      ),
    );

    if (widget.width != null || effectiveHeight != null) {
      field = SizedBox(
        width: widget.width,
        height: effectiveHeight,
        child: field,
      );
    }

    return field;
  }
}
