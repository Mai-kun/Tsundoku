/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/QuotesSection.svelte`.
///
/// Цитаты и выписки: optimistic добавление/удаление (local state + rollback
/// при ошибке + тост); в Svelte мутируется media.quotesJson напрямую — здесь
/// локальный список + колбек onQuotesJsonChanged для родителя (решение #49).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/toast.dart';

/// Секция цитат (1-в-1 с QuotesSection.svelte).
class QuotesSection extends ConsumerStatefulWidget {
  final MediaDetail media;

  /// Svelte мутирует media.quotesJson на месте; Dart read-only —
  /// родитель (MediaDetailView) обновляет стейт через этот колбек.
  final void Function(String nextJson)? onQuotesJsonChanged;

  const QuotesSection({
    super.key,
    required this.media,
    this.onQuotesJsonChanged,
  });

  @override
  ConsumerState<QuotesSection> createState() => _QuotesSectionState();
}

class _QuotesSectionState extends ConsumerState<QuotesSection> {
  List<MediaQuote> _quotes = <MediaQuote>[];
  bool _isAdding = false;
  bool _isSaving = false;
  bool _hoveredQuote = false;

  @override
  void initState() {
    super.initState();
    _quotes = _parseQuotes(widget.media.quotesJson);
  }

  @override
  void didUpdateWidget(covariant QuotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.media.quotesJson != oldWidget.media.quotesJson) {
      _quotes = _parseQuotes(widget.media.quotesJson);
    }
  }

  List<MediaQuote> _parseQuotes(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final parsed = jsonDecode(json);
      if (parsed is! List) return [];
      return parsed
          .whereType<Map<String, dynamic>>()
          .map(MediaQuote.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _encodeQuotes(List<MediaQuote> quotes) => jsonEncode([
        for (final q in quotes)
          {
            'id': q.id,
            'text': q.text,
            if (q.pageOrContext != null) 'pageOrContext': q.pageOrContext,
            'createdAt': q.createdAt,
          },
      ]);

  Future<void> _handleSave(TextEditingController textController,
      TextEditingController contextController) async {
    final text = textController.text.trim();
    if (text.isEmpty || _isSaving) return;

    final newQuote = MediaQuote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      pageOrContext: contextController.text.trim().isEmpty
          ? null
          : contextController.text.trim(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    final previousJson = widget.media.quotesJson;
    final nextQuotes = [newQuote, ..._quotes];
    final nextJson = _encodeQuotes(nextQuotes);

    setState(() {
      _quotes = nextQuotes;
      textController.clear();
      contextController.clear();
      _isAdding = false;
      _isSaving = true;
    });
    widget.onQuotesJsonChanged?.call(nextJson);

    try {
      await ref
          .read(apiClientProvider)
          .updateMedia(widget.media.id, UpdateMediaPayload(quotesJson: nextJson));
    } catch (error) {
      if (!mounted) return;
      setState(() => _quotes = _parseQuotes(previousJson));
      widget.onQuotesJsonChanged?.call(previousJson ?? '');
      _errorToast(error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleDelete(String id) async {
    final previousJson = widget.media.quotesJson;
    final nextQuotes =
        _quotes.where((q) => q.id != id).toList();
    final nextJson = _encodeQuotes(nextQuotes);

    setState(() => _quotes = nextQuotes);
    widget.onQuotesJsonChanged?.call(nextJson);

    try {
      await ref
          .read(apiClientProvider)
          .updateMedia(widget.media.id, UpdateMediaPayload(quotesJson: nextJson));
    } catch (error) {
      if (!mounted) return;
      setState(() => _quotes = _parseQuotes(previousJson));
      widget.onQuotesJsonChanged?.call(previousJson ?? '');
      _errorToast(error);
    }
  }

  void _errorToast(Object error) {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('toast.actionFailed'),
        description: errorMessage(error, locale),
        type: ToastType.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    if (_quotes.isEmpty && !_isAdding) {
      // Пустая dashed-кнопка-приглашение.
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredQuote = true),
        onExit: (_) => setState(() => _hoveredQuote = false),
        child: GestureDetector(
          onTap: () => setState(() => _isAdding = true),
          child: Container(
            constraints:
                const BoxConstraints(minHeight: 140), // min-h-[140px]
            padding: const EdgeInsets.all(20), // p-5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              border: Border.all(
                color: _hoveredQuote
                    ? const Color(0x4DFBBF24) // hover:border-amber-400/30
                    : Colors.white.withAlpha(26), // border-white/10
              ),
              color: _hoveredQuote
                  ? Colors.white.withAlpha(8) // hover:bg-white/[0.03]
                  : th.bgSurface.withAlpha(128), // panel-line/50
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: _hoveredQuote ? 1.05 : 1.0, // group-hover:scale-105
                  child: Container(
                    width: 40, // size-10
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 12), // mb-3
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                      color:
                          const Color(0x1AFBBF24), // bg-amber-400/10
                    ),
                    child: const Icon(LucideIcons.quote,
                        size: 18, color: Color(0xFFFBBF24)), // text-amber-400
                  ),
                ),
                Text(
                  t.tr('detail.quotesTitle').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.6, // tracking-wider
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
                const SizedBox(height: 8), // mt-2
                Text(
                  t.tr('detail.quotesEmpty'),
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    height: 1.625, // leading-relaxed
                    color: th.textMuted.withAlpha(178), // text-muted/70
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: th.bgSurface, // panel-line
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.quote,
                  size: 16, color: Color(0xFFFBBF24)), // text-amber-400
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.tr('detail.quotesTitle').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.w700, // font-bold
                          letterSpacing: 0.6, // tracking-wider
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                    ),
                    if (_quotes.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2), // px-2 py-0.5
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: const Color(0x1AFBBF24), // amber-400/10
                        ),
                        child: Text(
                          '${_quotes.length}',
                          style: const TextStyle(
                            fontSize: 11, // text-[11px]
                            fontWeight: FontWeight.w600, // font-semibold
                            color: Color(0xFFFBBF24), // text-amber-400
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _AddQuoteButton(
                label: t.tr('detail.quotesAdd'),
                th: th,
                isAdding: _isAdding,
                onTap: () => setState(() => _isAdding = !_isAdding),
              ),
            ],
          ),
          if (_isAdding)
            _AddQuoteForm(
              t: t,
              th: th,
              isSaving: _isSaving,
              onSave: _handleSave,
              onCancel: () => setState(() => _isAdding = false),
            ),
          const SizedBox(height: 14), // space-y-3.5
          for (final quote in _quotes)
            _QuoteCard(
              quote: quote,
              th: th,
              deleteLabel: t.tr('common.delete'),
              onDelete: () => _handleDelete(quote.id),
            ),
        ],
      ),
    );
  }
}

/// Кнопка «+» в шапке: size-7, hover amber.
class _AddQuoteButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final bool isAdding;
  final VoidCallback onTap;

  const _AddQuoteButton({
    required this.label,
    required this.th,
    required this.isAdding,
    required this.onTap,
  });

  @override
  State<_AddQuoteButton> createState() => _AddQuoteButtonState();
}

class _AddQuoteButtonState extends State<_AddQuoteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 28, // size-7
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                  color: _hovered
                      ? const Color(0x66FBBF24) // hover:border-amber-400/40
                      : Colors.white.withAlpha(26), // border-white/10
                ),
                color: _hovered
                    ? const Color(0x1AFBBF24) // hover:bg-amber-400/10
                    : Colors.white.withAlpha(10), // bg-white/[0.04]
              ),
              child: Icon(
                LucideIcons.plus,
                size: 15,
                color: _hovered
                    ? const Color(0xFFFBBF24) // hover:text-amber-400
                    : widget.th.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Форма добавления: textarea + контекст + Отмена/Сохранить.
class _AddQuoteForm extends StatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final bool isSaving;
  final Future<void> Function(
          TextEditingController text, TextEditingController context)
      onSave;
  final VoidCallback onCancel;

  const _AddQuoteForm({
    required this.t,
    required this.th,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_AddQuoteForm> createState() => _AddQuoteFormState();
}

class _AddQuoteFormState extends State<_AddQuoteForm> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _context = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _context.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _text.text.trim().isNotEmpty && !widget.isSaving;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final th = widget.th;
    return Container(
      margin: const EdgeInsets.only(top: 14), // space-y-3.5
      padding: const EdgeInsets.all(14), // p-3.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(
            color: const Color(0x33FBBF24)), // border-amber-400/20
        color: Colors.black.withAlpha(64), // bg-black/25
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _text,
            autofocus: true, // use:focusOnMount
            maxLines: 3,
            minLines: 3,
            onChanged: (_) => setState(() {}), // disable-состояние кнопки
            style: TextStyle(
              fontSize: 14, // text-sm
              height: 1.625, // leading-relaxed
              color: th.textPrimary, // text-ink
            ),
            decoration: InputDecoration(
              hintText: t.tr('detail.quotesPlaceholder'),
              hintStyle: TextStyle(
                  color: th.textMuted.withAlpha(153)), // placeholder muted/60
              filled: true,
              fillColor: Colors.black.withAlpha(51), // bg-black/20
              contentPadding: const EdgeInsets.all(12), // p-3
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.white.withAlpha(26)), // /10
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.white.withAlpha(26)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0x99FBBF24)), // amber-400/60
              ),
            ),
          ),
          const SizedBox(height: 12), // space-y-3
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _context,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: th.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: t.tr('detail.quotesContextPlaceholder'),
                    hintStyle:
                        TextStyle(color: th.textMuted.withAlpha(153)),
                    filled: true,
                    fillColor: Colors.black.withAlpha(51),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6), // px-3 py-1.5
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.white.withAlpha(26)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.white.withAlpha(26)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0x99FBBF24)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10), // gap-2.5
              _CancelButton(t: t, th: th, onTap: widget.onCancel),
              const SizedBox(width: 8), // gap-2
              _SaveButton(
                t: t,
                enabled: _canSave,
                onTap: () => widget.onSave(_text, _context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CancelButton extends StatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _CancelButton({required this.t, required this.th, required this.onTap});

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // px-3 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _hovered
                ? Colors.white.withAlpha(13) // hover:bg-white/[0.05]
                : Colors.transparent,
          ),
          child: Text(
            widget.t.tr('detail.quotesCancel'),
            style: TextStyle(
              fontSize: 12, // text-xs
              color: _hovered
                  ? widget.th.textPrimary // hover:text-ink
                  : widget.th.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final I18nDictionary t;
  final bool enabled;
  final VoidCallback onTap;

  const _SaveButton({
    required this.t,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6), // px-3.5 py-1.5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: enabled
              ? const Color(0xE6FBBF24) // bg-amber-400/90
              : const Color(0x80FBBF24), // disabled:opacity-50
        ),
        child: Text(
          t.tr('detail.quotesSave'),
          style: const TextStyle(
            fontSize: 12, // text-xs
            fontWeight: FontWeight.w600, // font-semibold
            color: Colors.black, // text-black
          ),
        ),
      ),
    );
  }
}

/// Карточка цитаты: serif-текст в кавычках + delete на hover.
class _QuoteCard extends StatefulWidget {
  final MediaQuote quote;
  final TsundokuTheme th;
  final String deleteLabel;
  final VoidCallback onDelete;

  const _QuoteCard({
    required this.quote,
    required this.th,
    required this.deleteLabel,
    required this.onDelete,
  });

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10), // space-y-2.5
      padding: const EdgeInsets.all(14), // p-3.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(
          color: _hovered
              ? const Color(0x66FBBF24) // hover:border-amber-400/40
              : const Color(0x33FBBF24), // border-amber-400/20
        ),
        color: _hovered
            ? const Color(0x0AF59E0B) // hover:bg-amber-500/[0.04]
            : const Color(0x05F59E0B), // bg-amber-500/[0.02]
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: '\u201C',
                        style: TextStyle(
                          fontSize: 16, // text-base
                          height: 1.0, // leading-none
                          color: Color(0x66FBBF24), // amber-400/40
                        ),
                      ),
                      TextSpan(
                        text: ' ${widget.quote.text} ',
                        style: TextStyle(
                          fontSize: 14, // text-sm
                          height: 1.625, // leading-relaxed
                          fontStyle: FontStyle.italic, // italic
                          color: const Color(0xFFE2E8F0), // text-slate-200
                        ),
                      ),
                      const TextSpan(
                        text: '\u201D',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.0,
                          color: Color(0x66FBBF24),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.quote.pageOrContext != null &&
                    widget.quote.pageOrContext!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6), // space-y-1.5
                    child: Text(
                      '— ${widget.quote.pageOrContext}',
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w500, // font-medium
                        color: Color(0xFFFCD34D), // text-amber-300
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Delete: opacity-0 → group-hover:opacity-100.
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Tooltip(
              message: widget.deleteLabel,
              child: Semantics(
                button: true,
                label: widget.deleteLabel,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: 32, // size-8
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.transparent,
                    ),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: _hovered
                          ? const Color(0xFFF87171) // hover:text-rose-400
                          : Colors.transparent, // opacity-0
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
