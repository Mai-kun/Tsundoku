/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/LinkedSourcesSection.svelte`.
///
/// Привязанные внешние источники: загрузка/добавление (с распознаванием
/// ссылок)/сделать основным/удаление, чипы «взятых данных» с разворотом,
/// TsundokuSelect для источника, lightbox — нет, переходы — ExternalLink.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/popover_menu.dart';
import '../../../shared/ui/toast.dart';
import '../../../shared/utils/source_url_helper.dart';
import '../../../shared/utils/url_media_parser.dart';

/// Строка привязанного источника (Svelte-интерфейс LinkedSource).
class LinkedSource {
  final String source;
  final String externalId;
  final String? url;
  final bool isPrimary;
  final String? title;
  final List<String>? providedFields;

  const LinkedSource({
    required this.source,
    required this.externalId,
    required this.url,
    required this.isPrimary,
    required this.title,
    required this.providedFields,
  });

  factory LinkedSource.fromJson(Map<String, dynamic> json) => LinkedSource(
        source: json['source'] as String? ?? '',
        externalId: json['externalId'] as String? ?? '',
        url: json['url'] as String?,
        isPrimary: json['isPrimary'] as bool? ?? false,
        title: json['title'] as String?,
        providedFields:
            (json['providedFields'] as List<Object?>?)?.cast<String>().toList(),
      );
}

/// Опция источника для формы добавления.
class _SourceOption {
  final String value;
  final String label;
  const _SourceOption({required this.value, required this.label});
}

/// Секция привязанных источников (1-в-1 с LinkedSourcesSection.svelte).
class LinkedSourcesSection extends ConsumerStatefulWidget {
  final String mediaId;
  final String mediaType;

  /// Новая идентичность media → перечитать список без F5.
  final Object? media;

  /// После успешной мутации — родитель обновляет карточку.
  final void Function()? onChanged;

  /// Открывает полный relink-модал (смена основного источника).
  final VoidCallback? onOpenRelink;

  const LinkedSourcesSection({
    super.key,
    required this.mediaId,
    required this.mediaType,
    this.media,
    this.onChanged,
    this.onOpenRelink,
  });

  @override
  ConsumerState<LinkedSourcesSection> createState() =>
      _LinkedSourcesSectionState();
}

class _LinkedSourcesSectionState extends ConsumerState<LinkedSourcesSection> {
  List<LinkedSource> _sources = <LinkedSource>[];
  bool _loading = true;
  Object? _loadError;
  String _busy = '';
  bool _addOpen = false;
  String _addSource = '';
  String _addId = '';
  List<_SourceOption> _sourceOptions = <_SourceOption>[];
  Map<String, bool> _expandedFields = <String, bool>{};
  final TextEditingController _addIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      _loadSourceOptions();
    });
  }

  @override
  void dispose() {
    _addIdController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LinkedSourcesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect-аналог: identity-смена media → перезагрузка (enrichment job).
    if (!identical(oldWidget.media, widget.media)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  void _toggleFields(String source) {
    setState(() {
      _expandedFields = {
        ..._expandedFields,
        source: !(_expandedFields[source] ?? false),
      };
    });
  }

  List<_SourceOption> _fallbackOptions() {
    final t = ref.read(tProvider);
    final kinopoisk = _SourceOption(
        value: 'kinopoisk', label: t.tr('detail.linkedSourcesKinopoisk'));
    return switch (widget.mediaType) {
      'anime' => const [
          _SourceOption(value: 'anilist', label: 'AniList'),
          _SourceOption(value: 'shikimori', label: 'Shikimori'),
          _SourceOption(value: 'animelib', label: 'AnimeLib'),
          _SourceOption(value: 'kitsu', label: 'Kitsu'),
        ],
      'manga' => const [
          _SourceOption(value: 'mangalib', label: 'MangaLib'),
          _SourceOption(value: 'mangadex', label: 'MangaDex'),
          _SourceOption(value: 'shikimori', label: 'Shikimori'),
          _SourceOption(value: 'anilist', label: 'AniList'),
        ],
      'book' => const [
          _SourceOption(value: 'ranobelib', label: 'RanobeLib'),
          _SourceOption(value: 'openlibrary', label: 'OpenLibrary'),
        ],
      'movie' => [
          const _SourceOption(value: 'tmdb', label: 'TMDb'),
          kinopoisk,
          const _SourceOption(value: 'imdb', label: 'IMDb'),
        ],
      'tvshow' => [
          const _SourceOption(value: 'tmdb', label: 'TMDb'),
          kinopoisk,
          const _SourceOption(value: 'imdb', label: 'IMDb'),
          const _SourceOption(value: 'tvdb', label: 'TVDB'),
        ],
      'game' => const [
          _SourceOption(value: 'steam', label: 'Steam'),
          _SourceOption(value: 'rawg', label: 'RAWG'),
        ],
      _ => const [],
    };
  }

  /// Источник → опция формы добавления; SocialLib — зонт, предлагается как
  /// конкретный сайт (AnimeLib/MangaLib/RanobeLib).
  _SourceOption? _toOption(SourceInfo info) {
    if (!info.isEnabled || !info.mediaTypes.contains(widget.mediaType)) {
      return null;
    }
    final id = info.id.toLowerCase();
    if (id == 'sociallib') {
      if (widget.mediaType == 'anime') {
        return const _SourceOption(value: 'animelib', label: 'AnimeLib');
      }
      if (widget.mediaType == 'manga') {
        return const _SourceOption(value: 'mangalib', label: 'MangaLib');
      }
      if (widget.mediaType == 'book') {
        return const _SourceOption(value: 'ranobelib', label: 'RanobeLib');
      }
      return null;
    }
    return _SourceOption(value: id, label: info.name);
  }

  List<_SourceOption> get _availableOptions {
    final linked = _sources.map((s) => s.source.trim().toLowerCase()).toSet();
    return _sourceOptions
        .where((option) => !linked.contains(option.value))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final sources =
          await ref.read(apiClientProvider).getLinkedSources(widget.mediaId);
      if (!mounted) return;
      setState(() {
        _sources =
            sources.map(LinkedSource.fromJson).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSourceOptions() async {
    try {
      final infos = await ref.read(apiClientProvider).getSources();
      if (!mounted) return;
      final options = infos
          .map(_toOption)
          .whereType<_SourceOption>()
          .toList();
      setState(() => _sourceOptions = options);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sourceOptions = _fallbackOptions());
    }
    if (!_sourceOptions.any((option) => option.value == _addSource)) {
      setState(() => _addSource = _sourceOptions.firstOrNull?.value ?? '');
    }
  }

  Future<void> _mutate(
      Future<List<Map<String, dynamic>>> Function() action,
      String successMessage) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      final response = await action();
      if (!mounted) return;
      setState(() {
        _sources = response.map(LinkedSource.fromJson).toList();
      });
      showToast(
        ref,
        ToastOptions(
          title: successMessage,
          description: t.tr('toast.descUpdated'),
        ),
      );
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  Future<void> _add() async {
    final raw = _addId.trim();
    if (raw.isEmpty || _addSource.isEmpty || _busy.isNotEmpty) return;

    // Вставленная ссылка → голый id, источник — по сайту ссылки (если
    // добавляем), иначе вся ссылка легла бы в externalId.
    var externalId = raw;
    var sourceKey = _addSource;
    final parsed = RegExp('^https?://', caseSensitive: false).hasMatch(raw)
        ? parseMediaUrl(raw)
        : null;
    if (parsed != null) {
      externalId = parsed.id;
      final linkIsAddable = !_sources
              .any((s) => s.source.trim().toLowerCase() == parsed.source) &&
          _sourceOptions.any((o) => o.value == parsed.source);
      if (linkIsAddable) sourceKey = parsed.source;
    }

    setState(() => _busy = 'add');
    final t = ref.read(tProvider);
    await _mutate(
      () => ref
          .read(apiClientProvider)
          .addLinkedSource(widget.mediaId, sourceKey, externalId),
      t.tr('detail.linkedSourcesAdded'),
    );
    if (!mounted) return;
    setState(() {
      _busy = '';
      _addOpen = false;
      _addId = '';
      _addIdController.clear();
    });
  }

  Future<void> _makePrimary(LinkedSource source) async {
    if (_busy.isNotEmpty) return;
    setState(() => _busy = 'primary:${source.source}');
    final t = ref.read(tProvider);
    await _mutate(
      () => ref
          .read(apiClientProvider)
          .makeLinkedSourcePrimary(widget.mediaId, source.source),
      t.tr('detail.linkedSourcesUpdated'),
    );
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _remove(LinkedSource source) async {
    if (_busy.isNotEmpty) return;
    setState(() => _busy = 'remove:${source.source}');
    final t = ref.read(tProvider);
    await _mutate(
      () => ref
          .read(apiClientProvider)
          .removeLinkedSource(widget.mediaId, source.source),
      t.tr('detail.linkedSourcesUpdated'),
    );
    if (mounted) setState(() => _busy = '');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final addable = _availableOptions;

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
              Icon(LucideIcons.link2,
                  size: 16, color: th.accentSoft), // text-accent-soft
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.tr('detail.linkedSourcesTitle').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.w700, // font-bold
                          letterSpacing: 0.6, // tracking-wider
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2), // px-2 py-0.5
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withAlpha(26), // bg-white/10
                        ),
                        child: Text(
                          '${_sources.length}',
                          style: const TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w700, // font-bold
                            color: Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _AddSourceButton(
                label: t.tr('detail.linkedSourcesAdd'),
                th: th,
                onTap: () => setState(() => _addOpen = !_addOpen),
              ),
            ],
          ),
          if (_addOpen)
            _AddSourceForm(
              t: t,
              th: th,
              options: addable,
              addSource: _addSource,
              onSourceChanged: (value) => setState(() => _addSource = value),
              idController: _addIdController,
              onIdChanged: (value) => setState(() => _addId = value),
              canSubmit: _addId.trim().isNotEmpty &&
                  _addSource.isNotEmpty &&
                  _busy != 'add',
              onSubmit: _add,
            ),
          const SizedBox(height: 12), // space-y-3
          if (_loading)
            Container(
              height: 64, // h-16
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), // rounded-xl
                color: Colors.white.withAlpha(8), // bg-white/[0.03]
              ),
            )
          else if (_loadError != null)
            Text(
              t.tr('detail.linkedSourcesLoadError'),
              style: TextStyle(fontSize: 12, color: th.textMuted),
            )
          else if (_sources.isEmpty)
            Text(
              t.tr('detail.linkedSourcesEmpty'),
              style: TextStyle(fontSize: 12, color: th.textMuted),
            )
          else
            Column(
              children: [
                for (final item in _sources)
                  _LinkedSourceRow(
                    item: item,
                    th: th,
                    t: t,
                    busy: _busy,
                    expanded: _expandedFields[item.source] ?? false,
                    mediaType: widget.mediaType,
                    onToggleFields: () => _toggleFields(item.source),
                    onMakePrimary: () => _makePrimary(item),
                    onRemove: () => _remove(item),
                    onRelink: () => widget.onOpenRelink?.call(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Кнопка «+» в шапке (size-8, hover accent).
class _AddSourceButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _AddSourceButton({
    required this.label,
    required this.th,
    required this.onTap,
  });

  @override
  State<_AddSourceButton> createState() => _AddSourceButtonState();
}

class _AddSourceButtonState extends State<_AddSourceButton> {
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
              width: 32, // size-8
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                  color: _hovered
                      ? widget.th.accent // hover:border-accent
                      : Colors.white.withAlpha(26), // border-white/10
                ),
                color: _hovered
                    ? widget.th.accent.withAlpha(51) // hover:bg-accent/20
                    : Colors.white.withAlpha(13), // bg-white/5
              ),
              child: Icon(
                LucideIcons.plus,
                size: 16,
                color: _hovered
                    ? Colors.white // hover:text-white
                    : const Color(0xFFCBD5E1), // text-slate-300
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Форма добавления: Select источника + ID/ссылка + «Привязать».
class _AddSourceForm extends StatelessWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final List<_SourceOption> options;
  final String addSource;
  final void Function(String) onSourceChanged;
  final TextEditingController idController;
  final void Function(String) onIdChanged;
  final bool canSubmit;
  final VoidCallback onSubmit;

  const _AddSourceForm({
    required this.t,
    required this.th,
    required this.options,
    required this.addSource,
    required this.onSourceChanged,
    required this.idController,
    required this.onIdChanged,
    required this.canSubmit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16), // mt-3 mb-4
      padding: const EdgeInsets.all(14), // p-3.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: Colors.white.withAlpha(5), // bg-white/[0.02]
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Источник: TsundokuSelect (шину TsundokuPopoverMenu).
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('detail.linkedSourcesSourceLabel'),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4), // space-y-1
                TsundokuSelect<_SourceOption>(
                  id: 'linked-source-select',
                  options: [
                    for (final option in options)
                      PopoverOption(value: option, label: option.label),
                  ],
                  value: options
                          .where((o) => o.value == addSource)
                          .firstOrNull ??
                      (options.isNotEmpty
                          ? options.first
                          : const _SourceOption(value: '', label: '—')),
                  onChange: (option) => onSourceChanged(option.value),
                  disabled: options.isEmpty, // availableOptions == [] → disabled
                  placeholder: options.isEmpty ? '—' : '',
                  label: t.tr('detail.linkedSourcesSourceLabel'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8), // gap-2
          // ID или ссылка.
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('detail.linkedSourcesIdLabel'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 36, // h-9
                  child: TextField(
                    controller: idController,
                    onChanged: onIdChanged,
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      color: th.textPrimary, // text-ink
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: th.bgCanvas, // bg-canvas
                      hintText: '35160--slug',
                      hintStyle:
                          TextStyle(color: th.textMuted.withAlpha(153)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10), // px-2.5
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), // rounded-lg
                        borderSide: BorderSide(
                            color: Colors.white.withAlpha(26)), // white/10
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.white.withAlpha(26)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: th.accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8), // gap-2
          // «Привязать».
          GestureDetector(
            onTap: canSubmit ? onSubmit : null,
            child: Container(
              height: 36, // h-9
              padding: const EdgeInsets.symmetric(
                  horizontal: 14), // px-3.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                color: canSubmit
                    ? th.accent // bg-accent
                    : th.accent.withAlpha(128), // disabled:opacity-50
              ),
              child: Center(
                child: Text(
                  t.tr('detail.linkedSourcesLink'),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: Colors.white,
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

/// Строка источника: имя, поле-счётчик, внешний линк, корона, сменить,
/// удалить (+ разворот чипов «взятых данных»).
class _LinkedSourceRow extends StatelessWidget {
  final LinkedSource item;
  final TsundokuTheme th;
  final I18nDictionary t;
  final String busy;
  final bool expanded;
  final String mediaType;
  final VoidCallback onToggleFields;
  final VoidCallback onMakePrimary;
  final VoidCallback onRemove;
  final VoidCallback onRelink;

  const _LinkedSourceRow({
    required this.item,
    required this.th,
    required this.t,
    required this.busy,
    required this.expanded,
    required this.mediaType,
    required this.onToggleFields,
    required this.onMakePrimary,
    required this.onRemove,
    required this.onRelink,
  });

  @override
  Widget build(BuildContext context) {
    final caption = item.title ?? (item.externalId.isNotEmpty ? item.externalId : item.source);
    final hasFields = item.providedFields != null &&
        item.providedFields!.isNotEmpty;
    final String? siteUrl = item.url ??
        buildSourceUrl(item.source, item.externalId, mediaType: mediaType);

    return Container(
      margin: const EdgeInsets.only(bottom: 6), // space-y-1.5
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: Colors.white.withAlpha(5), // bg-white/[0.02]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14, // text-sm
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: -0.25, // tracking-tight
                    color: Colors.white,
                  ),
                ),
              ),
              // Без field-счётчика — заголовок прямо на строке.
              if (!hasFields && siteUrl != null)
                Flexible(
                  child: _SourceLink(
                    text: caption,
                    url: siteUrl,
                    th: th,
                  ),
                )
              else if (!hasFields)
                Flexible(
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w500, // font-medium
                      color: th.textMuted, // text-muted
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasFields)
                    _FieldsCountButton(
                      count: item.providedFields!.length,
                      tooltip: t.tf(
                          'detail.linkedSourcesFieldsCount',
                          [item.providedFields!.length]),
                      expanded: expanded,
                      th: th,
                      onTap: onToggleFields,
                    ),
                  if (siteUrl != null)
                    _IconLinkButton(
                      icon: LucideIcons.externalLink,
                      tooltip: t.tr('detail.linkedSourcesOpen'),
                      url: siteUrl,
                      th: th,
                    )
                  else
                    const SizedBox(width: 28, height: 28),
                  if (item.isPrimary)
                    Tooltip(
                      message: t.tr('detail.linkedSourcesPrimarySource'),
                      child: const SizedBox(
                        width: 28, // h-7 w-7
                        height: 28,
                        child: Icon(LucideIcons.crown,
                            size: 15, color: Color(0xFFFBBF24)), // amber-400
                      ),
                    )
                  else
                    _CrownButton(
                      tooltip: t.tr('detail.linkedSourcesMakePrimary'),
                      busy: busy == 'primary:${item.source}',
                      th: th,
                      onTap: onMakePrimary,
                    ),
                  _PlainIconButton(
                    icon: LucideIcons.pencil,
                    tooltip: t.tr('detail.linkedSourcesRelink'),
                    th: th,
                    onTap: onRelink,
                  ),
                  if (!item.isPrimary)
                    _PlainIconButton(
                      icon: LucideIcons.trash2,
                      tooltip: t.tr('detail.linkedSourcesRemove'),
                      danger: true,
                      th: th,
                      onTap: onRemove,
                    )
                  else
                    const SizedBox(width: 28, height: 28), // spacer-выравнивание
                ],
              ),
            ],
          ),
          // Разворот чипов «взятых данных» (slide 180ms → AnimatedSize).
          if (hasFields && expanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8), // pt-2
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${item.source}:',
                          style: TextStyle(
                            fontSize: 12, // text-xs
                            color: th.textMuted, // text-muted
                          ),
                        ),
                        const SizedBox(width: 8), // gap-2
                        if (siteUrl != null)
                          Flexible(
                            child: _SourceLink(
                              text: caption,
                              url: siteUrl,
                              th: th,
                              small: true,
                            ),
                          )
                        else
                          Flexible(
                            child: Text(
                              caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: th.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6), // space-y-1.5
                    Wrap(
                      spacing: 4, // gap-1
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 4), // mr-1
                          child: Text(
                            t.tr('detail.linkedSourcesTakenLabel'),
                            style: const TextStyle(
                              fontSize: 11, // text-[11px]
                              color: Color(0xFF64748B), // text-slate-500
                            ),
                          ),
                        ),
                        for (final field in item.providedFields!)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2), // px-1.5 py-0.5
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4), // rounded
                              border: Border.all(
                                  color: Colors.white
                                      .withAlpha(13)), // border-white/5
                              color: Colors.white
                                  .withAlpha(10), // bg-white/[0.04]
                            ),
                            child: Text(
                              field,
                              style: const TextStyle(
                                fontSize: 10, // text-[10px]
                                color: Color(0xFFCBD5E1), // text-slate-300
                              ),
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
    );
  }
}

/// Ссылка на сайт (accent-soft, hover underline; в Flutter — открытая
/// внешняя ссылка за фасадом).
class _SourceLink extends StatelessWidget {
  final String text;
  final String? url;
  final TsundokuTheme th;
  final bool small;

  const _SourceLink({
    required this.text,
    required this.url,
    required this.th,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: url != null
          ? () =>
              platformService.openExternalUrl(url!)
          : null,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: small ? 12 : 12, // text-xs
          fontWeight: FontWeight.w500, // font-medium
          color: th.accentSoft, // text-accent-soft
        ),
      ),
    );
  }
}

/// Кнопка счётчика полей: число + переворачивающийся шеврон.
class _FieldsCountButton extends StatelessWidget {
  final int count;
  final String tooltip;
  final bool expanded;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _FieldsCountButton({
    required this.count,
    required this.tooltip,
    required this.expanded,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        toggled: expanded, // aria-expanded
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4), // px-1 py-1
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: Colors.white.withAlpha(128), // text-white/50
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: expanded ? 0.5 : 0, // rotate-180
                  child: Icon(LucideIcons.chevronDown,
                      size: 12, color: Colors.white.withAlpha(128)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Внешняя ссылка-иконка (ExternalLink): открытие за фасадом.
class _IconLinkButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String url;
  final TsundokuTheme th;

  const _IconLinkButton({
    required this.icon,
    required this.tooltip,
    required this.url,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: () => platformService.openExternalUrl(url),
          child: SizedBox(
            width: 28, // h-7 w-7
            height: 28,
            child: Icon(icon, size: 14, color: Colors.white.withAlpha(115)),
          ),
        ),
      ),
    );
  }
}

/// Кнопка короны (сделать основным): busy/disabled.
class _CrownButton extends StatelessWidget {
  final String tooltip;
  final bool busy;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _CrownButton({
    required this.tooltip,
    required this.busy,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: 28, // h-7 w-7
            height: 28,
            child: Icon(
              LucideIcons.crown,
              size: 15,
              color: busy
                  ? Colors.white.withAlpha(51) // disabled:opacity-50
                  : Colors.white.withAlpha(115), // text-white/45 заметная иконка
            ),
          ),
        ),
      ),
    );
  }
}

/// Плоская иконочная кнопка (Pencil/Trash2): hover-цвета.
class _PlainIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool danger;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _PlainIconButton({
    required this.icon,
    required this.tooltip,
    required this.th,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_PlainIconButton> createState() => _PlainIconButtonState();
}

class _PlainIconButtonState extends State<_PlainIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              width: 28, // h-7 w-7
              height: 28,
              child: Icon(
                widget.icon,
                size: 14,
                color: _hovered
                    ? (widget.danger
                        ? const Color(0xFFF87171) // hover:text-rose-400
                        : Colors.white) // hover:text-white
                    : Colors.white.withAlpha(115), // text-white/45 заметные иконки
              ),
            ),
          ),
        ),
      ),
    );
  }
}
