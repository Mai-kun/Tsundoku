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
import 'package:tsundoku_flutter/shared/ui/segmented_control.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';

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
  bool _dragging = false;

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
  static const _socialLibSites = [
    (id: 1, name: 'MangaLib', tag: 'Манга', type: 'manga'),
    (id: 5, name: 'AnimeLib', tag: 'Аниме', type: 'anime'),
    (id: 3, name: 'RanobeLib', tag: 'Ранобэ', type: 'book'),
    (id: 2, name: 'SlashLib / YaoiLib', tag: 'Слэш', type: 'manga'),
    (id: 4, name: 'HentaiLib', tag: '18+', type: 'manga'),
  ];
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

  // Template state
  bool _showTemplate = false;
  static const _templateJson = '''[
  {
    "title": "Fullmetal Alchemist: Brotherhood",
    "type": "anime",
    "status": "completed",
    "score": 9,
    "progress": 64,
    "totalCount": 64,
    "studio": "Bones",
    "releaseYear": 2009
  },
  {
    "title": "Berserk",
    "type": "manga",
    "status": "reading",
    "score": 10,
    "progress": 350,
    "totalCount": 374,
    "author": "Kentaro Miura",
    "year": 1989
  }
]''';

  static const _templateCsv =
      'title,type,status,score,progress,totalCount,author,releaseYear';

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

  String get _fileAccept {
    switch (_provider) {
      case ImportProvider.mal:
      case ImportProvider.shikimori:
        return '.xml,.json';
      case ImportProvider.letterboxd:
      case ImportProvider.goodreads:
      case ImportProvider.anixart:
        return '.csv';
      case ImportProvider.steam:
      case ImportProvider.anilist:
        return '.json';
      case ImportProvider.mangalib:
      case ImportProvider.custom:
        return '.json,.csv';
    }
  }

  String _getHelpText(I18nDictionary t) {
    switch (_provider) {
      case ImportProvider.anilist:
        return t.tr('importModal.helpAnilist');
      case ImportProvider.mangalib:
        return t.tr('importModal.helpMangalib');
      case ImportProvider.mal:
        return t.tr('importModal.helpMal');
      case ImportProvider.shikimori:
        return t.tr('importModal.helpShikimori');
      case ImportProvider.letterboxd:
        return t.tr('importModal.helpLetterboxd');
      case ImportProvider.goodreads:
        return t.tr('importModal.helpGoodreads');
      case ImportProvider.steam:
        return t.tr('importModal.helpSteam');
      case ImportProvider.anixart:
        return t.tr('importModal.helpAnixart');
      case ImportProvider.custom:
        return t.tr('importModal.helpCustom');
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

  void _toggleMangalibSite(int id) {
    setState(() {
      if (_mangalibSites.contains(id)) {
        if (_mangalibSites.length > 1) {
          _mangalibSites.remove(id);
        }
      } else {
        _mangalibSites.add(id);
      }
    });
  }

  void _toggleStatus(int id) {
    setState(() {
      if (_selectedStatuses.contains(id)) {
        if (_selectedStatuses.length > 1) {
          _selectedStatuses.remove(id);
        }
      } else {
        _selectedStatuses.add(id);
      }
    });
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
        // Section Header (space-y-6 = 24px)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  const SizedBox(height: 4), // mt-1 = 4
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
            if (widget.showCloseButton && widget.onClose != null) ...[
              const SizedBox(width: 8),
              TsundokuButton(
                variant: ButtonVariant.ghost,
                size: ButtonSize.sm,
                iconOnly: true,
                onPressed: widget.onClose,
                child: const Icon(LucideIcons.x, size: 18),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24), // space-y-6 = 24px

        // Success result banner
        if (_result != null) ...[
          _buildResultBanner(t, theme),
        ],

        if (_result == null) ...[
          // Block 1: Provider Selection Rail
          _buildProviderSelector(theme, t),
          const SizedBox(height: 24),

          // Block 2: Provider Specific Settings
          _buildProviderBody(t, theme),
          const SizedBox(height: 24),

          // Block 3: Common Options (Duplicates + Destination List)
          _buildCommonOptions(t, theme),
          const SizedBox(height: 24),

          // Error alert
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14), // p-3.5 = 14
              decoration: BoxDecoration(
                color: const Color(0x1AF43F5E), // rose-500/10
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x40F43F5E)), // rose-400/25
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    size: 16,
                    color: Color(0xFFFB7185), // rose-400
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFECDD3), // rose-200
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Block 4: Footer action button
          _buildSubmitButton(t, theme),
        ],
      ],
    );
  }

  Widget _buildResultBanner(I18nDictionary t, TsundokuTheme theme) {
    final res = _result!;

    return Container(
      padding: const EdgeInsets.all(24), // p-6 = 24
      decoration: BoxDecoration(
        color: const Color(0x1A10B981), // emerald-500/10
        borderRadius: BorderRadius.circular(12), // rounded-xl
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
                  color: Color(0x3334D399), // emerald-400/20
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.checkCircle2,
                  size: 24,
                  color: Color(0xFF6EE7B7), // emerald-300
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
                      color: Color(0xFFA7F3D0), // emerald-200
                    ),
                  ),
                  Text(
                    _provider.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xCC6EE7B7), // emerald-300/80
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20), // mt-5 = 20
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.total'),
                  value: '${res.totalFound}',
                  valueColor: const Color(0xFFF1F5F9),
                  bgColor: const Color(0x99181E2C), // card/60
                  borderColor: Colors.white.withAlpha(25), // white/10
                ),
              ),
              const SizedBox(width: 12), // gap-3 = 12
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.imported'),
                  value: '${res.importedCount}',
                  valueColor: const Color(0xFFA7F3D0), // emerald-200
                  bgColor: const Color(0x0D10B981), // emerald-400/5
                  borderColor: const Color(0x3334D399), // emerald-400/20
                ),
              ),
              const SizedBox(width: 12), // gap-3 = 12
              Expanded(
                child: _buildMetricCard(
                  label: t.tr('importModal.skipped'),
                  value: '${res.skippedDuplicates}',
                  valueColor: const Color(0xFFF1F5F9),
                  bgColor: const Color(0x99181E2C), // card/60
                  borderColor: Colors.white.withAlpha(25), // white/10
                ),
              ),
            ],
          ),
          if (res.skippedTitles != null && res.skippedTitles!.isNotEmpty) ...[
            const SizedBox(height: 12), // mt-3 = 12
            Container(
              padding: const EdgeInsets.all(12), // p-3 = 12
              decoration: BoxDecoration(
                color: const Color(0x66181E2C), // card/40
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(color: Colors.white.withAlpha(25)), // white/10
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _showSkippedTitles = !_showSkippedTitles),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.tf('importModal.skippedDuplicatesWithCount',
                              [res.skippedTitles!.length]),
                          style: TextStyle(fontSize: 12, color: theme.textMuted),
                        ),
                        Icon(
                          _showSkippedTitles
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 14,
                          color: theme.textMuted,
                        ),
                      ],
                    ),
                  ),
                  if (_showSkippedTitles) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.tf('importModal.duplicatesWithTitles',
                          [res.skippedTitles!.join(', ')]),
                      style: TextStyle(
                          fontSize: 12, color: theme.textMuted, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24), // mt-6 = 24
          Wrap(
            spacing: 12, // gap-3 = 12
            runSpacing: 12,
            children: [
              if (res.targetListId != null)
                TsundokuButton(
                  variant: ButtonVariant.primary,
                  size: ButtonSize.md,
                  onPressed: () =>
                      widget.onNavigateToList?.call(res.targetListId!),
                  child: Text(t.tr('importModal.openList')),
                ),
              TsundokuButton(
                variant: ButtonVariant.secondary,
                size: ButtonSize.lg,
                onPressed: _resetResult,
                child: Text(t.tr('importModal.importAnother')),
              ),
              if (widget.showCloseButton && widget.onClose != null)
                TsundokuButton(
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.lg,
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
      padding: const EdgeInsets.all(14), // p-3.5 = 14
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: valueColor), // text-xl = 20
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
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
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
            // Tailwind: sm: 640 (2 cols), lg: 1024 (4 cols)
            final screenWidth = MediaQuery.sizeOf(context).width;
            final cols = (screenWidth >= 1024 && constraints.maxWidth >= 720)
                ? 4
                : (screenWidth >= 640 && constraints.maxWidth >= 380)
                    ? 2
                    : (constraints.maxWidth >= 760
                        ? 4
                        : (constraints.maxWidth >= 380 ? 2 : 1));

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ImportProvider.values.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 70, // 40px icon + 24px vertical padding + borders
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
                    padding: const EdgeInsets.all(12), // p-3 = 12
                    decoration: BoxDecoration(
                      color: isSelected ? pTheme.surface : const Color(0xCC181E2C),
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                      border: Border.all(
                        color: isSelected ? pTheme.accent : Colors.white.withAlpha(25),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: pTheme.border.withAlpha(120),
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
                            borderRadius: BorderRadius.circular(8), // rounded-lg
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textMuted,
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
                label: t.tr('importModal.anilistProfileTab'),
                active: _anilistMode == 'profile',
                onTap: () => setState(() => _anilistMode = 'profile'),
                st: st,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabPill(
                label: t.tr('importModal.anilistFileTab'),
                active: _anilistMode == 'file',
                onTap: () => setState(() => _anilistMode = 'file'),
                st: st,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_anilistMode == 'profile') ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x80181E2C), // bg-card/50
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TsundokuTextField(
                    controller: _anilistUsernameController,
                    onSubmitted: (_) => _runImport(),
                    labelText: t.tr('importModal.anilistUsername'),
                    placeholder: t.tr('importModal.anilistUsernamePlaceholder'),
                  ),
                ),
                const SizedBox(width: 8),
                TsundokuButton(
                  variant: ButtonVariant.primary,
                  size: ButtonSize.md,
                  onPressed: _busy ? null : _runImport,
                  loading: _busy,
                  child: Text(t.tr('importModal.import')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getHelpText(t),
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
              height: 1.5,
            ),
          ),
        ] else ...[
          _buildFileDropArea(
            hint: t.tf('importModal.formats', [_fileAccept]),
            st: st,
          ),
          const SizedBox(height: 8),
          Text(
            _getHelpText(t),
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
              height: 1.5,
            ),
          ),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x80181E2C), // bg-card/50
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TsundokuTextField(
                  controller: _steamProfileController,
                  labelText: 'Steam ID или ссылка на профиль',
                  placeholder:
                      'https://steamcommunity.com/id/... or 76561198...',
                ),
                const SizedBox(height: 14),
                TsundokuTextField(
                  controller: _steamApiKeyController,
                  obscureText: true,
                  labelText: 'Steam Web API Key (опционально)',
                  placeholder: _steamKeyConfigured
                      ? 'Ключ уже сохранён на сервере'
                      : '••••••••••••••••••••••••••••••••',
                ),
                if (_steamKeyConfigured) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(LucideIcons.check,
                          size: 14, color: Color(0xFF6EE7B7)),
                      const SizedBox(width: 6),
                      Text(
                        t.tr('importModal.steamKeyConfigured'),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6EE7B7)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _buildCheckboxRow(
                  label: 'Сохранить ключ Steam в настройках',
                  value: _saveSteamKey,
                  accentColor: st.accent,
                  onChanged: (v) => setState(() => _saveSteamKey = v ?? false),
                ),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withAlpha(15), height: 1),
                const SizedBox(height: 10),
                _buildCheckboxRow(
                  label: 'Пропускать игры с временем < 2 часов',
                  value: _steamSkipShortSessions,
                  accentColor: st.accent,
                  onChanged: (v) =>
                      setState(() => _steamSkipShortSessions = v ?? true),
                ),
                _buildCheckboxRow(
                  label: 'Синхронизировать достижения',
                  value: _steamSyncAchievements,
                  accentColor: st.accent,
                  onChanged: (v) =>
                      setState(() => _steamSyncAchievements = v ?? true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getHelpText(t),
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
              height: 1.5,
            ),
          ),
        ] else ...[
          _buildFileDropArea(
            hint: t.tf('importModal.formats', [_fileAccept]),
            st: st,
          ),
          const SizedBox(height: 8),
          Text(
            _getHelpText(t),
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
              height: 1.5,
            ),
          ),
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

        // 1. Sites selection card
        Container(
          padding: const EdgeInsets.all(14), // p-3.5
          decoration: BoxDecoration(
            color: const Color(0x80181E2C), // bg-card/50
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        t.tr('importModal.socialLibSites').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    t.tf('importModal.selectedOf',
                        [_mangalibSites.length, _socialLibSites.length]),
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
                  final cols = constraints.maxWidth >= 540 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _socialLibSites.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent: 44,
                    ),
                    itemBuilder: (context, index) {
                      final site = _socialLibSites[index];
                      final isChecked = _mangalibSites.contains(site.id);

                      return InkWell(
                        onTap: () => _toggleMangalibSite(site.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isChecked
                                ? st.surface
                                : const Color(0x05FFFFFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isChecked
                                  ? st.border
                                  : const Color(0x14FFFFFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? st.accent.withAlpha(80)
                                      : Colors.black26,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isChecked
                                        ? st.accent
                                        : Colors.white24,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: isChecked
                                    ? Icon(LucideIcons.check,
                                        size: 12, color: st.text)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      site.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: isChecked
                                            ? st.text
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                    Text(
                                      site.tag,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.textMuted,
                                      ),
                                    ),
                                  ],
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
          ),
        ),
        const SizedBox(height: 12),

        // 2. Folders selection card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x80181E2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    t.tf('importModal.selectedOf', [
                      _selectedStatuses.length,
                      _folderOptions.length
                    ]),
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
                  final cols = constraints.maxWidth >= 540 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _folderOptions.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent: 40,
                    ),
                    itemBuilder: (context, index) {
                      final opt = _folderOptions[index];
                      final isChecked = _selectedStatuses.contains(opt.id);

                      return InkWell(
                        onTap: () => _toggleStatus(opt.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isChecked
                                ? st.surface
                                : const Color(0x05FFFFFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isChecked
                                  ? st.border
                                  : const Color(0x14FFFFFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? st.accent.withAlpha(80)
                                      : Colors.black26,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isChecked
                                        ? st.accent
                                        : Colors.white24,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: isChecked
                                    ? Icon(LucideIcons.check,
                                        size: 12, color: st.text)
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
                                    fontWeight: isChecked
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isChecked
                                        ? st.text
                                        : const Color(0xFF94A3B8),
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
          ),
        ),
        const SizedBox(height: 12),

        // 3. Tabs: Collector vs File
        TsundokuSegmentedControl<String>(
          value: _mangalibMode,
          options: [
            SegmentedOption(
              value: 'collector',
              label: t.tr('importModal.instantCollector'),
              icon: LucideIcons.sparkles,
            ),
            SegmentedOption(
              value: 'file',
              label: t.tr('importModal.fileJsonCsv'),
            ),
          ],
          onChanged: (val) => setState(() => _mangalibMode = val),
        ),
        const SizedBox(height: 12),

        if (_mangalibMode == 'collector') ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x80181E2C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mangalibAuth.connected) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x2610B981), // emerald-500/15
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0x6634D399)), // emerald-400/40
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check,
                            size: 12, color: Color(0xFF6EE7B7)),
                        const SizedBox(width: 6),
                        Text(
                          '${t.tr('importModal.mangalibAuth.connected')}${mangalibAuth.userId.isNotEmpty ? ' · ID: ${mangalibAuth.userId}' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6EE7B7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.tr('importModal.mangalibAuth.oneClickHint'),
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFCBD5E1),
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TsundokuTextField(
                        controller: _mangalibProfileController,
                        placeholder: mangalibAuth.userId.isNotEmpty
                            ? mangalibAuth.userId
                            : '123456 · https://mangalib.org/ru/users/123456',
                      ),
                    ),
                    const SizedBox(width: 8),
                    TsundokuButton(
                      variant: ButtonVariant.primary,
                      size: ButtonSize.md,
                      onPressed:
                          _mangalibDetectBusy ? null : _detectMangalibBrowser,
                      loading: _mangalibDetectBusy,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.sparkles, size: 14),
                          const SizedBox(width: 6),
                          Text(t.tr('importModal.mangalibAuth.detectButton')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          _buildFileDropArea(
            hint: t.tr('importModal.supportsMangaLibFiles'),
            st: st,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _getHelpText(t),
          style: TextStyle(
            fontSize: 12,
            color: theme.textMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFilePickerBody(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme(_provider.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: t.tr('importModal.fileLabel'),
          dotColor: st.accent,
        ),
        const SizedBox(height: 10),
        _buildFileDropArea(
          hint: t.tf('importModal.formats', [_fileAccept]),
          st: st,
        ),
        const SizedBox(height: 8),
        Text(
          _getHelpText(t),
          style: TextStyle(
            fontSize: 12,
            color: theme.textMuted,
            height: 1.5,
          ),
        ),
        if (_provider == ImportProvider.custom) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0x99181E2C), // bg-card/60
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _showTemplate = !_showTemplate),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14), // p-3.5
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.fileText,
                                size: 16, color: st.accent),
                            const SizedBox(width: 8),
                            Text(
                              _showTemplate
                                  ? t.tr('importModal.hideTemplate')
                                  : t.tr('importModal.showTemplate'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _showTemplate
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 16,
                          color: theme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showTemplate) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(50),
                      border: Border(
                          top: BorderSide(
                              color: Colors.white.withAlpha(20))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.tr('importModal.templateJsonLabel')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: theme.textMuted,
                              ),
                            ),
                            TsundokuButton(
                              variant: ButtonVariant.secondary,
                              size: ButtonSize.xs,
                              onPressed: () => _copyTemplate(_templateJson),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _templateCopied
                                        ? LucideIcons.check
                                        : LucideIcons.copy,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _templateCopied
                                        ? t.tr('importModal.templateCopied')
                                        : t.tr('importModal.copyTemplate'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(100),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withAlpha(25)),
                          ),
                          child: const SelectableText(
                            _templateJson,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF6EE7B7),
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.tr('importModal.templateCsvLabel')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: theme.textMuted,
                              ),
                            ),
                            TsundokuButton(
                              variant: ButtonVariant.secondary,
                              size: ButtonSize.xs,
                              onPressed: () => _copyTemplate(_templateCsv),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.copy, size: 12),
                                  const SizedBox(width: 4),
                                  Text(t.tr('importModal.copyTemplate')),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(100),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withAlpha(25)),
                          ),
                          child: const SelectableText(
                            _templateCsv,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF6EE7B7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFileDropArea({
    required String hint,
    required ImportSourceTheme st,
  }) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final hasFile = _file != null;

    final borderColor = _dragging
        ? st.accent
        : (hasFile
            ? const Color(0x6610B981) // emerald-500/40
            : Colors.white.withAlpha(38)); // white/15

    final bgColor = _dragging
        ? st.surface
        : (hasFile
            ? const Color(0x0D10B981) // emerald-500/5
            : const Color(0x99181E2C)); // card/60

    return PlatformDropZone(
      onHoverChanged: (hovering) {
        if (mounted && _dragging != hovering) {
          setState(() => _dragging = hovering);
        }
      },
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
          padding: const EdgeInsets.all(24), // p-6 = 24
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
          ),
          child: hasFile
              ? Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x3310B981), // emerald-500/20
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.fileText,
                        size: 24,
                        color: Color(0xFF34D399),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _file!.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(_file!.bytes.length / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TsundokuButton(
                      variant: ButtonVariant.secondary,
                      size: ButtonSize.sm,
                      onPressed: () {
                        setState(() {
                          _file = null;
                        });
                      },
                      child: Text(t.tr('importModal.changeFile')),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x14FFFFFF), // bg-field
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        LucideIcons.upload,
                        size: 20,
                        color: theme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.tr('importModal.dropFile'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textMuted,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCommonOptions(I18nDictionary t, TsundokuTheme theme) {
    final st = theme.sourceTheme(_provider.id);

    return Container(
      padding: const EdgeInsets.all(16), // p-4 = 16
      decoration: BoxDecoration(
        color: const Color(0x99181E2C), // bg-card/60
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.tr('importModal.optionsTitle').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: theme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxRow(
            label: t.tr('importModal.skipDuplicates'),
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
            Container(
              margin: const EdgeInsets.only(left: 24),
              padding: const EdgeInsets.only(left: 16, top: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                      color: Colors.white.withAlpha(25), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTabPill(
                        label: t.tr('importModal.newList'),
                        active: _listMode == 'new',
                        onTap: () => setState(() => _listMode = 'new'),
                        st: st,
                      ),
                      const SizedBox(width: 8),
                      _buildTabPill(
                        label: t.tr('importModal.existingList'),
                        active: _listMode == 'existing',
                        onTap: () => setState(() => _listMode = 'existing'),
                        st: st,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_listMode == 'new')
                    TsundokuTextField(
                      controller: _newListNameController,
                      labelText: 'Название нового списка',
                      placeholder: t.tf('importModal.defaultList', [_provider.label]),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _targetListId,
                      dropdownColor: const Color(0xFF1E2230),
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: t.tr('importModal.selectList'),
                        labelStyle: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: const Color(0x0AFFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0x1AFFFFFF)),
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
                      onChanged: (val) =>
                          setState(() => _targetListId = val),
                    ),
                ],
              ),
            ),
          ],

          // Folder selection chips for other sources
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
                Text(
                  t.tf('importModal.selectedOf', [
                    _selectedStatuses.length,
                    _folderOptions.length
                  ]),
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
                final cols = constraints.maxWidth >= 540 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _folderOptions.length,
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: 40,
                  ),
                  itemBuilder: (context, index) {
                    final opt = _folderOptions[index];
                    final isChecked = _selectedStatuses.contains(opt.id);

                    return InkWell(
                      onTap: () => _toggleStatus(opt.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? st.surface
                              : const Color(0x05FFFFFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isChecked
                                ? st.border
                                : const Color(0x14FFFFFF),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isChecked
                                    ? st.accent.withAlpha(80)
                                    : Colors.black26,
                                borderRadius:
                                    BorderRadius.circular(4),
                                border: Border.all(
                                  color: isChecked
                                      ? st.accent
                                      : Colors.white24,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: isChecked
                                  ? Icon(LucideIcons.check,
                                      size: 12, color: st.text)
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
                                  fontWeight: isChecked
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isChecked
                                      ? st.text
                                      : const Color(0xFF94A3B8),
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
        child: Text(_busy
            ? t.tr('importModal.importing')
            : t.tr('importModal.start')),
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required bool active,
    required VoidCallback onTap,
    ImportSourceTheme? st,
    IconData? icon,
  }) {
    final activeBg = st?.surface ?? const Color(0x266366F1);
    final activeBorder = st?.border ?? const Color(0x666366F1);
    final activeText = st?.text ?? Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8), // px-3.5 py-2
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeBg : const Color(0x99181E2C), // bg-card/60
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? activeBorder
                : Colors.white.withAlpha(25), // border-white/10
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: active
                      ? (st?.accent ?? Colors.white)
                      : const Color(0xFF94A3B8)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? activeText : const Color(0xFF94A3B8),
              ),
            ),
          ],
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
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
