import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'shared/theme/tsundoku_theme.dart';
import 'shared/theme/tsundoku_tokens.dart';

/// Tsundoku (MediaTracker) — Flutter UI entry point.
///
/// Этап 0: пустой каркас. План миграции и правила — см. `FLUTTER_MIGRATION.md`
/// в корне worktree. Ключевые константы архитектуры:
/// - Бэкенд `MediaTracker.Server` (.NET NativeAOT) независим: сам решает,
///   запускать ли UI-бинарь (`--url http://127.0.0.1:{port}`) или работать
///   headless (`--no-ui`). API-контракт — `openapi.json`.
/// - `baseUrl` API нигде не хардкодится.
/// - Прямой `import 'dart:io'` в виджетах/провайдерах запрещён: платформенное
///   изолируется за `PlatformService` (условные импорты io/web).
void main() {
  runApp(const ProviderScope(child: TsundokuApp()));
}

class TsundokuApp extends StatelessWidget {
  const TsundokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tsundoku',
      debugShowCheckedModeBanner: false,
      theme: buildTsundokuTheme(
        // Пока тема одна (obsidian); смена тем — через провайдер uiSettings
        // при портировании Фаз 1+.
        tokens: TsundokuTheme.obsidian,
      ),
      home: const ScaffoldPlaceholder(),
    );
  }
}

/// Заглушка каркаса (Этап 0); в Фазе 3 заменяется на AppShell.
class ScaffoldPlaceholder extends StatelessWidget {
  const ScaffoldPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Tsundoku — Flutter scaffold (Этап 0)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
