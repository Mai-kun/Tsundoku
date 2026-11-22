/// 1:1 port of `mediatracker-ui/src/features/import-media/ImportPanel.svelte`.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/import-media/mangalib_auth.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/platform/platform.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';

enum ImportProvider {
  anilist('anilist', 'AniList', 'AL', 'JSON или профиль пользователя'),
  mangalib('mangalib', 'MangaLib', 'ML', 'MangaLib / AnimeLib / RanobeLib'),
  mal('mal', 'MyAnimeList', 'MAL', 'XML / JSON'),
  shikimori('shikimori', 'Shikimori', 'SH', 'XML / JSON'),
  letterboxd('letterboxd', 'Letterboxd', 'L', 'Movie CSV'),
  goodreads('goodreads', 'Goodreads', 'G', 'Book CSV'),
  steam('steam', 'Steam', 'S', 'Games / Profile'),
  anixart('anixart', 'Anixart', 'AX', 'Экспорт аниме в CSV'),
  custom('custom', 'CSV / JSON', '{ }', 'Универсальный JSON / CSV');

  final String id;
  final String label;
  final String iconText;
  final String subtitle;

  const ImportProvider(this.id, this.label, this.iconText, this.subtitle);
}

class ImportPanel extends ConsumerStatefulWidget {
  final VoidCallback? onImportCompleted;
  final ValueChanged<String>? onNavigateToList;
  final VoidCallback? onClose;
  final bool showCloseButton;

  const ImportPanel({
    super.key,
    this.onImportCompleted,
    this.onNavigateToList,
    this.onClose,
    this.showCloseButton = false,
  });

  @override
  ConsumerState<ImportPanel> createState() => ImportPanelState();
}

class ImportPanelState extends ConsumerState<ImportPanel> {
  ImportProvider _provider = ImportProvider.anilist;
  ({String name, Uint8List bytes})? _file;

  // AniList
  String _anilistMode = 'profile'; // 'profile' | 'file'
  final TextEditingController _anilistUsernameController =
      TextEditingController();

  // Steam
  String _steamMode = 'profile'; // 'profile' | 'file'
  final TextEditingController _steamProfileController =
      TextEditingController();
  final TextEditingController _steamApiKeyController = TextEditingController();
  bool _steamKeyConfigured = false;
  bool _steamSkipShortSessions = true;
  bool _steamSyncAchievements = true;
  bool _saveSteamKey = false;

  // MangaLib
  String _mangalibMode = 'collector'; // 'collector' | 'file'
  final TextEditingController _mangalibProfileController =
      TextEditingController();
  final List<int> _mangalibSites = <int>[1, 5, 3, 2, 4];
  final bool _mangalibIncludeCustomFolders = true;
  bool _mangalibDetectBusy = false;

  // Common options
  bool _skipDuplicates = true;
  bool _addToList = false;
  String _listMode = 'new'; // 'new' | 'existing'
  String? _targetListId;
  final TextEditingController _newListNameController = TextEditingController();
  final Set<int> _selectedStatuses = <int>{1, 2, 4, 6, 5};
  static const _folderOptions = [
    (id: 1, label: 'Читаю / Смотрю'),
    (id: 2, label: 'В планах'),
    (id: 4, label: 'Прочитано'),
    (id: 6, label: 'Отложено / Жду'),
    (id: 3, label: 'Брошено / Удалено'),
    (id: 5, label: 'Любимые'),
  ];

  // State
  List<CustomListSummary> _lists = const <CustomListSummary>[];
  bool _busy = false;
  String? _error;
  ImportResultDto? _result;
  bool _showSkippedTitles = false;
  bool _templateCopied = false;

