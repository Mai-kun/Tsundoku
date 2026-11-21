/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/BookEditionSection.svelte`.
///
/// Об издании: издатель/страницы/год/язык/формат + ISBN с копированием
/// (navigator.clipboard → PlatformService.copyText, решение #32).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/toast.dart';

/// Секция издания книги (1-в-1 с BookEditionSection.svelte).
class BookEditionSection extends ConsumerStatefulWidget {
  final MediaDetail media;

  const BookEditionSection({super.key, required this.media});

  @override
  ConsumerState<BookEditionSection> createState() => _BookEditionSectionState();
}

class _BookEditionSectionState extends ConsumerState<BookEditionSection> {
  bool _copied = false;
  Timer? _copyTimeout;

  @override
  void dispose() {
    // $effect-cleanup: таймаут копирования отменяется при утилизации.
    _copyTimeout?.cancel();
    super.dispose();
  }

  void _copyIsbn() {
    final isbn = widget.media.isbn;
    if (isbn == null || isbn.isEmpty) return;
    unawaited(platformService.copyText(isbn).then((_) {
      final t = ref.read(tProvider);
      final locale = ref.read(i18nProvider);
      if (!mounted) return;
      setState(() => _copied = true);
      showToast(
        ref,
        ToastOptions(
          title: locale.wire == 'ru' ? 'ISBN скопирован' : 'ISBN copied to clipboard',
          description: t.tr('toast.descCopied'),
        ),
      );
      _copyTimeout?.cancel();
      _copyTimeout = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _copied = false);
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final isRu = locale.wire == 'ru';
    final media = widget.media;

    final rows = <({String label, String value})>[
      if (media.studio?.trim().isNotEmpty ?? false)
        (
          label: isRu ? 'Издатель' : 'Publisher',
          value: media.studio!.trim(),
        ),
      if ((media.totalPages ?? 0) > 0)
        (
          label: isRu ? 'Всего страниц' : 'Total pages',
          value: '${media.totalPages} ${isRu ? 'стр.' : 'pages'}',
        ),
      if (media.releaseYear != null)
        (
          label: isRu ? 'Год публикации' : 'Published',
          value: '${media.releaseYear}',
        ),
      if (media.originalLanguage?.isNotEmpty ?? false)
        (
          label: isRu ? 'Язык' : 'Language',
          value: media.originalLanguage!.toUpperCase(),
        ),
      (
        label: isRu ? 'Формат' : 'Format',
        value: media.userPlatform?.trim().isNotEmpty ?? false
            ? media.userPlatform!.trim()
            : (media.format != null && media.format != 'book'
                ? media.format!
                : (isRu ? 'Электронная книга' : 'E-book / Print')),
      ),
    ];

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
              Icon(LucideIcons.library,
                  size: 16, color: th.accentSoft), // text-accent-soft
              const SizedBox(width: 8), // gap-2
              Text(
                (isRu ? 'Об издании' : 'Publication').toUpperCase(),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w700, // font-bold
                  letterSpacing: 0.6, // tracking-wider
                  color: Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          // grid grid-cols-2 gap-2.
          LayoutBuilder(builder: (context, constraints) {
            final colWidth = (constraints.maxWidth - 8) / 2; // gap-2
            return Wrap(
              spacing: 8, // gap-2
              runSpacing: 8,
              children: [
                for (final row in rows)
                  SizedBox(
                    width: colWidth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8), // px-3 py-2
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8), // rounded-lg
                        border: Border.all(
                            color: Colors.white.withAlpha(15)), // /[0.06]
                        color: Colors.black.withAlpha(38), // bg-black/15
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              fontSize: 11, // text-[11px]
                              fontWeight: FontWeight.w500, // font-medium
                              color: th.textMuted, // text-muted
                            ),
                          ),
                          const SizedBox(height: 2), // gap-0.5
                          Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w600, // font-semibold
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (media.isbn?.isNotEmpty ?? false)
                  SizedBox(
                    width: constraints.maxWidth, // col-span-2
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8), // px-3 py-2
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withAlpha(15)),
                        color: Colors.black.withAlpha(38),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ISBN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: th.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  media.isbn!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2, // tracking-wide
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _CopyIsbnButton(
                            isRu: isRu,
                            copied: _copied,
                            onTap: _copyIsbn,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Кнопка копирования ISBN: Check/Copied на 2s после успеха.
class _CopyIsbnButton extends StatefulWidget {
  final bool isRu;
  final bool copied;
  final VoidCallback onTap;

  const _CopyIsbnButton({
    required this.isRu,
    required this.copied,
    required this.onTap,
  });

  @override
  State<_CopyIsbnButton> createState() => _CopyIsbnButtonState();
}

class _CopyIsbnButtonState extends State<_CopyIsbnButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isRu ? 'Копировать ISBN' : 'Copy ISBN',
      child: Semantics(
        button: true,
        label: widget.isRu ? 'Копировать ISBN' : 'Copy ISBN',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4), // px-2.5 py-1
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
                border: Border.all(
                    color: Colors.white.withAlpha(21)), // /[0.08]
                color: _hovered
                    ? Colors.white.withAlpha(21) // hover:bg-white/[0.08]
                    : Colors.white.withAlpha(10), // bg-white/[0.04]
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.copied) ...[
                    const Icon(LucideIcons.check,
                        size: 13, color: Color(0xFF34D399)), // text-emerald-400
                    const SizedBox(width: 6), // gap-1.5
                    Text(
                      widget.isRu ? 'Скопировано' : 'Copied',
                      style: const TextStyle(
                        fontSize: 11, // text-[11px]
                        fontWeight: FontWeight.w500, // font-medium
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ] else ...[
                    const Icon(LucideIcons.copy,
                        size: 13, color: Color(0xFF94A3B8)), // text-slate-400
                    const SizedBox(width: 6),
                    Text(
                      widget.isRu ? 'Копировать' : 'Copy',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _hovered
                            ? Colors.white // hover:text-white
                            : const Color(0xFFCBD5E1), // text-slate-300
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
