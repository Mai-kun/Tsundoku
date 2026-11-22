/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/RelationLoadButton.svelte`.
///
/// Селектор источника + кнопка загрузки: список источников резолвится один
/// раз на элемент; выбор опции грузит с force=true; лейбл щёлкает сразу.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/popover_menu.dart';
import 'relation_sources.dart';

/// Кнопка загрузки связанных/рекомендаций (1-в-1 с RelationLoadButton.svelte).
class RelationLoadButton extends ConsumerStatefulWidget {
  /// `{type, isAnime}` — достаточно для availableRelationSources.
  final MediaItem media;
  final bool loading;

  /// «related» — «Загрузить связанные», «recommendations» — «Получить
  /// рекомендации».
  final String kind;

  /// Провайдер, чьи данные сейчас на экране; остаётся выбираемым.
  final String? currentSource;

  /// Выбор опции грузит от неё; force пропускает 30-дневный кэш.
  final void Function(String source, {bool force}) onLoad;

  const RelationLoadButton({
    super.key,
    required this.media,
    required this.loading,
    required this.kind,
    required this.currentSource,
    required this.onLoad,
  });

  @override
  ConsumerState<RelationLoadButton> createState() => _RelationLoadButtonState();
}

class _RelationLoadButtonState extends ConsumerState<RelationLoadButton> {
  List<RelationSourceOption> _sources = <RelationSourceOption>[];
  String _selected = '';
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveSources());
  }

  @override
  void didUpdateWidget(covariant RelationLoadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Список зависит от настроек и типа — резолвится раз на элемент.
    final key = '${widget.media.type.wire}:${widget.media.isAnime ?? false}';
    final oldKey = '${oldWidget.media.type.wire}:${oldWidget.media.isAnime ?? false}';
    if (key != oldKey) _resolved = false;
    if (!_resolved) _resolveSources();
  }

  Future<void> _resolveSources() async {
    if (_resolved) return;
    _resolved = true;
    try {
      final list =
          await availableRelationSources(ref.read(apiClientProvider), widget.media);
      if (!mounted) return;
      setState(() {
        _sources = list;
        // Открыть на провайдере того, что уже на экране.
        _selected = list
                .where((source) => _matches(source, widget.currentSource))
                .map((source) => source.id)
                .firstOrNull ??
            list.firstOrNull?.id ??
            '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sources = <RelationSourceOption>[]);
    }
  }

  bool _matches(RelationSourceOption source, String? wanted) {
    if (wanted == null || wanted.isEmpty) return false;
    final needle = wanted.toLowerCase();
    return source.id.toLowerCase() == needle ||
        source.label.toLowerCase() == needle;
  }

  String get _selectedLabel {
    final locale = ref.read(i18nProvider);
    return _sources
            .where((source) => source.id == _selected)
            .map((source) => source.label)
            .firstOrNull ??
        widget.currentSource ??
        (locale.wire == 'ru' ? 'Выберите источник' : 'Choose a source');
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final isRu = locale.wire == 'ru';

    final label = isRu
        ? (widget.kind == 'related' ? 'Загрузить связанные' : 'Получить рекомендации')
        : (widget.kind == 'related' ? 'Load related' : 'Get recommendations');

    return Wrap(
      spacing: 8, // gap-2
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TsundokuPopoverMenu<String>(
          id: 'relation-source',
          options: [
            for (final source in _sources)
              PopoverOption(value: source.id, label: source.label),
          ],
          selected: _selected,
          onSelect: (value) {
            // Лейбл щёлкает на клик: await onLoad оставил бы триггер со
            // старым источником, пока запрос в полёте.
            if (value != _selected) {
              setState(() => _selected = value);
              widget.onLoad(value, force: true);
            }
          },
          label: isRu ? 'Источник связанных' : 'Related source',
          placement: PopoverPlacement.bottomEnd,
          trigger: (context, ctx) => IgnorePointer(
            child: Container(
              height: 32, // h-8
              padding:
                  const EdgeInsets.symmetric(horizontal: 10), // px-2.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
                border: Border.all(
                    color: Colors.white.withAlpha(21)), // /[0.08]
                color: const Color(0xFF1C202B), // bg-[#1c202b]
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.link2,
                      size: 13, color: th.accentSoft), // accent-soft
                  const SizedBox(width: 8), // gap-2
                  Flexible(
                    child: Text(
                      '${isRu ? 'Источник' : 'Source'}: $_selectedLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        color: Color(0xFFE2E8F0), // text-slate-200
                      ),
                    ),
                  ),
                  if (widget.loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF10B981)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(LucideIcons.chevronDown,
                      size: 13, color: const Color(0xFF94A3B8)), // slate-400
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap:
              (widget.loading || _selected.isEmpty) ? null : () => widget.onLoad(_selected),
          child: Container(
            height: 32, // h-8
            padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              border: Border.all(
                  color: th.accent.withAlpha(102)), // border-accent/40
              color: th.accent.withAlpha(26), // bg-accent/10
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.loading) ...[
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFA5B4FC)),
                  ),
                  const SizedBox(width: 8), // gap-2
                ],
                Flexible(
                  child: Text(
                    widget.loading
                        ? (isRu ? 'Загрузка…' : 'Loading…')
                        : label,
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: th.accentSoft, // text-accent-soft
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
