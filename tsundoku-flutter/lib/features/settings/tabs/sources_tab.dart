/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "sources").
///
/// Вкладка «Источники»:
/// - Локальные офлайн-базы (Layer 0): переиндексация, режим автономии, список баз, тумблеры, удаление дампов.
/// - Настройки прокси: HTTP/SOCKS5, логин/пароль, мастер-тумблер, тест прокси, сохранение.
/// - Переключатель вида (Pill tabs): Официальные API | Веб-парсеры сайтов + фильтр типов медиа.
/// - Карточки источников: статус, привязка к прокси, тест связи, мастер-тумблер, ввод/сохранение ключей,
///   авторизация через сессию браузера (SocialLib / Simkl).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/api/offline_mode.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/dtos.dart';
import '../../../shared/types/models.dart';
import '../../../shared/ui/badge.dart';
import '../../../shared/ui/confirm_dialog.dart';
import '../../../shared/ui/popover_menu.dart';
import '../../../shared/ui/toast.dart';

class SourcesTab extends ConsumerStatefulWidget {
  final void Function(String sourceId, String? type)? onTestSearch;

  const SourcesTab({super.key, this.onTestSearch});

  @override
  ConsumerState<SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends ConsumerState<SourcesTab> {
  // Offline Databases State
  OfflineDatabasesSummaryDto? _offlineSummary;
  bool _offlineLoading = false;
  bool _offlineReindexing = false;
  bool _offlineModeToggling = false;
  String _offlineDbToggling = '';
  String _deletingDump = '';

  // Proxy Settings State
  ProxySettings? _proxySettings;
  bool _proxyEnabled = false;
  final TextEditingController _proxyUrlController = TextEditingController();
  final TextEditingController _proxyUsernameController = TextEditingController();
  final TextEditingController _proxyPasswordController = TextEditingController();
  bool _proxyPasswordDirty = false;
  bool _savingProxy = false;
  bool _testingProxy = false;
  ProxyTestResult? _proxyTestResult;
  String? _proxyLoadError;
  String _togglingProxySource = '';

  // Sources State
  List<SourceInfo> _sources = [];
  bool _sourcesLoading = false;
  String? _sourcesError;
  String _sourceKindFilter = 'api'; // 'api' | 'scraper'
  String _selectedTypeFilter = 'all'; // 'all' | 'anime' | 'manga' | ...
  String _togglingSource = '';
  String _testingSource = '';
  final Map<String, ConnectionTestResult> _testResults = {};
  String _savingKey = '';
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, bool> _showKeys = {};
  final Map<String, String> _keyErrors = {};
  final Map<String, String> _keySuccess = {};
  bool _detectingSocialLib = false;
  bool _showSocialLibManualToken = false;
  bool _detectingSimkl = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadOfflineDatabases(),
      _loadProxySettings(),
      _loadSources(),
    ]);
  }

  TextEditingController _getKeyController(String sourceId) {
    return _keyControllers.putIfAbsent(sourceId, () => TextEditingController());
  }

  void _toast({required String title, required String description, ToastType type = ToastType.info}) {
    ref.read(toastStoreProvider.notifier).show(
          ToastOptions(title: title, description: description, type: type),
        );
  }

  // ── Offline Databases ────────────────────────────────────────────────────────

  Future<void> _loadOfflineDatabases() async {
    if (!mounted) return;
    setState(() => _offlineLoading = true);
    try {
      final summary = await ref.read(apiClientProvider).getOfflineDatabases();
      if (mounted) {
        setState(() => _offlineSummary = summary);
      }
      await ref.read(offlineModeProvider.notifier).init();
    } catch (_) {
      // Ignore background init failure.
    } finally {
      if (mounted) {
        setState(() => _offlineLoading = false);
      }
    }
  }

  Future<void> _handleReindexOffline(I18nDictionary t) async {
    if (_offlineReindexing) return;
    setState(() => _offlineReindexing = true);
    try {
      await ref.read(apiClientProvider).reindexOfflineDatabases();
      _toast(
        title: t.tr('settingsModal.sources.offline.reindexToast'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
      await _loadOfflineDatabases();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _offlineReindexing = false);
      }
    }
  }

  Future<void> _handleToggleOfflineMode(I18nDictionary t) async {
    if (_offlineModeToggling) return;
    setState(() => _offlineModeToggling = true);
    final offlineState = ref.read(offlineModeProvider);
    try {
      await ref.read(offlineModeProvider.notifier).toggle(!offlineState.isOffline);
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _offlineModeToggling = false);
      }
    }
  }

  Future<void> _handleToggleOfflineDb(String fileName, bool enabled, I18nDictionary t) async {
    if (_offlineDbToggling.isNotEmpty) return;
    setState(() => _offlineDbToggling = fileName);
    try {
      await ref.read(apiClientProvider).toggleSourceEnabled('offline:$fileName', enabled);
      await _loadOfflineDatabases();
      await _loadSources();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _offlineDbToggling = '');
      }
    }
  }

  Future<void> _handleDeleteDump(OfflineDatabaseStatusDto db, I18nDictionary t) async {
    if (_deletingDump.isNotEmpty || db.sourceDumpFileName == null) return;
    final confirmed = await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-source-dump',
        title: t.tf('settingsModal.sources.offline.deleteDumpConfirm', [db.sourceDumpFileName!]),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    );
    if (!confirmed) return;

    setState(() => _deletingDump = db.fileName);
    try {
      await ref.read(apiClientProvider).deleteOfflineDatabaseDump(db.sourceDumpFileName!);
      _toast(
        title: t.tr('settingsModal.sources.offline.deleteDumpDone'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
      await _loadOfflineDatabases();
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _deletingDump = '');
      }
    }
  }

  // ── Proxy Settings ──────────────────────────────────────────────────────────

  Future<void> _loadProxySettings() async {
    try {
      _proxyLoadError = null;
      final settings = await ref.read(apiClientProvider).getProxySettings();
      if (!mounted) return;
      setState(() {
        _proxySettings = settings;
        _proxyEnabled = settings.enabled;
        _proxyUrlController.text = settings.proxyUrl;
        _proxyUsernameController.text = settings.username ?? '';
        _proxyPasswordController.clear;
        _proxyPasswordDirty = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _proxyLoadError = e.toString());
      }
    }
  }

  Future<void> _handleSaveProxy(I18nDictionary t) async {
    setState(() => _savingProxy = true);
    try {
      final res = await ref.read(apiClientProvider).saveProxySettings(
            SaveProxySettingsInput(
              enabled: _proxyEnabled,
              proxyUrl: _proxyUrlController.text.trim(),
              username: _proxyUsernameController.text.trim().isEmpty
                  ? null
                  : _proxyUsernameController.text.trim(),
              password: _proxyPasswordDirty ? _proxyPasswordController.text : null,
              proxiedSources: _proxySettings?.proxiedSources ?? const [],
            ),
          );
      if (mounted) {
        setState(() {
          _proxySettings = ProxySettings(
            enabled: res.enabled,
            proxyUrl: _proxyUrlController.text.trim(),
            username: _proxyUsernameController.text.trim().isEmpty
                ? null
                : _proxyUsernameController.text.trim(),
            hasPassword: res.hasPassword,
            maskedPassword: res.maskedPassword,
            proxiedSources: res.proxiedSources,
          );
          _proxyPasswordController.clear();
          _proxyPasswordDirty = false;
        });
      }
      await _loadSources();
      _toast(
        title: t.tr('settingsModal.sources.proxy.savedToast'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _savingProxy = false);
      }
    }
  }

  Future<void> _handleTestProxy(I18nDictionary t) async {
    setState(() {
      _testingProxy = true;
      _proxyTestResult = null;
    });
    try {
      final res = await ref.read(apiClientProvider).testProxy(
            proxyUrl: _proxyUrlController.text.trim(),
            username: _proxyUsernameController.text.trim().isEmpty
                ? null
                : _proxyUsernameController.text.trim(),
            password: _proxyPasswordDirty
                ? (_proxyPasswordController.text.isEmpty ? null : _proxyPasswordController.text)
                : null,
            useStoredPassword: !_proxyPasswordDirty && (_proxySettings?.hasPassword == true),
          );
      if (mounted) {
        setState(() => _proxyTestResult = res);
      }
      _toast(
        title: res.success
            ? t.tr('settingsModal.sources.proxy.testOk')
            : t.tr('settingsModal.sources.proxy.testFailed'),
        description: '${res.message}${res.success ? ' (${res.latencyMs} мс)' : ''}',
        type: res.success ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _testingProxy = false);
      }
    }
  }

  Future<void> _handleToggleSourceProxy(SourceInfo source, I18nDictionary t) async {
    setState(() => _togglingProxySource = source.id);
    try {
      final res = await ref.read(apiClientProvider).toggleSourceProxy(
            source.id,
            source.isProxied != true,
          );
      if (mounted) {
        setState(() {
          _sources = _sources.map((s) => s.id == source.id ? s.copyWith(isProxied: res.isProxied) : s).toList();
          if (_proxySettings != null) {
            _proxySettings = _proxySettings!.copyWith(proxiedSources: res.proxiedSources);
          }
        });
      }
      _toast(
        title: '${source.name}: ${t.tr('settingsModal.sources.proxy.perSourceToggle')} ${res.isProxied ? "ON" : "OFF"}',
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: e.toString(),
        description: t.tr('toast.actionFailed'),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _togglingProxySource = '');
      }
    }
  }

  // ── Sources List ────────────────────────────────────────────────────────────

  Future<void> _loadSources() async {
    setState(() {
      _sourcesLoading = true;
      _sourcesError = null;
    });
    try {
      final res = await ref.read(apiClientProvider).getSources();
      if (mounted) {
        setState(() => _sources = res);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sourcesError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _sourcesLoading = false);
      }
    }
  }

  Future<void> _handleToggleSource(SourceInfo source, I18nDictionary t) async {
    setState(() => _togglingSource = source.id);
    try {
      final nextState = !source.isEnabled;
      final res = await ref.read(apiClientProvider).toggleSourceEnabled(source.id, nextState);
      if (mounted) {
        setState(() {
          _sources = _sources.map((s) => s.id == source.id ? s.copyWith(isEnabled: res.isEnabled) : s).toList();
        });
      }
      _toast(
        title: res.isEnabled
            ? '${source.name}: ${t.tr('settingsModal.sources.enabledBadge')}'
            : '${source.name}: ${t.tr('settingsModal.sources.disabledBadge')}',
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _togglingSource = '');
      }
    }
  }

  Future<void> _handleTestSource(String sourceId, I18nDictionary t) async {
    setState(() => _testingSource = sourceId);
    try {
      final res = await ref.read(apiClientProvider).testSourceConnection(sourceId);
      if (mounted) {
        setState(() => _testResults[sourceId] = res);
      }
      if (!res.success) {
        _toast(
          title: res.message.isNotEmpty ? res.message : t.tr('settingsModal.sources.testFailed'),
          description: t.tr('toast.descRetry'),
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResults[sourceId] = ConnectionTestResult(
            success: false,
            latencyMs: 0,
            message: e.toString(),
          );
        });
      }
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _testingSource = '');
      }
    }
  }

  Future<void> _handleSaveKey(String sourceId, I18nDictionary t) async {
    final controller = _getKeyController(sourceId);
    final key = controller.text.trim();
    setState(() {
      _savingKey = sourceId;
      _keyErrors.remove(sourceId);
      _keySuccess.remove(sourceId);
    });

    try {
      final res = await ref.read(apiClientProvider).saveSourceKey(sourceId, key);
      if (mounted) {
        setState(() {
          _keySuccess[sourceId] = t.tr('settingsModal.sources.saved');
          _sources = _sources.map((s) {
            if (s.id == sourceId) {
              return s.copyWith(
                hasKey: res.hasKey,
                isConfigured: res.hasKey,
                maskedKey: res.maskedKey,
              );
            }
            return s;
          }).toList();
          controller.clear();
        });
      }
      _toast(
        title: t.tr('settingsModal.sources.saved'),
        description: t.tr('toast.descSaved'),
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _keyErrors[sourceId] = e.toString());
      }
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _savingKey = '');
      }
    }
  }

  Future<void> _handleDetectSocialLibSession(I18nDictionary t) async {
    setState(() => _detectingSocialLib = true);
    try {
      final res = await ref.read(apiClientProvider).detectMangalibBrowserSession();
      if (res != null && res.success) {
        _toast(
          title: 'Авторизация MangaLib успешно подхвачена из браузера',
          description: t.tr('toast.descSaved'),
          type: ToastType.success,
        );
        await _loadSources();
      } else {
        _toast(
          title: res?.message ?? 'Сессия не найдена в браузерах',
          description: 'Войдите на сайт lib.social в браузере и повторите попытку',
          type: ToastType.warning,
        );
      }
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _detectingSocialLib = false);
      }
    }
  }

  Future<void> _handleDetectSimklSession(I18nDictionary t) async {
    setState(() => _detectingSimkl = true);
    try {
      final res = await ref.read(apiClientProvider).detectSimklBrowserSession();
      if (res != null && res.success) {
        _toast(
          title: 'Авторизация Simkl успешно подхвачена из браузера',
          description: t.tr('toast.descSaved'),
          type: ToastType.success,
        );
        await _loadSources();
      } else {
        _toast(
          title: res?.message ?? 'Сессия Simkl не найдена в браузерах',
          description: 'Войдите на simkl.com в браузере и повторите попытку',
          type: ToastType.warning,
        );
      }
    } catch (e) {
      _toast(
        title: t.tr('toast.actionFailed'),
        description: e.toString(),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _detectingSimkl = false);
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  static String _getOfflineDbIcon(String type, String name) {
    final lower = '$type $name'.toLowerCase();
    if (lower.contains('manga') || lower.contains('comic') || lower.contains('ranobe')) return '📚';
    if (lower.contains('anime')) return '🎬';
    if (lower.contains('game')) return '🎮';
    if (lower.contains('book')) return '📖';
    return '🗄️';
  }

  static ({Color accent, Color border}) _sourceTheme(String sourceId, TsundokuTheme theme) {
    return switch (sourceId) {
      'tmdb' => (accent: const Color(0xFF01D277), border: const Color(0x3301D277)),
      'imdb' => (accent: const Color(0xFFF5C518), border: const Color(0x33F5C518)),
      'rawg' => (accent: const Color(0xFFFFFFFF), border: const Color(0x26FFFFFF)),
      'simkl' => (accent: const Color(0xFF00E676), border: const Color(0x3300E676)),
      'kinopoisk' => (accent: const Color(0xFFFF6600), border: const Color(0x33FF6600)),
      'anilist' => (accent: const Color(0xFF02A9FF), border: const Color(0x3302A9FF)),
      'mal' => (accent: const Color(0xFF2E51A2), border: const Color(0x332E51A2)),
      'shikimori' => (accent: const Color(0xFFD32F2F), border: const Color(0x33D32F2F)),
      'googlebooks' => (accent: const Color(0xFF4285F4), border: const Color(0x334285F4)),
      'openlibrary' => (accent: const Color(0xFFE1D9D1), border: const Color(0x26E1D9D1)),
      'sociallib' => (accent: const Color(0xFFE50914), border: const Color(0x33E50914)),
      _ => (accent: theme.accent, border: theme.borderSubtle),
    };
  }

  static String _categoryLabel(String key, I18nDictionary t) {
    return switch (key) {
      'anime' => t.tr('navigation.anime'),
      'manga' => t.tr('types.manga'),
      'movie' => t.tr('types.movie'),
      'tvshow' => t.tr('types.tvshow'),
      'game' => t.tr('types.game'),
      'book' => t.tr('types.book'),
      _ => key,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);
    final offlineState = ref.watch(offlineModeProvider);
    final proxyReady = _proxyUrlController.text.trim().isNotEmpty;

    final filteredSources = _sources.where((s) {
      if (_sourceKindFilter == 'api' && s.isScraper) return false;
      if (_sourceKindFilter == 'scraper' && !s.isScraper) return false;
      if (_selectedTypeFilter != 'all' && !s.mediaTypes.contains(_selectedTypeFilter)) {
        return false;
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Local Offline Databases (Layer 0) ──────────────────────────
          _buildOfflineDatabasesBlock(t, theme, offlineState),
          const SizedBox(height: 24),

          // ── 2. Network & Proxy Block ──────────────────────────────────────
          _buildProxyBlock(t, theme, proxyReady),
          const SizedBox(height: 24),

          // ── 3. Sources Section Header & Controls ──────────────────────────
          _buildSourcesHeader(t, theme),
          const SizedBox(height: 16),

          // ── 4. Sources List ───────────────────────────────────────────────
          _buildSourcesList(t, theme, filteredSources, proxyReady),
        ],
      ),
    );
  }

  // ── Block Builders ──────────────────────────────────────────────────────────

  Widget _buildOfflineDatabasesBlock(
    I18nDictionary t,
    TsundokuTheme theme,
    OfflineModeState offlineState,
  ) {
    final totalTitles = _offlineSummary?.totalIndexedTitles ?? 0;
    final pendingDumps = _offlineSummary?.pendingDumps ?? const [];
    final databases = _offlineSummary?.databases ?? const [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x406366F1)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x661E1B4B),
            Color(0xB3151A26),
            Color(0xE610141D),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final headerInfo = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x336366F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x4D6366F1)),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.server, size: 20, color: Color(0xFF818CF8)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              t.tr('settingsModal.sources.offline.title'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (totalTitles > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0x266366F1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0x4D6366F1)),
                                ),
                                child: Text(
                                  '$totalTitles тайтлов',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFA5B4FC)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.tr('settingsModal.sources.offline.subtitle'),
                          style: TextStyle(fontSize: 12, color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final reindexButton = OutlinedButton.icon(
                onPressed: _offlineReindexing ? null : () => _handleReindexOffline(t),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0x266366F1),
                  side: const BorderSide(color: Color(0x4D6366F1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: _offlineReindexing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFA5B4FC)),
                label: Text(
                  t.tr('settingsModal.sources.offline.reindexBtn'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC7D2FE)),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerInfo,
                    const SizedBox(height: 12),
                    reindexButton,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: headerInfo),
                  const SizedBox(width: 12),
                  reindexButton,
                ],
              );
            },
          ),

          // Offline Autonomy Mode Toggle (if databases exist)
          if (offlineState.hasDatabases) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x0FD97706),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33F59E0B)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t.tr('settingsModal.sources.offline.offlineModeTitle'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (offlineState.isOffline) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0x26F59E0B),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x4DF59E0B)),
                                ),
                                child: Text(
                                  t.tr('settingsModal.sources.offline.offlineModeActive'),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.tr('settingsModal.sources.offline.offlineModeDesc'),
                          style: TextStyle(fontSize: 11, color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildSwitch(
                    value: offlineState.isOffline,
                    activeColor: const Color(0xFFD97706),
                    disabled: _offlineModeToggling,
                    onChanged: (_) => _handleToggleOfflineMode(t),
                  ),
                ],
              ),
            ),
          ],

          // Raw Dumps Warning Banner
          if (pendingDumps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1AF59E0B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4DF59E0B)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 16, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.tf('settingsModal.sources.offline.pendingDumpsWarning', [pendingDumps.join(', ')]),
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFDE68A)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Databases Grid
          const SizedBox(height: 16),
          if (_offlineLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (databases.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 700;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isWide ? 3 : 1,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 108,
                  ),
                  itemCount: databases.length,
                  itemBuilder: (context, index) {
                    final db = databases[index];
                    return _buildDatabaseCard(db, t, theme);
                  },
                );
              },
            ),

          // Bottom Directory Hint
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.folderOpen, size: 13, color: theme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.tr('settingsModal.sources.offline.hint'),
                    style: TextStyle(fontSize: 11, color: theme.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseCard(OfflineDatabaseStatusDto db, I18nDictionary t, TsundokuTheme theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(_getOfflineDbIcon(db.type, db.name), style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        db.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSwitch(
                value: db.isActive,
                activeColor: const Color(0xFF059669),
                disabled: _offlineDbToggling == db.fileName,
                onChanged: (val) => _handleToggleOfflineDb(db.fileName, val, t),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '${db.totalTitles} тайтлов',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text('•', style: TextStyle(fontSize: 11, color: theme.textMuted)),
              const SizedBox(width: 6),
              Text(_formatBytes(db.fileSizeBytes), style: TextStyle(fontSize: 11, color: theme.textMuted)),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    db.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: theme.textMuted),
                  ),
                ),
                if (_deletingDump == db.fileName)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (db.sourceDumpFileName != null)
                  InkWell(
                    onTap: () => _handleDeleteDump(db, t),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x1AF43F5E),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x4DF43F5E)),
                      ),
                      child: Text(
                        t.tr('settingsModal.sources.offline.deleteDumpBtn'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFFDA4AF)),
                      ),
                    ),
                  )
                else if (db.isActive && widget.onTestSearch != null)
                  InkWell(
                    onTap: () => widget.onTestSearch!('offline:${db.fileName}', db.type),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x266366F1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x4D6366F1)),
                      ),
                      child: Text(
                        '🔍 ${t.tr('settingsModal.sources.offline.testSearchBtn')}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFC7D2FE)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyBlock(I18nDictionary t, TsundokuTheme theme, bool proxyReady) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x400284C7)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x66082F49),
            Color(0xB3151A26),
            Color(0xE610141D),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x330284C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x4D0284C7)),
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.globe, size: 20, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          t.tr('settingsModal.sources.proxy.title'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (_proxySettings?.enabled == true && proxyReady)
                          const TsundokuBadge(tone: BadgeTone.success, size: BadgeSize.sm, child: Text('Прокси включен')),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.tr('settingsModal.sources.proxy.description'),
                      style: TextStyle(fontSize: 12, color: theme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildSwitch(
                value: _proxyEnabled,
                activeColor: const Color(0xFF0284C7),
                onChanged: (val) => setState(() => _proxyEnabled = val),
              ),
            ],
          ),
          if (_proxyLoadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_proxyLoadError!, style: const TextStyle(color: Color(0xFFFDA4AF), fontSize: 12)),
            )
          else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _proxyUrlController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                labelText: t.tr('settingsModal.sources.proxy.urlLabel'),
                hintText: t.tr('settingsModal.sources.proxy.urlPlaceholder'),
                isDense: true,
                filled: true,
                fillColor: const Color(0x0FFFFFFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _proxyUsernameController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: t.tr('settingsModal.sources.proxy.usernameLabel'),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0x0FFFFFFF),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _proxyPasswordController,
                    obscureText: true,
                    onChanged: (_) => _proxyPasswordDirty = true,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: t.tr('settingsModal.sources.proxy.passwordLabel'),
                      hintText: t.tr('settingsModal.sources.proxy.passwordPlaceholder'),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0x0FFFFFFF),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            if (_proxySettings?.hasPassword == true && !_proxyPasswordDirty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.tr('settingsModal.sources.proxy.passwordStoredHint'),
                  style: TextStyle(fontSize: 10, color: theme.textMuted),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _testingProxy || !proxyReady ? null : () => _handleTestProxy(t),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: _testingProxy
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 13),
                  label: Text(
                    _testingProxy
                        ? t.tr('settingsModal.sources.proxy.testing')
                        : t.tr('settingsModal.sources.proxy.testButton'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _savingProxy ? null : () => _handleSaveProxy(t),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(LucideIcons.check, size: 13),
                  label: Text(
                    _savingProxy
                        ? t.tr('settingsModal.sources.proxy.saving')
                        : t.tr('settingsModal.sources.proxy.saveButton'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_proxyTestResult != null)
                  TsundokuBadge(
                    tone: _proxyTestResult!.success ? BadgeTone.success : BadgeTone.danger,
                    size: BadgeSize.sm,
                    child: Text(
                      _proxyTestResult!.success
                          ? '${_proxyTestResult!.message} · ${_proxyTestResult!.latencyMs} мс'
                          : _proxyTestResult!.message,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourcesHeader(I18nDictionary t, TsundokuTheme theme) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tr('settingsModal.sources.title'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              t.tr('settingsModal.sources.description'),
              style: TextStyle(fontSize: 12, color: theme.textMuted),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Pill Switcher: API vs Scrapers
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0x0FFFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPillButton(
                    label: t.tr('settingsModal.sources.kindApi'),
                    icon: LucideIcons.zap,
                    selected: _sourceKindFilter == 'api',
                    onTap: () => setState(() => _sourceKindFilter = 'api'),
                  ),
                  _buildPillButton(
                    label: t.tr('settingsModal.sources.kindScrapers'),
                    icon: LucideIcons.globe,
                    selected: _sourceKindFilter == 'scraper',
                    onTap: () => setState(() => _sourceKindFilter = 'scraper'),
                  ),
                ],
              ),
            ),
            // Media Type Filter
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${t.tr('settingsModal.sources.filterLabel')}:',
                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                ),
                const SizedBox(width: 6),
                TsundokuSelect<String>(
                  id: 'source-type-filter',
                  width: 160,
                  height: 36,
                  value: _selectedTypeFilter,
                  options: [
                    PopoverOption(value: 'all', label: t.tr('settingsModal.sources.filterAll')),
                    PopoverOption(value: 'anime', label: t.tr('navigation.anime')),
                    PopoverOption(value: 'manga', label: t.tr('types.manga')),
                    PopoverOption(value: 'movie', label: t.tr('types.movie')),
                    PopoverOption(value: 'tvshow', label: t.tr('types.tvshow')),
                    PopoverOption(value: 'game', label: t.tr('types.game')),
                    PopoverOption(value: 'book', label: t.tr('types.book')),
                  ],
                  onChange: (val) {
                    setState(() => _selectedTypeFilter = val);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPillButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x336366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? const Color(0xFFA5B4FC) : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFFA5B4FC) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesList(
    I18nDictionary t,
    TsundokuTheme theme,
    List<SourceInfo> filteredSources,
    bool proxyReady,
  ) {
    if (_sourcesLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_sourcesError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x1AF43F5E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_sourcesError!, style: const TextStyle(color: Color(0xFFFDA4AF), fontSize: 13)),
      );
    }

    if (filteredSources.isEmpty && _sourceKindFilter == 'scraper') {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0x268B5CF6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(LucideIcons.globe, size: 24, color: Color(0xFFC4B5FD)),
            ),
            const SizedBox(height: 12),
            Text(
              t.tr('settingsModal.sources.scraperEmptyTitle'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('settingsModal.sources.scraperEmptyText'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredSources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final source = filteredSources[index];
        return _buildSourceCard(source, t, theme, proxyReady);
      },
    );
  }

  Widget _buildSourceCard(
    SourceInfo source,
    I18nDictionary t,
    TsundokuTheme theme,
    bool proxyReady,
  ) {
    final sTheme = _sourceTheme(source.id, theme);
    final isToggling = _togglingSource == source.id;
    final isTesting = _testingSource == source.id;
    final testRes = _testResults[source.id];
    final isProxied = source.isProxied == true;
    final togglingProxy = _togglingProxySource == source.id;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Info & Controls
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Indicator dot & Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: sTheme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          source.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (!source.isEnabled)
                          TsundokuBadge(size: BadgeSize.sm, child: Text(t.tr('settingsModal.sources.disabledBadge')))
                        else if (source.isScraper)
                          TsundokuBadge(
                            tone: BadgeTone.info,
                            size: BadgeSize.sm,
                            child: Text(t.tr('settingsModal.sources.scraperBadge')),
                          )
                        else if (source.id == 'sociallib')
                          const TsundokuBadge(
                            tone: BadgeTone.info,
                            size: BadgeSize.sm,
                            child: Text('Опциональный токен (18+ / закладки)'),
                          )
                        else if (source.optionalApiKey && !source.requiresApiKey)
                          TsundokuBadge(
                            tone: BadgeTone.info,
                            size: BadgeSize.sm,
                            child: Text(t.tr('settingsModal.sources.optionalKey')),
                          )
                        else if (source.requiresApiKey)
                          TsundokuBadge(
                            tone: source.hasKey ? BadgeTone.success : BadgeTone.warning,
                            size: BadgeSize.sm,
                            child: Text(
                              source.hasKey
                                  ? t.tr('settingsModal.sources.keyConfigured')
                                  : t.tr('settingsModal.sources.keyRequired'),
                            ),
                          )
                        else
                          TsundokuBadge(
                            tone: BadgeTone.info,
                            size: BadgeSize.sm,
                            child: Text(t.tr('settingsModal.sources.noKeyRequired')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.description,
                      style: TextStyle(fontSize: 12, color: theme.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: source.mediaTypes.map((mt) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x0FFFFFFF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _categoryLabel(mt, t),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: theme.textMuted),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Right: Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Proxy toggle button
                  OutlinedButton.icon(
                    onPressed: !proxyReady || togglingProxy ? null : () => _handleToggleSourceProxy(source, t),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isProxied ? const Color(0x26059669) : Colors.transparent,
                      side: BorderSide(color: isProxied ? const Color(0x4D059669) : const Color(0x1AFFFFFF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: togglingProxy
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(LucideIcons.globe, size: 12, color: isProxied ? const Color(0xFF6EE7B7) : theme.textMuted),
                    label: Text(
                      t.tr('settingsModal.sources.proxy.perSourceToggle'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isProxied ? const Color(0xFF6EE7B7) : theme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Test Connection button
                  OutlinedButton.icon(
                    onPressed: isTesting ? null : () => _handleTestSource(source.id, t),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: isTesting
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.refreshCw, size: 12),
                    label: Text(
                      isTesting ? t.tr('settingsModal.sources.testing') : t.tr('settingsModal.sources.testConnection'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Master toggle switch
                  _buildSwitch(
                    value: source.isEnabled,
                    activeColor: const Color(0xFF6366F1),
                    disabled: isToggling,
                    onChanged: (_) => _handleToggleSource(source, t),
                  ),
                ],
              ),
            ],
          ),

          // Connection Test Result Pill
          if (testRes != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (testRes.success)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x26059669),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check, size: 12, color: Color(0xFF34D399)),
                        const SizedBox(width: 4),
                        Text(
                          t.tf('settingsModal.sources.testSuccess', [testRes.latencyMs]),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF34D399)),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x26F43F5E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.circleAlert, size: 12, color: Color(0xFFFB7185)),
                        const SizedBox(width: 4),
                        Text(
                          testRes.message.isNotEmpty ? testRes.message : t.tr('settingsModal.sources.testFailed'),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFFB7185)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          // Key Management Section
          if (source.requiresApiKey || source.optionalApiKey) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
              ),
              child: _buildKeyForm(source, t, theme),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyForm(SourceInfo source, I18nDictionary t, TsundokuTheme theme) {
    if (source.id == 'sociallib') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source.hasKey && source.maskedKey != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.check, size: 12, color: Color(0xFF34D399)),
                  const SizedBox(width: 6),
                  const Text('Сессия активна: ', style: TextStyle(fontSize: 12, color: Color(0xFF34D399))),
                  Text(source.maskedKey!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Ключ не требуется для поиска. Авторизация нужна только для каталога 18+ и личных закладок.',
                style: TextStyle(fontSize: 12, color: theme.textMuted),
              ),
            ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _detectingSocialLib ? null : () => _handleDetectSocialLibSession(t),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: _detectingSocialLib
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.refreshCw, size: 13),
                label: const Text('Подхватить сессию из браузера', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() => _showSocialLibManualToken = !_showSocialLibManualToken),
                icon: const Icon(LucideIcons.key, size: 13),
                label: const Text('Ввести токен вручную', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_showSocialLibManualToken) ...[
            const SizedBox(height: 8),
            _buildStandardKeyInput(source, t, theme, 'Bearer-токен (accessToken с lib.social)'),
          ],
        ],
      );
    }

    if (source.id == 'simkl') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _detectingSimkl ? null : () => _handleDetectSimklSession(t),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: _detectingSimkl
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.refreshCw, size: 13),
                label: const Text('Подхватить сессию из браузера', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStandardKeyInput(source, t, theme, 'Client ID simkl.com'),
        ],
      );
    }

    return _buildStandardKeyInput(source, t, theme, null);
  }

  Widget _buildStandardKeyInput(
    SourceInfo source,
    I18nDictionary t,
    TsundokuTheme theme,
    String? customPlaceholder,
  ) {
    final controller = _getKeyController(source.id);
    final isSaving = _savingKey == source.id;
    final showKey = _showKeys[source.id] ?? false;
    final successMsg = _keySuccess[source.id];
    final errorMsg = _keyErrors[source.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source.maskedKey != null) ...[
          Row(
            children: [
              Text('${t.tr('settingsModal.sources.currentKey')}: ', style: TextStyle(fontSize: 11, color: theme.textMuted)),
              Text(source.maskedKey!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white)),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: controller,
                  obscureText: !showKey,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: customPlaceholder ??
                        (source.hasKey
                            ? t.tr('settingsModal.sources.replaceKeyPlaceholder')
                            : t.tr('settingsModal.sources.inputPlaceholder')),
                    hintStyle: TextStyle(fontSize: 12, color: theme.textMuted),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0x0FFFFFFF),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: Icon(showKey ? LucideIcons.eyeOff : LucideIcons.eye, size: 14),
                      onPressed: () => setState(() => _showKeys[source.id] = !showKey),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: isSaving ? null : () => _handleSaveKey(source.id, t),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0x266366F1),
                foregroundColor: const Color(0xFFC7D2FE),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: isSaving
                  ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.shieldCheck, size: 13),
              label: Text(
                isSaving ? t.tr('common.saving') : t.tr('settingsModal.sources.saveKey'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (successMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(successMsg, style: const TextStyle(fontSize: 11, color: Color(0xFF34D399))),
          ),
        if (errorMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(errorMsg, style: const TextStyle(fontSize: 11, color: Color(0xFFFDA4AF))),
          ),
      ],
    );
  }

  Widget _buildSwitch({
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : () => onChanged(!value),
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 24,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: value ? activeColor : const Color(0x1AFFFFFF),
            border: Border.all(
              color: value ? activeColor.withAlpha(200) : const Color(0x1AFFFFFF),
            ),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : const Color(0xFF94A3B8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
