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
import 'package:tsundoku_flutter/shared/types/dtos.dart';

enum ImportProvider {
  anilist('anilist', 'AniList', LucideIcons.tv),
  mangalib('mangalib', 'MangaLib', LucideIcons.bookOpen),
  mal('mal', 'MyAnimeList', LucideIcons.film),
  shikimori('shikimori', 'Shikimori', LucideIcons.sparkles),
  letterboxd('letterboxd', 'Letterboxd', LucideIcons.clapperboard),
  goodreads('goodreads', 'Goodreads', LucideIcons.book),
  steam('steam', 'Steam', LucideIcons.gamepad2),
  anixart('anixart', 'Anixart', LucideIcons.play),
  custom('custom', 'CSV / JSON', LucideIcons.fileSpreadsheet);

  final String id;
  final String label;
  final IconData icon;

  const ImportProvider(this.id, this.label, this.icon);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        if (widget.showCloseButton) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x1A6366F1), // indigo-500/10
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x336366F1)), // indigo-500/20
                    ),
                    child: const Center(
                      child: Icon(
                        LucideIcons.folderInput,
                        size: 20,
                        color: Color(0xFF818CF8), // indigo-400
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('importModal.title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Перенесите данные из внешних сервисов или локальных файлов',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8), // slate-400
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (widget.onClose != null)
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    LucideIcons.x,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: widget.onClose,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // Success result banner
        if (_result != null) ...[
          _buildResultBanner(t),
          const SizedBox(height: 20),
        ],

        if (_result == null) ...[
          // Provider Selection Rail
          _buildProviderSelector(),
          const SizedBox(height: 20),

          // Provider Specific Settings
          _buildProviderBody(t),
          const SizedBox(height: 20),

          // Common Options (Duplicates + Destination List)
          _buildCommonOptions(t),
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
          _buildSubmitButton(t),
        ],
      ],
    );
  }

  Widget _buildResultBanner(I18nDictionary t) {
    final res = _result!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1A10B981), // emerald-500/10
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3310B981)), // emerald-500/20
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.checkCircle2,
                size: 20,
                color: Color(0xFF34D399), // emerald-400
              ),
              const SizedBox(width: 10),
              Text(
                t.tr('importModal.success'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA7F3D0), // emerald-200
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildMetricChip(
                label: 'Всего найдено',
                value: '${res.totalFound}',
                color: const Color(0xFF94A3B8),
              ),
              _buildMetricChip(
                label: 'Импортировано',
                value: '${res.importedCount}',
                color: const Color(0xFF34D399),
              ),
              _buildMetricChip(
                label: 'Пропущено дубликатов',
                value: '${res.skippedDuplicates}',
                color: const Color(0xFFFBBF24),
              ),
            ],
          ),
          if (res.targetListId != null) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: () => widget.onNavigateToList?.call(res.targetListId!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.externalLink,
                    size: 14,
                    color: Color(0xFF818CF8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Перейти к списку ${res.targetListName ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (res.skippedTitles != null && res.skippedTitles!.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showSkippedTitles = !_showSkippedTitles),
              child: Row(
                children: [
                  Icon(
                    _showSkippedTitles
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Показать пропущенные тайтлы (${res.skippedTitles!.length})',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            if (_showSkippedTitles)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  res.skippedTitles!.join(', '),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _resetResult,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0x3310B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Импортировать ещё', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ImportProvider.values.map((p) {
          final active = _provider == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _provider = p;
                  _file = null;
                  _error = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0x336366F1) // indigo-500/20
                      : const Color(0x0AFFFFFF), // white/[0.04]
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? const Color(0x666366F1) // indigo-500/40
                        : const Color(0x14FFFFFF), // white/[0.08]
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      p.icon,
                      size: 16,
                      color: active
                          ? const Color(0xFF818CF8)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        color: active ? Colors.white : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProviderBody(I18nDictionary t) {
    switch (_provider) {
      case ImportProvider.anilist:
        return _buildAniListBody(t);
      case ImportProvider.mangalib:
        return _buildMangaLibBody(t);
      case ImportProvider.steam:
        return _buildSteamBody(t);
      case ImportProvider.mal:
      case ImportProvider.shikimori:
      case ImportProvider.letterboxd:
      case ImportProvider.goodreads:
      case ImportProvider.anixart:
      case ImportProvider.custom:
        return _buildFilePickerBody(t);
    }
  }

  Widget _buildAniListBody(I18nDictionary t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildTabPill(
              label: t.tr('importModal.anilistProfileTab'),
              active: _anilistMode == 'profile',
              onTap: () => setState(() => _anilistMode = 'profile'),
            ),
            const SizedBox(width: 8),
            _buildTabPill(
              label: t.tr('importModal.anilistFileTab'),
              active: _anilistMode == 'file',
              onTap: () => setState(() => _anilistMode = 'file'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_anilistMode == 'profile') ...[
          TextField(
            controller: _anilistUsernameController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              labelText: t.tr('importModal.anilistUsername'),
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              hintText: 'Например, Mai-kun',
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
                borderSide: const BorderSide(color: Color(0x80818CF8)),
              ),
            ),
          ),
        ] else ...[
          _buildFileDropArea(hint: 'AniList JSON экспорт (.json)'),
        ],
      ],
    );
  }

  Widget _buildSteamBody(I18nDictionary t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildTabPill(
              label: 'Steam профиль',
              active: _steamMode == 'profile',
              onTap: () => setState(() => _steamMode = 'profile'),
            ),
            const SizedBox(width: 8),
            _buildTabPill(
              label: 'Файл',
              active: _steamMode == 'file',
              onTap: () => setState(() => _steamMode = 'file'),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
                borderSide: const BorderSide(color: Color(0x80818CF8)),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                borderSide: const BorderSide(color: Color(0x80818CF8)),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
          _buildFileDropArea(hint: 'Steam JSON/CSV экспорт'),
        ],
      ],
    );
  }

  Widget _buildMangaLibBody(I18nDictionary t) {
    final mangalibAuth = ref.watch(mangalibAuthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildTabPill(
              label: 'Быстрый импорт',
              active: _mangalibMode == 'collector',
              onTap: () => setState(() => _mangalibMode = 'collector'),
            ),
            const SizedBox(width: 8),
            _buildTabPill(
              label: 'Файл Tsundoku SocialLib',
              active: _mangalibMode == 'file',
              onTap: () => setState(() => _mangalibMode = 'file'),
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
                borderSide: const BorderSide(color: Color(0x80818CF8)),
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
          _buildFileDropArea(hint: 'tsundoku-sociallib.json'),
        ],
      ],
    );
  }

  Widget _buildFilePickerBody(I18nDictionary t) {
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
        _buildFileDropArea(hint: formatHint),
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

  Widget _buildFileDropArea({required String hint}) {
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
            color: const Color(0x05FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile
                  ? const Color(0x666366F1)
                  : const Color(0x1AFFFFFF),
              width: hasFile ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                hasFile ? LucideIcons.fileCheck : LucideIcons.upload,
                size: 28,
                color: hasFile ? const Color(0xFF818CF8) : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 10),
              Text(
                hasFile ? _file!.name : 'Нажмите или перетащите файл сюда',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasFile ? FontWeight.w600 : FontWeight.normal,
                  color: hasFile ? Colors.white : const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonOptions(I18nDictionary t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ПАРАМЕТРЫ ИМПОРТА',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        _buildCheckboxRow(
          label: 'Пропускать дубликаты (по названию и автору)',
          value: _skipDuplicates,
          onChanged: (v) => setState(() => _skipDuplicates = v ?? true),
        ),
        _buildCheckboxRow(
          label: t.tr('importModal.addToList'),
          value: _addToList,
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
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      label: 'Существующий список',
                      active: _listMode == 'existing',
                      onTap: () => setState(() => _listMode = 'existing'),
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
      ],
    );
  }

  Widget _buildSubmitButton(I18nDictionary t) {
    return ElevatedButton(
      onPressed: _busy ? null : _runImport,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4F46E5), // indigo-600
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x4D4F46E5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Начать импорт',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0x266366F1) // indigo-500/15
              : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? const Color(0x666366F1)
                : const Color(0x14FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxRow({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
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
                activeColor: const Color(0xFF6366F1),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
