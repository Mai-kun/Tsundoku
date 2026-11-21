/// Порт `mediatracker-ui/src/features/edit-media/modules/QuotesModule.svelte`.
///
/// Block 3 — standalone-редактор цитат и выписок. Список живёт целиком в
/// bindable-пропе; в API ничего не пишется — вызывающий сериализует его в
/// `quotesJson` при сохранении.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

/// Кобальтово-янтарная палитра цитат (Tailwind-литералы вне ThemeExtension,
/// как в детальных секциях).
const Color _kAmber400 = Color(0xFFFBBF24);
const Color _kAmber400Half = Color(0x80FBBF24); // amber-400/50
const Color _kAmber400Faint = Color(0x33FBBF24); // amber-400/20
const Color _kAmber300 = Color(0xFFFCD34D);
const Color _kBlack20 = Color(0x33000000); // bg-black/20
const Color _kBlack25 = Color(0x40000000); // bg-black/25

class QuotesModule extends ConsumerStatefulWidget {
  final bool flat;
  final bool showLabel;
  final List<QuoteDraft> quotes;

  /// Svelte `quotes = $bindable([])`.
  final ValueChanged<List<QuoteDraft>>? onChange;

  const QuotesModule({
    super.key,
    this.flat = false,
    this.showLabel = true,
    required this.quotes,
    required this.onChange,
  });

  @override
  ConsumerState<QuotesModule> createState() => _QuotesModuleState();
}

class _QuotesModuleState extends ConsumerState<QuotesModule> {
  bool _isAdding = false;
  final TextEditingController _newText = TextEditingController();
  final TextEditingController _newContext = TextEditingController();
  String? _editingId;
  final TextEditingController _editText = TextEditingController();
  final TextEditingController _editContext = TextEditingController();

  void _commit(List<QuoteDraft> next) => widget.onChange?.call(next);

