/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte`.
///
/// Основной вид настроек:
/// - Левая боковая панель с навигацией по 10 вкладкам (источники, поиск, бэкап,
///   импорт, темп чтения, обновление, хранилище, внешний вид, десктоп, API-токены).
/// - Мобильный адаптивный режим с горизонтальной панелью вкладок (< 700px).
/// - Полная интеграция всех 10 вкладок без заглушек.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../features/settings/tabs/appearance_tab.dart';
import '../features/settings/tabs/api_tokens_tab.dart';
import '../features/settings/tabs/backup_tab.dart';
import '../features/settings/tabs/desktop_tab.dart';
import '../features/settings/tabs/import_tab.dart';
import '../features/settings/tabs/reading_tab.dart';
import '../features/settings/tabs/search_tab.dart';
import '../features/settings/tabs/sources_tab.dart';
import '../features/settings/tabs/storage_tab.dart';
import '../features/settings/tabs/update_tab.dart';
import '../shared/i18n/index.dart';
import '../shared/theme/tsundoku_tokens.dart';

enum SettingsTab {
  sources('sources'),
  search('search'),
  backup('backup'),
  importTab('import'),
  reading('reading'),
  update('update'),
  storage('storage'),
  appearance('appearance'),
  desktop('desktop'),
  apiTokens('apiTokens');

  final String wire;
  const SettingsTab(this.wire);

  static SettingsTab fromWire(String wire) {
    return SettingsTab.values.firstWhere(
      (t) => t.wire == wire,
      orElse: () => SettingsTab.sources,
    );
  }
}

class SettingsView extends ConsumerStatefulWidget {
  final SettingsTab initialTab;
  final VoidCallback? onImportCompleted;
  final ValueChanged<String>? onNavigateToList;
  final void Function(String sourceId, String? type)? onTestSearch;
  final Widget Function(
    BuildContext context,
    SettingsTab activeTab,
    VoidCallback onImportCompleted,
    ValueChanged<String>? onNavigateToList,
    void Function(String sourceId, String? type)? onTestSearch,
  )? panelBuilder;

  const SettingsView({
    super.key,
    this.initialTab = SettingsTab.sources,
    this.onImportCompleted,
    this.onNavigateToList,
    this.onTestSearch,
    this.panelBuilder,
  });

  @override
  ConsumerState<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends ConsumerState<SettingsView> {
  late SettingsTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  @override
  void didUpdateWidget(SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _activeTab = widget.initialTab;
    }
  }

  SettingsTab get activeTab => _activeTab;

  void setTab(SettingsTab tab) {
    setState(() => _activeTab = tab);
  }

  String _tabLabel(SettingsTab tab, I18nDictionary t) {
    switch (tab) {
      case SettingsTab.sources:
        return t.tr('settingsModal.tabs.sources');
      case SettingsTab.search:
        return t.tr('settingsModal.tabs.search');
      case SettingsTab.backup:
        return t.tr('settingsModal.tabs.backup');
      case SettingsTab.importTab:
        return t.tr('settingsModal.tabs.import');
      case SettingsTab.reading:
        return t.tr('settingsModal.tabs.reading');
      case SettingsTab.update:
        return t.tr('settingsModal.tabs.update');
      case SettingsTab.storage:
        return t.tr('settingsModal.tabs.storage');
      case SettingsTab.appearance:
        return t.tr('settingsModal.tabs.appearance');
      case SettingsTab.desktop:
        return t.tr('settingsModal.tabs.desktop');
      case SettingsTab.apiTokens:
        return t.tr('settingsModal.tabs.apiTokens');
    }
  }

  IconData _tabIcon(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.sources:
        return LucideIcons.server;
      case SettingsTab.search:
        return LucideIcons.search;
      case SettingsTab.backup:
        return LucideIcons.rotateCcw;
      case SettingsTab.importTab:
        return LucideIcons.folderInput;
      case SettingsTab.reading:
        return LucideIcons.bookOpen;
      case SettingsTab.update:
        return LucideIcons.refreshCw;
      case SettingsTab.storage:
        return LucideIcons.database;
      case SettingsTab.appearance:
        return LucideIcons.palette;
      case SettingsTab.desktop:
        return LucideIcons.appWindow;
      case SettingsTab.apiTokens:
        return LucideIcons.key;
    }
  }

  Widget _buildTabContent(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.sources:
        return SourcesTab(onTestSearch: widget.onTestSearch);
      case SettingsTab.search:
        return const SearchTab();
      case SettingsTab.backup:
        return const BackupTab();
      case SettingsTab.importTab:
        return ImportTab(
          onImportCompleted: widget.onImportCompleted,
          onNavigateToList: widget.onNavigateToList,
        );
      case SettingsTab.reading:
        return const ReadingTab();
      case SettingsTab.update:
        return const UpdateTab();
      case SettingsTab.storage:
        return const StorageTab();
      case SettingsTab.appearance:
        return const AppearanceTab();
      case SettingsTab.desktop:
        return const DesktopTab();
      case SettingsTab.apiTokens:
        return const ApiTokensTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final tokens = TsundokuTheme.of(context);

    if (widget.panelBuilder != null) {
      return widget.panelBuilder!(
        context,
        _activeTab,
        widget.onImportCompleted ?? () {},
        widget.onNavigateToList,
        widget.onTestSearch,
      );
    }

    final visibleTabs = SettingsTab.values
        .where((t) => t != SettingsTab.apiTokens || _activeTab == SettingsTab.apiTokens)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mobile horizontal tab rail
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: visibleTabs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = visibleTabs[index];
                    final isActive = tab == _activeTab;

                    return ChoiceChip(
                      selected: isActive,
                      avatar: Icon(
                        _tabIcon(tab),
                        size: 14,
                        color: isActive ? Colors.white : tokens.textMuted,
                      ),
                      label: Text(
                        _tabLabel(tab, t),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive ? Colors.white : tokens.textMuted,
                        ),
                      ),
                      selectedColor: tokens.accent,
                      backgroundColor: tokens.bgSurface,
                      side: BorderSide(
                        color: isActive ? tokens.accent : Colors.white.withAlpha(20),
                      ),
                      onSelected: (selected) {
                        if (selected) setTab(tab);
                      },
                    );
                  },
                ),
              ),

              const Divider(color: Color(0x14FFFFFF), height: 1),

              // Content area
              Expanded(
                child: Container(
                  color: const Color(0x66151A26), // bg-[#151a26]/40
                  child: _buildTabContent(_activeTab),
                ),
              ),
            ],
          );
        }

        // Desktop two-column layout (sidebar + content)
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left sidebar tab navigation
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                border: Border(
                  right: BorderSide(color: Colors.white.withAlpha(15)),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: ListView.separated(
                itemCount: visibleTabs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final tab = visibleTabs[index];
                  final isActive = tab == _activeTab;

                  return InkWell(
                    onTap: () => setTab(tab),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? tokens.accent.withAlpha(38) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive ? tokens.accent.withAlpha(76) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _tabIcon(tab),
                            size: 16,
                            color: isActive ? tokens.accentSoft : tokens.textMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _tabLabel(tab, t),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                color: isActive ? tokens.accentSoft : tokens.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Right content area
            Expanded(
              child: Container(
                color: const Color(0x66151A26), // bg-[#151a26]/40
                child: _buildTabContent(_activeTab),
              ),
            ),
          ],
        );
      },
    );
  }
}
