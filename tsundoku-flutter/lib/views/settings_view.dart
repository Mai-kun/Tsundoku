import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

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
                  itemCount: SettingsTab.values.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = SettingsTab.values[index];
                    final isActive = tab == _activeTab;
                    return InkWell(
                      onTap: () => setTab(tab),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? tokens.accent.withAlpha(38)
                              : tokens.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive
                                ? tokens.accent.withAlpha(76)
                                : Colors.white.withAlpha(15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _tabIcon(tab),
                              size: 15,
                              color: isActive
                                  ? tokens.accentSoft
                                  : tokens.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _tabLabel(tab, t),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? tokens.accentSoft
                                    : tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildSectionContent(_activeTab, t, tokens),
                ),
              ),
            ],
          );
        }

        // Desktop 2-column layout matching Svelte embedded mode
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left sidebar navigation (w-64)
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
                itemCount: SettingsTab.values.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final tab = SettingsTab.values[index];
                  final isActive = tab == _activeTab;

                  return InkWell(
                    onTap: () => setTab(tab),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? tokens.accent.withAlpha(38)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? tokens.accent.withAlpha(76)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _tabIcon(tab),
                            size: 16,
                            color: isActive
                                ? tokens.accentSoft
                                : tokens.textMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _tabLabel(tab, t),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isActive
                                    ? tokens.accentSoft
                                    : tokens.textMuted,
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
                color: tokens.bgCanvas,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: _buildSectionContent(_activeTab, t, tokens),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionContent(
    SettingsTab tab,
    I18nDictionary t,
    TsundokuTheme tokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accent.withAlpha(38),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.accent.withAlpha(76)),
              ),
              child: Icon(_tabIcon(tab), size: 20, color: tokens.accentSoft),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tabLabel(tab, t),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.tr('settingsModal.title'),
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: tokens.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Text(
            '${_tabLabel(tab, t)}: секция настроек',
            style: TextStyle(fontSize: 14, color: tokens.textMuted),
          ),
        ),
      ],
    );
  }
}
