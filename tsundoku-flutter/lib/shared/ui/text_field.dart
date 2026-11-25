import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_tokens.dart';

/// Unified text input component adhering 1:1 to Svelte styling:
/// - Single-line default: 36px height (= ButtonSize.md), font-size 13px, horizontal padding 12px
/// - Background #0f1219 (bg-field)
/// - Border painted on the outer Container (`borderSubtle` idle, `accent` focused), radius 8px
/// - Collapsed inner TextField (0px InputDecorator inset)
/// - Supports prefixIcon, suffix, obscureText, multiline, width, height.
class TsundokuTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
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
  final EdgeInsetsGeometry? contentPadding;
  final bool isDense;

  const TsundokuTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
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
    this.contentPadding,
    this.isDense = true,
  });

  @override
  State<TsundokuTextField> createState() => _TsundokuTextFieldState();
}

class _TsundokuTextFieldState extends State<TsundokuTextField> {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;
  bool _isFocused = false;

  TextEditingController get _effectiveController =>
      widget.controller ??
      (_internalController ??=
          TextEditingController(text: widget.initialValue ?? ''));

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _isFocused = _effectiveFocusNode.hasFocus;
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final focused = _effectiveFocusNode.hasFocus;
    if (focused != _isFocused) {
      setState(() => _isFocused = focused);
    }
  }

  @override
  void didUpdateWidget(TsundokuTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        widget.initialValue != null &&
        widget.initialValue != oldWidget.initialValue) {
      _effectiveController.text = widget.initialValue!;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      final oldNode = oldWidget.focusNode ?? _internalFocusNode;
      oldNode?.removeListener(_handleFocusChange);
      if (widget.focusNode != null) {
        _internalFocusNode?.dispose();
        _internalFocusNode = null;
      }
      _effectiveFocusNode.addListener(_handleFocusChange);
      _isFocused = _effectiveFocusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final effectiveHeight = widget.multiline ? null : (widget.height ?? 36.0);

    final Color borderColor;
    if (!widget.enabled) {
      borderColor = const Color(0x0DFFFFFF);
    } else if (_isFocused) {
      borderColor = th.accent;
    } else {
      borderColor = th.borderSubtle;
    }

    final baseTextStyle = widget.style ??
        TextStyle(
          fontSize: 13,
          color: th.textPrimary,
          fontWeight: FontWeight.w400,
        );
    final double effectiveFontSize = baseTextStyle.fontSize ?? 13.0;
    final TextStyle textStyle = widget.multiline
        ? baseTextStyle
        : (baseTextStyle.height == null
            ? baseTextStyle.copyWith(height: 1.0)
            : baseTextStyle);

    final hintStyle = TextStyle(
      fontSize: effectiveFontSize,
      height: widget.multiline ? textStyle.height : (textStyle.height ?? 1.0),
      color: th.textMuted.withValues(alpha: 0.6), // text-muted/60
      fontWeight: FontWeight.w400,
    );

    final Widget field = TextField(
      controller: _effectiveController,
      focusNode: _effectiveFocusNode,
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
      strutStyle: widget.multiline
          ? null
          : StrutStyle(
              fontSize: effectiveFontSize,
              height: textStyle.height ?? 1.0,
              forceStrutHeight: true,
            ),
      textAlignVertical:
          widget.multiline ? TextAlignVertical.top : TextAlignVertical.center,
      cursorColor: th.accent,
      decoration: InputDecoration(
        isDense: widget.isDense,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
        counterText: '',
        hintText: widget.placeholder,
        hintStyle: hintStyle,
      ),
    );

    final Widget alignedField =
        widget.multiline ? field : Center(child: field);
    final bool hasAffixes = widget.prefixIcon != null || widget.suffix != null;
    final Widget innerContent = hasAffixes
        ? Row(
            crossAxisAlignment: widget.multiline
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (widget.prefixIcon != null) ...[
                widget.prefixIcon!,
                const SizedBox(width: 8),
              ],
              Expanded(child: alignedField),
              if (widget.suffix != null) ...[
                const SizedBox(width: 8),
                widget.suffix!,
              ],
            ],
          )
        : (widget.multiline
            ? field
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: alignedField),
                ],
              ));

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.enabled && !widget.readOnly
            ? () {
                if (!_effectiveFocusNode.hasFocus) {
                  _effectiveFocusNode.requestFocus();
                }
              }
            : null,
        child: Container(
          width: widget.width,
          height: effectiveHeight,
          alignment: widget.multiline ? Alignment.topLeft : Alignment.center,
          padding: widget.contentPadding ??
              EdgeInsets.symmetric(
                horizontal: 12,
                vertical: widget.multiline ? 10 : 0,
              ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1219), // #0f1219 / bg-field
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: innerContent,
        ),
      ),
    );
  }
}