  @override
  void initState() {
    super.initState();
    _loadListsAndSources();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mangalibAuthProvider.notifier).readMangalibStatus();
    });
  }

  @override
  void dispose() {
    _anilistUsernameController.dispose();
    _steamProfileController.dispose();
    _steamApiKeyController.dispose();
    _mangalibProfileController.dispose();
    _newListNameController.dispose();
    super.dispose();
  }

  Future<void> _loadListsAndSources() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.getLists(),
        api.getSources(),
      ]);
      if (mounted) {
        setState(() {
          _lists = results[0] as List<CustomListSummary>;
          final sources = results[1] as List<SourceInfo>;
          final steamSource = sources.where((s) => s.id == 'steam').firstOrNull;
          _steamKeyConfigured = steamSource?.hasKey ?? false;
        });
      }
    } catch (_) {
      // non-blocking
    }
  }

  List<String> get _allowedExtensions {
    switch (_provider) {
      case ImportProvider.mangalib:
        return const ['json'];
      case ImportProvider.mal:
        return const ['xml', 'gz'];
      case ImportProvider.shikimori:
        return const ['json', 'csv'];
      case ImportProvider.letterboxd:
      case ImportProvider.goodreads:
        return const ['csv'];
      case ImportProvider.anixart:
        return const ['zip'];
      default:
        return const ['json', 'csv'];
    }
  }

  Future<void> _pickFile() async {
    final picked = await platformService.pickFile();
    if (picked != null && mounted) {
      setState(() {
        _file = picked;
        _error = null;
      });
    }
  }

  Future<void> _copyTemplate(String content) async {
    await platformService.copyText(content);
    if (mounted) {
      setState(() => _templateCopied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _templateCopied = false);
      });
    }
  }

  Future<void> _detectMangalibBrowser() async {
    setState(() => _mangalibDetectBusy = true);
    try {
      final res =
          await ref.read(apiClientProvider).detectMangalibBrowserSession();
      if (res != null && res.success && mounted) {
        await ref
            .read(mangalibAuthProvider.notifier)
            .adoptBrowserSession(res.userId);
        if (res.userId != null) {
          _mangalibProfileController.text = '${res.userId}';
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _mangalibDetectBusy = false);
    }
  }

  Future<void> _runImport() async {
    if (_busy) return;
    final t = ref.read(tProvider);

    final anilistProfile =
        _provider == ImportProvider.anilist && _anilistMode == 'profile';
    final steamProfile =
        _provider == ImportProvider.steam && _steamMode == 'profile';
    final mangalibCollector =
        _provider == ImportProvider.mangalib && _mangalibMode == 'collector';

    if (anilistProfile) {
      if (_anilistUsernameController.text.trim().isEmpty) {
        setState(() => _error = t.tr('importModal.anilistUsernameError'));
        return;
      }
    } else if (steamProfile) {
      if (_steamProfileController.text.trim().isEmpty) {
        setState(() => _error = 'Укажите Steam ID или ссылку на профиль.');
        return;
      }
    } else if (mangalibCollector) {
      final auth = ref.read(mangalibAuthProvider);
      final idOrUrl =
          _mangalibProfileController.text.trim().isNotEmpty
              ? _mangalibProfileController.text.trim()
              : auth.userId;
      if (idOrUrl.isEmpty) {
        setState(() => _error = 'Укажите ID пользователя MangaLib или ссылку.');
        return;
      }
    } else {
      if (_file == null) {
        setState(() => _error = 'Выберите файл для импорта.');
        return;
      }
      final ext = _file!.name.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(ext)) {
        setState(() => _error = 'Неподдерживаемый формат файла: .$ext');
        return;
      }
    }

    if (_addToList && _listMode == 'existing' && _targetListId == null) {
      setState(() => _error = t.tr('importModal.chooseListError'));
      return;
    }
    if (_addToList &&
        _listMode == 'new' &&
        _newListNameController.text.trim().isEmpty) {
      setState(() => _error = 'Укажите название нового списка.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final targetListId =
          _addToList && _listMode == 'existing' ? _targetListId : null;
      final newListName = _addToList && _listMode == 'new'
          ? _newListNameController.text.trim()
          : null;

      ImportResultDto res;

      if (anilistProfile) {
        res = await api.importAniListProfile(AniListProfilePayload(
          username: _anilistUsernameController.text.trim(),
          createList: _addToList,
          targetListId: targetListId,
          newListName: newListName,
          skipDuplicates: _skipDuplicates,
        ));
      } else if (steamProfile) {
        final val = _steamProfileController.text.trim();
        final isNumeric = RegExp(r'^\d+$').hasMatch(val);
        res = await api.importSteamProfile(SteamImportPayload(
          steamId: isNumeric ? val : null,
          profileUrl: isNumeric ? null : val,
          steamApiKey: _steamApiKeyController.text.trim().isNotEmpty
              ? _steamApiKeyController.text.trim()
              : null,
          skipDuplicates: _skipDuplicates,
          targetListId: targetListId,
          newListName: newListName,
          minPlaytimeMinutes: _steamSkipShortSessions ? 120 : null,
          syncAchievements: _steamSyncAchievements,
        ));

        if (_saveSteamKey &&
            _steamApiKeyController.text.trim().isNotEmpty) {
          await api.saveSourceKey(
              'steam', _steamApiKeyController.text.trim());
        }
      } else if (mangalibCollector) {
        final auth = ref.read(mangalibAuthProvider);
        final idOrUrl = _mangalibProfileController.text.trim().isNotEmpty
            ? _mangalibProfileController.text.trim()
            : auth.userId;
        res = await api.importMangaLibProfile(MangaLibProfilePayload(
          profileUrlOrId: idOrUrl,
          siteIds: _mangalibSites,
          bearerToken: null,
          statusIds: null,
          includeCustomFolders: _mangalibIncludeCustomFolders,
          skipDuplicates: _skipDuplicates,
          targetListId: targetListId,
          newListName: newListName,
        ));
      } else {
        final formMap = <String, dynamic>{
          'file': MultipartFile.fromBytes(
            _file!.bytes,
            filename: _file!.name,
          ),
          'provider': _provider.id,
          'skipDuplicates': _skipDuplicates,
        };
        if (targetListId != null) formMap['targetListId'] = targetListId;
        if (newListName != null) formMap['newListName'] = newListName;
        final formData = FormData.fromMap(formMap);
        res = await api.importFile(formData);
      }

      if (mounted) {
        setState(() {
          _result = res;
        });
        widget.onImportCompleted?.call();
        _loadListsAndSources();
      }
    } catch (caught) {
      if (mounted) {
        setState(() {
          _error = caught is Exception
              ? caught.toString().replaceAll('Exception: ', '')
              : 'Ошибка импорта';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _resetResult() {
    setState(() {
      _result = null;
      _file = null;
      _error = null;
      _showSkippedTitles = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (widget.showCloseButton) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x1A6366F1), // indigo-500/10
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x336366F1)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.folderInput,
                        size: 20,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tr('importModal.title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.tr('importModal.description'),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showCloseButton && widget.onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                icon: Icon(
                  LucideIcons.x,
                  size: 18,
                  color: theme.textMuted,
                ),
                onPressed: widget.onClose,
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Success result banner
        if (_result != null) ...[
          _buildResultBanner(t, theme),
          const SizedBox(height: 20),
        ],

        if (_result == null) ...[
          // Provider Selection Rail
          _buildProviderSelector(theme, t),
          const SizedBox(height: 20),

          // Provider Specific Settings
          _buildProviderBody(t, theme),
          const SizedBox(height: 20),

          // Common Options (Duplicates + Destination List)
          _buildCommonOptions(t, theme),
          const SizedBox(height: 20),

          // Error alert
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1AF43F5E), // rose-500/10
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x33F43F5E)), // rose-500/20
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    size: 16,
                    color: Color(0xFFFB7185), // rose-400
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFB7185),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Footer action button
          _buildSubmitButton(t, theme),
        ],
      ],
    );
  }

  Widget _buildResultBanner(I18nDictionary t, TsundokuTheme theme) {
    final res = _result!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x1A10B981), // emerald-500/10
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x4034D399)), // emerald-400/25
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x3334D399),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.checkCircle2,
                  size: 24,
                  color: Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tr('importModal.success'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA7F3D0),
                    ),
                  ),
                  Text(
                    _provider.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xCC6EE7B7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.total'),
                  value: '${res.totalFound}',
                  valueColor: Colors.white,
                  bgColor: const Color(0x99181E2C),
                  borderColor: Colors.white.withAlpha(25),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.imported'),
                  value: '${res.importedCount}',
                  valueColor: const Color(0xFFA7F3D0),
                  bgColor: const Color(0x1410B981),
                  borderColor: const Color(0x3334D399),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.skipped'),
                  value: '${res.skippedDuplicates}',
                  valueColor: Colors.white,
                  bgColor: const Color(0x99181E2C),
                  borderColor: Colors.white.withAlpha(25),
                ),
              ),
            ],
          ),
          if (res.skippedTitles != null && res.skippedTitles!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x66181E2C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _showSkippedTitles = !_showSkippedTitles),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.tf('importModal.skippedDuplicatesWithCount', [res.skippedTitles!.length]),
                          style: TextStyle(fontSize: 12, color: theme.textMuted),
                        ),
                        Icon(
                          _showSkippedTitles ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                          size: 14,
                          color: theme.textMuted,
                        ),
                      ],
                    ),
                  ),
                  if (_showSkippedTitles) ...[
                    const SizedBox(height: 8),
                    Text(
                      res.skippedTitles!.join(', '),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (res.targetListId != null)
                TsundokuButton(
                  variant: ButtonVariant.primary,
                  size: ButtonSize.md,
                  onPressed: () => widget.onNavigateToList?.call(res.targetListId!),
                  child: Text(t.tr('importModal.openList')),
                ),
              TsundokuButton(
                variant: ButtonVariant.secondary,
                size: ButtonSize.md,
                onPressed: _resetResult,
                child: Text(t.tr('importModal.importAnother')),
              ),
              if (widget.showCloseButton && widget.onClose != null)
                TsundokuButton(
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.md,
                  onPressed: widget.onClose,
                  child: Text(t.tr('common.close')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color valueColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    required Color dotColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Color(0xFFE2E8F0),
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dotColor,
            ),
          ),
      ],
    );
  }

  Widget _buildProviderSelector(TsundokuTheme theme, I18nDictionary t) {
    final curTheme = theme.sourceTheme(_provider.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.source'),
          dotColor: curTheme.accent,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 500
                    ? 2
                    : 1;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ImportProvider.values.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 3.2,
              ),
              itemBuilder: (context, index) {
                final p = ImportProvider.values[index];
                final isSelected = _provider == p;
                final pTheme = theme.sourceTheme(p.id);

                return InkWell(
                  onTap: () {
                    setState(() {
                      _provider = p;
                      _file = null;
                      _error = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? pTheme.surface : const Color(0xCC181E2C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? pTheme.accent : Colors.white.withAlpha(25),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: pTheme.border,
                                blurRadius: 4,
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: pTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: pTheme.border,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            p.iconText,
                            style: TextStyle(
                              fontSize: p.iconText.length > 2 ? 11 : 13,
                              fontWeight: FontWeight.w800,
                              color: pTheme.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                p.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(LucideIcons.check, size: 16, color: pTheme.accent),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildProviderBody(I18nDictionary t, TsundokuTheme theme) {
    switch (_provider) {
      case ImportProvider.anilist:
        return _buildAniListBody(t, theme);
      case ImportProvider.mangalib:
        return _buildMangaLibBody(t, theme);
      case ImportProvider.steam:
        return _buildSteamBody(t, theme);
      case ImportProvider.mal:
      case ImportProvider.shikimori:
      case ImportProvider.letterboxd:
      case ImportProvider.goodreads:
      case ImportProvider.anixart:
      case ImportProvider.custom:
        return _buildFilePickerBody(t, theme);
    }
  }

  Widget _buildAniListBody(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme('anilist');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.fileLabel'),
          dotColor: st.accent,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTabPill(
                label: 'По никнейму профиля',
                active: _anilistMode == 'profile',
                onTap: () => setState(() => _anilistMode = 'profile'),
                st: st,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabPill(
                label: 'Загрузить JSON-файл',
                active: _anilistMode == 'file',
                onTap: () => setState(() => _anilistMode = 'file'),
                st: st,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_anilistMode == 'profile') ...[
          TextField(
            controller: _anilistUsernameController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              labelText: t.tr('importModal.anilistUsername'),
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              hintText: 'Например, Mai-kun',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              prefixIcon: const Icon(LucideIcons.user, size: 16),
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: st.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AniList: Settings → Account → Export Data. Либо введите никнейм профиля — список загрузится через публичный API.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.4),
          ),
        ] else ...[
          _buildFileDropArea(hint: 'AniList JSON экспорт (.json)', st: st),
        ],
      ],
    );
  }

  Widget _buildSteamBody(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme('steam');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.fileLabel'),
          dotColor: st.accent,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTabPill(
                label: 'Steam профиль',
                active: _steamMode == 'profile',
                onTap: () => setState(() => _steamMode = 'profile'),
                st: st,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabPill(
                label: 'Файл',
                active: _steamMode == 'file',
                onTap: () => setState(() => _steamMode = 'file'),
                st: st,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_steamMode == 'profile') ...[
          TextField(
            controller: _steamProfileController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Steam ID или ссылка на профиль',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              hintText: '76561198... или https://steamcommunity.com/id/...',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: st.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _steamApiKeyController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Steam Web API Key (опционально)',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              hintText: _steamKeyConfigured
                  ? 'Ключ уже сохранён на сервере'
                  : 'Ключ для получения достижений и скрытых библиотек',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: st.accent),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildCheckboxRow(
            label: 'Пропускать игры с временем < 2 часов',
            value: _steamSkipShortSessions,
            onChanged: (v) => setState(() => _steamSkipShortSessions = v ?? true),
          ),
          _buildCheckboxRow(
            label: 'Синхронизировать достижения',
            value: _steamSyncAchievements,
            onChanged: (v) => setState(() => _steamSyncAchievements = v ?? true),
          ),
          if (!_steamKeyConfigured)
            _buildCheckboxRow(
              label: 'Сохранить ключ Steam в настройках',
              value: _saveSteamKey,
              onChanged: (v) => setState(() => _saveSteamKey = v ?? false),
            ),
        ] else ...[
          _buildFileDropArea(hint: 'Steam JSON/CSV экспорт', st: st),
        ],
      ],
    );
  }

  Widget _buildMangaLibBody(I18nDictionary t, TsundokuTheme theme) {
    final mangalibAuth = ref.watch(mangalibAuthProvider);
    final st = theme.sourceTheme('mangalib');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.fileLabel'),
          dotColor: st.accent,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTabPill(
                label: 'Быстрый импорт',
                active: _mangalibMode == 'collector',
                onTap: () => setState(() => _mangalibMode = 'collector'),
                st: st,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabPill(
                label: 'Файл Tsundoku SocialLib',
                active: _mangalibMode == 'file',
                onTap: () => setState(() => _mangalibMode = 'file'),
                st: st,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_mangalibMode == 'collector') ...[
          if (mangalibAuth.connected) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1A10B981),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x3310B981)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.check, size: 16, color: Color(0xFF34D399)),
                  const SizedBox(width: 8),
                  Text(
                    'Сессия MangaLib подключена (ID: ${mangalibAuth.userId.isNotEmpty ? mangalibAuth.userId : 'активна'})',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFA7F3D0)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _mangalibProfileController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              labelText: 'ID пользователя MangaLib или ссылка',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              hintText: mangalibAuth.userId.isNotEmpty
                  ? mangalibAuth.userId
                  : 'Например, 1234567 или https://mangalib.me/user/1234567',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: st.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _mangalibDetectBusy ? null : _detectMangalibBrowser,
            icon: _mangalibDetectBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.sparkles, size: 14),
            label: const Text(
              'Определить сессию из браузера',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ] else ...[
          _buildFileDropArea(hint: 'tsundoku-sociallib.json', st: st),
        ],
      ],
    );
  }

  Widget _buildFilePickerBody(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme(_provider.id);
    String formatHint;
    switch (_provider) {
      case ImportProvider.mal:
        formatHint = 'XML экспорт MyAnimeList (.xml, .gz)';
        break;
      case ImportProvider.shikimori:
        formatHint = 'Shikimori экспорт (.json, .csv)';
        break;
      case ImportProvider.letterboxd:
        formatHint = 'Letterboxd CSV (watched.csv / diary.csv)';
        break;
      case ImportProvider.goodreads:
        formatHint = 'Goodreads CSV экспорт (.csv)';
        break;
      case ImportProvider.anixart:
        formatHint = 'Anixart ZIP архив (.zip)';
        break;
      default:
        formatHint = 'CSV или JSON файл';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.fileLabel'),
          dotColor: st.accent,
        ),
        const SizedBox(height: 10),
        _buildFileDropArea(hint: formatHint, st: st),
        if (_provider == ImportProvider.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _copyTemplate(
                    'title,type,status,score,progress,startedAt,finishedAt,notes'),
                icon: Icon(
                  _templateCopied ? LucideIcons.check : LucideIcons.copy,
                  size: 14,
                ),
                label: Text(
                  _templateCopied ? 'Скопировано!' : 'Скопировать CSV шаблон',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFileDropArea({required String hint, required ImportSourceTheme st}) {
    final hasFile = _file != null;

    return PlatformDropZone(
      onFilesDropped: (files) {
        if (files.isNotEmpty && mounted) {
          setState(() {
            _file = (name: files.first.name, bytes: files.first.bytes);
            _error = null;
          });
        }
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickFile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: hasFile
                ? const Color(0x0D10B981)
                : st.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile
                  ? const Color(0x6610B981)
                  : st.accent.withAlpha(90),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasFile
                      ? const Color(0x3310B981)
                      : const Color(0x14FFFFFF),
                ),
                alignment: Alignment.center,
                child: Icon(
                  hasFile ? LucideIcons.fileText : LucideIcons.upload,
                  size: 22,
                  color: hasFile ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                hasFile ? _file!.name : 'Нажмите или перетащите файл сюда',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasFile ? FontWeight.w600 : FontWeight.w500,
                  color: hasFile ? Colors.white : const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              if (hasFile) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _file = null;
                    });
                  },
                  child: const Text('Изменить файл', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonOptions(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme(_provider.id);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x99181E2C), // bg-card/60
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: t.tr('importModal.optionsTitle'),
            dotColor: st.accent,
          ),
          const SizedBox(height: 12),
          _buildCheckboxRow(
            label: 'Пропускать дубликаты (по названию и автору)',
            value: _skipDuplicates,
            accentColor: st.accent,
            onChanged: (v) => setState(() => _skipDuplicates = v ?? true),
          ),
          _buildCheckboxRow(
            label: t.tr('importModal.addToList'),
            value: _addToList,
            accentColor: st.accent,
            onChanged: (v) => setState(() => _addToList = v ?? false),
          ),
          if (_addToList) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTabPill(
                        label: 'Новый список',
                        active: _listMode == 'new',
                        onTap: () => setState(() => _listMode = 'new'),
                        st: st,
                      ),
                      const SizedBox(width: 8),
                      _buildTabPill(
                        label: 'Существующий список',
                        active: _listMode == 'existing',
                        onTap: () => setState(() => _listMode = 'existing'),
                        st: st,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_listMode == 'new')
                    TextField(
                      controller: _newListNameController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Название нового списка',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        hintText: 'Например, Импорт ${_provider.label}',
                        filled: true,
                        fillColor: const Color(0x0AFFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: st.accent),
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _targetListId,
                      dropdownColor: const Color(0xFF1E2230),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Выберите список',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0x0AFFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: st.accent),
                        ),
                      ),
                      items: _lists.map((l) {
                        return DropdownMenuItem<String>(
                          value: l.id,
                          child: Text(l.name),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _targetListId = val),
                    ),
                ],
              ),
            ),
          ],

          // Folder selection chips
          if (_provider != ImportProvider.mangalib &&
              _provider != ImportProvider.anixart &&
              _provider != ImportProvider.steam) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withAlpha(15), height: 1),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: st.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.tr('importModal.listsToImport').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Выбрано: ${_selectedStatuses.length} из ${_folderOptions.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: st.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 600 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _folderOptions.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 3.6,
                  ),
                  itemBuilder: (context, index) {
                    final opt = _folderOptions[index];
                    final isChecked = _selectedStatuses.contains(opt.id);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isChecked) {
                            if (_selectedStatuses.length > 1) {
                              _selectedStatuses.remove(opt.id);
                            }
                          } else {
                            _selectedStatuses.add(opt.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isChecked ? st.surface : const Color(0x05FFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isChecked ? st.accent : const Color(0x14FFFFFF),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isChecked ? st.accent : Colors.black26,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isChecked ? st.accent : Colors.white24,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: isChecked
                                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                opt.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                                  color: isChecked ? st.text : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton(I18nDictionary t, TsundokuTheme theme) {
    return Align(
      alignment: Alignment.centerRight,
      child: TsundokuButton(
        variant: ButtonVariant.primary,
        size: ButtonSize.lg,
        loading: _busy,
        onPressed: _busy ? null : _runImport,
        child: Text(_busy ? t.tr('importModal.importing') : t.tr('importModal.start')),
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required bool active,
    required VoidCallback onTap,
    ImportSourceTheme? st,
  }) {
    final activeBg = st?.surface ?? const Color(0x266366F1);
    final activeBorder = st?.border ?? const Color(0x666366F1);
    final activeText = st?.text ?? Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeBg : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? activeBorder : const Color(0x14FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? activeText : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxRow({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
    Color? accentColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: value,
                activeColor: accentColor ?? const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