  void _addQuote() {
    final text = _newText.text.trim();
    if (text.isEmpty) return;
    _commit([
      ...widget.quotes,
      MediaQuote(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
            (widget.quotes.length.toString()),
        text: text,
        pageOrContext: _newContext.text.trim().isEmpty
            ? null
            : _newContext.text.trim(),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    ]);
    setState(() {
      _newText.clear();
      _newContext.clear();
      _isAdding = false;
    });
  }

  void _startEditing(MediaQuote quote) {
    setState(() {
      _editingId = quote.id;
      _editText.text = quote.text;
      _editContext.text = quote.pageOrContext ?? '';
    });
  }

  void _commitEditing() {
    if (_editingId == null) return;
    final text = _editText.text.trim();
    if (text.isEmpty) return;
    _commit(widget.quotes
        .map((quote) => quote.id == _editingId
            ? MediaQuote(
                id: quote.id,
                text: text,
                pageOrContext: _editContext.text.trim().isEmpty
                    ? null
                    : _editContext.text.trim(),
                createdAt: quote.createdAt,
              )
            : quote)
        .toList());
    setState(() => _editingId = null);
  }

  void _cancelEditing() {
    setState(() {
      _editingId = null;
      _editText.clear();
      _editContext.clear();
    });
  }

  void _removeQuote(String id) {
    _commit(
        List<QuoteDraft>.from(widget.quotes)..removeWhere((q) => q.id == id));
    if (_editingId == id) _cancelEditing();
  }

  @override
  void dispose() {
    _newText.dispose();
    _newContext.dispose();
    _editText.dispose();
    _editContext.dispose();
    super.dispose();
  }

  InputDecoration _quoteField(TsundokuTheme th, {String? hint}) =>
      InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _kBlack20, // bg-black/20
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Colors.white24), // border-white/10
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: _kAmber400Half), // focus:border-amber-400/60
        ),
        hintText: hint,
        hintStyle: TextStyle(color: th.textMuted.withAlpha(153)),
      );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return ModuleCard(
      flat: widget.flat,
      showLabel: widget.showLabel,
      title: t.tr('createModal.modules.quotes'),
      count: widget.quotes.length,
      icon: const Icon(LucideIcons.quote, size: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Добавление/кнопка «Добавить цитату».
          if (_isAdding)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12), // p-3
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(color: _kAmber400Faint), // amber-400/20
                color: _kBlack25, // bg-black/25
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _newText,
                    maxLines: 4,
                    minLines: 4,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.625, // leading-relaxed
                      color: Color(0xFFF3F4F6), // text-ink
                    ),
                    decoration: _quoteField(
                      th,
                      hint: t.tr('detail.quotesPlaceholder'),
                    ),
                  ),
                  const SizedBox(height: 10), // space-y-2.5
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newContext,
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            color: Color(0xFFF3F4F6),
                          ),
                          decoration: _quoteField(
                            th,
                            hint: t.tr('detail.quotesContextPlaceholder'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isAdding = false;
                            _newText.clear();
                            _newContext.clear();
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6), // px-2.5 py-1.5
                          child: Text(
                            t.tr('detail.quotesCancel'),
                            style: TextStyle(
                              fontSize: 12, // text-xs
                              color: th.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Save-кнопка (bg-amber-400/90, text-black).
                      GestureDetector(
                        onTap: _newText.text.trim().isEmpty ? null : _addQuote,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6), // px-3 py-1.5
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: _newText.text.trim().isEmpty
                                ? _kAmber400Half
                                : _kAmber400.withAlpha(230), // amber-400/90
                          ),
                          child: Text(
                            t.tr('detail.quotesSave'),
                            style: const TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _isAdding = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8), // px-3 py-2
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white24,
                    // border-dashed → DashedBorder не используется: сплошная
                    // border-white/10 (пунктир в Flutter-канвасе — отклонение,
                    // см. 🐛 журнал? нет: примечание в строке таблицы).
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus,
                        size: 14, color: th.accentSoft), // text-accent-soft
                    const SizedBox(width: 6), // gap-1.5
                    Text(
                      t.tr('detail.quotesAdd'),
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600,
                        color: th.accentSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12), // space-y-3
          if (widget.quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4), // px-1
              child: Text(
                t.tr('detail.quotesEmpty'),
                style: TextStyle(fontSize: 14, color: th.textMuted),
              ),
            )
          else
            Column(
              children: [
                for (final quote in widget.quotes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8), // space-y-2
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12), // p-3
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kAmber400Faint),
                        color: const Color(0x05F59E0B), // amber-500/[0.02]
                      ),
                      child: _editingId == quote.id
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _editText,
                                  maxLines: 3,
                                  minLines: 3,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.625,
                                    color: Color(0xFFF3F4F6),
                                  ),
                                  decoration: _quoteField(th),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _editContext,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFF3F4F6),
                                        ),
                                        decoration: _quoteField(
                                          th,
                                          hint: t
                                              .tr('detail.quotesContextPlaceholder'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: _cancelEditing,
                                      child: Container(
                                        width: 28, // size-7
                                        height: 28,
                                        alignment: Alignment.center,
                                        child: Icon(LucideIcons.x,
                                            size: 14, color: th.textMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: _editText.text.trim().isEmpty
                                          ? null
                                          : _commitEditing,
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: _editText.text.trim().isEmpty
                                              ? _kAmber400Half
                                              : _kAmber400.withAlpha(230),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(LucideIcons.check,
                                            size: 14, color: Colors.black),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // serif italic + amber-кавычки.
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '“',
                                              style: TextStyle(
                                                  color: _kAmber400
                                                      .withAlpha(102)),
                                            ),
                                            TextSpan(text: quote.text),
                                            TextSpan(
                                              text: '”',
                                              style: TextStyle(
                                                  color: _kAmber400
                                                      .withAlpha(102)),
                                            ),
                                          ],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 14, // text-sm
                                          height: 1.625, // leading-relaxed
                                          fontStyle: FontStyle.italic,
                                          fontFamily: 'serif', // font-serif
                                          color:
                                              Color(0xFFE2E8F0), // slate-200
                                        ),
                                      ),
                                      if (quote.pageOrContext != null) ...[
                                        const SizedBox(height: 4), // space-y-1
                                        Text(
                                          '— ${quote.pageOrContext}',
                                          style: const TextStyle(
                                            fontSize: 12, // text-xs
                                            fontWeight: FontWeight.w500,
                                            color: _kAmber300, // amber-300
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8), // gap-2
                                Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _startEditing(quote),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        child: Icon(LucideIcons.pencil,
                                            size: 13, color: th.textMuted),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _removeQuote(quote.id),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        child: Icon(LucideIcons.trash2,
                                            size: 13, color: th.textMuted),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
