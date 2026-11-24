/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/RelinkSourceModal.svelte`.
///
/// Смена источника тайтла: поиск по провайдерам (debounce 500ms, sequence-
/// гвард), привязка выбранного результата (relinkMedia → onRelinked).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/media_labels.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/popover_menu.dart';
import '../../shared/ui/tsundoku_image.dart';

const Color _kAccentSoft = Color(0xFFA5B4FC); // --color-accent-soft
const Color _kInputBg = Color(0xFF1C202B); // bg-[#1c202b]
const Color _kSlate300 = Color(0xFFCBD5E1);
const Color _kRose200 = Color(0xFFFECDD3);
const Color _kRose300 = Color(0xFFFDA4AF);

/// Anime is its own search bucket; anything the aggregator does not know
/// becomes "all".
const Set<String> _kSearchable = <String>{
  'anime', 'manga', 'movie', 'tvshow', 'game', 'book',
};

/// Модалка смены источника (1-в-1 с RelinkSourceModal.svelte).
class RelinkSourceModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final String mediaId;

  /// Библиотечная запись: даёт поисковый терм и тип-фильтр.
  final String title;

  /// Неавторский (оригинальный) заголовок — сеет поиск и уходит в relink.
  final String? originalTitle;

  /// wire-строка типа.
  final String type;
  final String? currentSource;
  final VoidCallback onClose;

  /// Родитель подменяет detail на обновлённый payload.
  final void Function(MediaDetail payload) onRelinked;

  const RelinkSourceModal({
    super.key,
    required this.isOpen,
    required this.mediaId,
    required this.title,
    this.originalTitle,
    required this.type,
    this.currentSource,
    required this.onClose,
    required this.onRelinked,
  });

  @override
  ConsumerState<RelinkSourceModal> createState() => _RelinkSourceModalState();
}

class _RelinkSourceModalState extends ConsumerState<RelinkSourceModal> {
  List<SourceInfo> _providers = const <SourceInfo>[];
  bool _providersLoaded = false;
  String _provider = '';

  String _query = '';
  List<ExternalMedia> _results = const <ExternalMedia>[];
  bool _searching = false;
  Object? _searchError;
  String _linkingId = '';
  Object? _linkError;

  CancelToken? _searchToken;
  Timer? _debounce;
  int _sequence = 0;
  bool _prefilled = false;
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  bool get _isRu => ref.read(i18nProvider).wire == 'ru';

  String get _scope {
    final type = widget.type.toLowerCase();
    return _kSearchable.contains(type) ? type : 'all';
  }

  String get _term => _query.trim();
  bool get _canSearch => _term.length >= 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onOpenChanged();
    });
  }

  @override
  void didUpdateWidget(covariant RelinkSourceModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen ||
        widget.mediaId != oldWidget.mediaId ||
        widget.title != oldWidget.title ||
        widget.originalTitle != oldWidget.originalTitle ||
        widget.type != oldWidget.type) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onOpenChanged();
      });
    }
  }

  /// $effect-сумма: prefill + сброс provider при закрытии + загрузка
  /// провайдеров.
  void _onOpenChanged() {
    if (!widget.isOpen) {
      // Свежий пик при каждом открытии: provider предыдущего relink не
      // переносится молча.
      if (mounted && _provider.isNotEmpty) setState(() => _provider = '');
      _prefilled = false;
      return;
    }
    _maybePrefill();
    _maybeLoadProviders();
    _scheduleSearch();
  }

  /// Prefill оригинальным заголовком — обычный кейс одно нажатие Enter.
  void _maybePrefill() {
    if (!widget.isOpen || _query.isNotEmpty || _prefilled) return;
    _prefilled = true;
    final seed = widget.originalTitle?.trim().isNotEmpty ?? false
        ? widget.originalTitle!.trim()
        : widget.title;
    setState(() {
      _query = seed;
      _searchController.text = seed;
    });
    _inputFocus.requestFocus(); // rAF-focus
  }

  /// $effect: при открытии и пустом списке — getSources (enabled-фильтр).
  Future<void> _maybeLoadProviders() async {
    if (!widget.isOpen || _providersLoaded) return;
    _providersLoaded = true;
    try {
      final list = await ref.read(apiClientProvider).getSources();
      if (!mounted) return;
      setState(() {
        _providers = list.where((source) => source.isEnabled).toList();
      });
      // provider-каскад и поиск зависят от options — перезапуск $effect.
      _resolveProvider();
      _scheduleSearch();
    } catch (_) {
      if (mounted) setState(() => _providers = const <SourceInfo>[]);
    }
  }

  /// supportsType: источник заявляет mediaTypes — provider предлагается
  /// ровно тогда, когда умеет этот тип (лечит дрейф hand-kept-списка).
  bool _supportsType(SourceInfo source, String mediaType) {
    return source.mediaTypes.any((d) => d.toLowerCase() == mediaType);
  }

  List<SourceInfo> get _providerOptions {
    final wanted = widget.type.toLowerCase();
    final matched = _providers
        .where((source) => _supportsType(source, wanted))
        .toList();
    // Никто не заявил тип — предлагаем все включённые, а не пустой пикер,
    // блокирующий единственное действие диалога.
    return matched.isNotEmpty ? matched : _providers;
  }

  /// Открытие на текущем провайдере: обычный кейс («тот же сервис, лучше
  /// совпадение») без пика.
  void _resolveProvider() {
    final options = _providerOptions;
    if (!widget.isOpen || _provider.isNotEmpty || options.isEmpty) return;
    SourceInfo? current;
    if (widget.currentSource != null) {
      final needle = widget.currentSource!.toLowerCase();
      for (final option in options) {
        if ('${option.id} ${option.name}'.toLowerCase().contains(needle)) {
          current = option;
          break;
        }
      }
    }
    setState(() => _provider = current?.id ?? options.first.id);
  }

  /// Debounce 500ms — один запрос на паузу в наборе; внеочередной ответ не
  /// перезапишет более новый (sequence).
  void _scheduleSearch() {
    _debounce?.cancel();
    final current = _term;
    final target = _provider;
    if (!widget.isOpen || current.length < 2 || target.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const <ExternalMedia>[];
          _searching = false;
        });
      }
      return;
    }

    final mine = ++_sequence;
    _searchToken?.cancel();
    final local = CancelToken();
    _searchToken = local;

    if (mounted) {
      setState(() {
        _searching = true;
        _searchError = null;
      });
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final rows = await ref
            .read(apiClientProvider)
            .searchExternal(_scope, current, cancelToken: local, source: target);
        if (mine != _sequence || !mounted) return;
        setState(() => _results = rows);
      } catch (error) {
        if (mine != _sequence || !mounted) return;
        // DOMException-аборты игнорируются; CancelToken-отмена — тоже.
        if (error is DioException &&
            (error.type == DioExceptionType.cancel ||
                error.type == DioExceptionType.connectionError &&
                    local.isCancelled)) {
          return;
        }
        if (local.isCancelled) return;
        setState(() {
          _searchError = error;
          _results = const <ExternalMedia>[];
        });
      } finally {
        if (mine == _sequence && mounted) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _link(ExternalMedia result) async {
    if (_linkingId.isNotEmpty) return;
    setState(() {
      _linkingId = result.externalId;
      _linkError = null;
    });
    try {
      final payload = await ref.read(apiClientProvider).relinkMedia(
            widget.mediaId,
            externalId: result.externalId,
            source: result.externalSource ?? '',
            type: widget.type,
            title: result.title,
          );
      widget.onRelinked(payload);
    } catch (error) {
      if (mounted) setState(() => _linkError = error);
    } finally {
      if (mounted) setState(() => _linkingId = '');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchToken?.cancel();
    _inputFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final isRu = _isRu;
    final providerOptions = _providerOptions;

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.lg,
      contentPadding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7, // max-h-[70vh]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(th, isRu),
            _buildSearchSection(th, isRu, providerOptions),
            Flexible(child: _buildResults(th, isRu)),
            if (_linkError != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12), // px-5 py-3
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
                ),
                child: Text(
                  errorMessage(_linkError!, ref.read(i18nProvider)),
                  style: const TextStyle(
                      fontSize: 12, color: _kRose300), // text-xs text-rose-300
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Header ----

  Widget _buildHeader(TsundokuTheme th, bool isRu) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
      ),
      child: Row(
        children: [
          Icon(LucideIcons.link2, size: 18, color: _kAccentSoft),
          const SizedBox(width: 12), // gap-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRu ? 'Сменить источник' : 'Change source',
                  style: const TextStyle(
                    fontSize: 14, // text-sm
                    fontWeight: FontWeight.w700, // font-bold
                    color: Colors.white,
                  ),
                ),
                Text(
                  isRu
                      ? 'Найдите тот же тайтл в другом провайдере и привяжите его к этой записи.'
                      : 'Find the same title in another provider and attach it to this record.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // truncate
                  style: TextStyle(
                      fontSize: 12, color: th.textMuted), // text-muted
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Semantics(
              button: true,
              label: isRu ? 'Закрыть' : 'Close',
              child: Container(
                padding: const EdgeInsets.all(6), // p-1.5
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // rounded-md
                  color: Colors.transparent,
                ),
                child: Icon(LucideIcons.x,
                    size: 16, color: th.textMuted), // hover-ветка упрощена
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Search + provider ----

  Widget _buildSearchSection(
      TsundokuTheme th, bool isRu, List<SourceInfo> providerOptions) {
    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40, // h-10
            padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(color: Colors.white.withAlpha(21)),
              color: _kInputBg,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.search,
                    size: 15, color: th.textMuted), // text-muted
                const SizedBox(width: 8), // gap-2
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _inputFocus,
                    onChanged: (value) {
                      _query = value;
                      _scheduleSearch();
                    },
                    onSubmitted: (_) => _scheduleSearch(),
                    style: const TextStyle(
                        fontSize: 14, color: Colors.white), // text-sm
                    // outline-none: фокус-кольцо темы поля приглушено —
                    // границу несёт контейнер h-10.
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText:
                          isRu ? 'Название тайтла…' : 'Title name…',
                      hintStyle: TextStyle(color: th.textMuted),
                    ),
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kAccentSoft),
                  ),
              ],
            ),
          ),

          // Provider select (slide-переход ⏭️ — появление мгновенное).
          if (providerOptions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8), // mt-2
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (isRu ? 'Искать в сервисе' : 'Search in provider')
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 11, // text-[11px]
                      fontWeight: FontWeight.w600, // font-semibold
                      letterSpacing: 0.6, // tracking-wider
                      color: th.textMuted, // text-muted uppercase tracking
                    ),
                  ),
                  const SizedBox(height: 4), // mb-1
                  TsundokuSelect<String>(
                    id: 'relink-provider',
                    options: [
                      for (final option in providerOptions)
                        PopoverOption(value: option.id, label: option.name),
                    ],
                    value: _provider,
                    onChange: (next) => setState(() => _provider = next),
                    label: isRu ? 'Искать в сервисе' : 'Search in provider',
                  ),
                ],
              ),
            ),
          ],

          if (widget.currentSource != null && widget.currentSource!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8), // mt-2
              child: Text.rich(
                TextSpan(
                  text: isRu ? 'Текущий источник' : 'Current source',
                  style: TextStyle(
                      fontSize: 12, color: th.textMuted), // text-muted
                  children: [
                    const TextSpan(text: ': '),
                    TextSpan(
                      text: widget.currentSource,
                      style: const TextStyle(
                          fontSize: 12, color: _kSlate300), // text-slate-300
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Results ----

  Widget _buildResults(TsundokuTheme th, bool isRu) {
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(16), // p-4
        child: Text(
          errorMessage(_searchError!, ref.read(i18nProvider)),
          style: const TextStyle(
              fontSize: 14, color: _kRose200), // text-sm text-rose-200
        ),
      );
    }
    if (!_canSearch) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
        child: Center(
          child: Text(
            isRu ? 'Введите хотя бы 2 символа.' : 'Type at least 2 characters.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: th.textMuted), // text-muted text-sm
          ),
        ),
      );
    }
    if (!_searching && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
        child: Center(
          child: Text(
            isRu
                ? 'Ничего не найдено. Попробуйте другое название.'
                : 'Nothing found. Try another title.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: th.textMuted), // text-muted text-sm
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16), // p-4
      child: Column(
        children: [
          for (final result in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 8), // space-y-2
              child: _ResultRow(
                result: result,
                linkingId: _linkingId,
                linkLabel: isRu ? 'Привязать' : 'Link',
                onLink: () => unawaited(_link(result)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Одна строка результата поиска (li).
class _ResultRow extends StatelessWidget {
  final ExternalMedia result;
  final String linkingId;
  final String linkLabel;
  final VoidCallback onLink;

  const _ResultRow({
    required this.result,
    required this.linkingId,
    required this.linkLabel,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final isLinking = linkingId == result.externalId;
    final busy = linkingId.isNotEmpty;
    final badge = result.externalSource != null && result.externalSource!.isNotEmpty
        ? sourceBadgeClasses(result.externalSource!)
        : null;

    return Container(
      padding: const EdgeInsets.all(10), // p-2.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(
            color: Colors.white.withAlpha(15)), // border-white/[0.06]
        color: th.bgSurface, // --color-panel-line = var(--bg-surface)
      ),
      child: Row(
        children: [
          // Постер 2/3 (h-14 w-10) + baseUrl-склейка прокси (решение #25).
          Container(
            width: 40, // w-10
            height: 56, // h-14
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              color: th.bgSurface, // bg-[var(--color-field)]
            ),
            clipBehavior: Clip.antiAlias,
            child: result.coverUrl != null
                ? TsundokuImage(
                    imageUrl: result.coverUrl,
                    fit: BoxFit.cover,
                    semanticLabel: result.title, // alt
                    errorWidget: const SizedBox.expand(),
                  )
                : Center(
                    child: Icon(LucideIcons.image,
                        size: 16, color: th.textMuted),
                  ),
          ),
          const SizedBox(width: 12), // gap-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // truncate
                  style: const TextStyle(
                    fontSize: 14, // text-sm
                    fontWeight: FontWeight.w600, // font-semibold
                    color: Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4), // mt-1
                  child: Wrap(
                    spacing: 6, // gap-1.5
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2), // px-1.5 py-0.5
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(4), // rounded
                            border: Border.all(color: badge.border),
                            color: badge.background,
                          ),
                          child: Text(
                            result.externalSource!,
                            style: TextStyle(
                              fontSize: 10, // text-[10px]
                              fontWeight: FontWeight.w600, // font-semibold
                              color: badge.text,
                            ),
                          ),
                        ),
                      if (result.releaseYear != null)
                        Text(
                          '${result.releaseYear}',
                          style: TextStyle(
                              fontSize: 11, color: th.textMuted), // text-[11px]
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12), // gap-3
          GestureDetector(
            onTap: busy ? null : onLink,
            child: Opacity(
              opacity: busy ? 0.5 : 1, // disabled:opacity-50
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6), // px-3 py-1.5
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // rounded-md
                  border: Border.all(
                      color: th.accent.withAlpha(102)), // accent/40
                  color: th.accent.withAlpha(26), // accent/10
                ),
                child: isLinking
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kAccentSoft),
                      )
                    : Text(
                        linkLabel,
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.w600, // font-semibold
                          color: _kAccentSoft, // accent-soft
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
