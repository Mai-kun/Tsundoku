import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        // Inter — 1:1 с mediatracker-ui (--font-sans: Inter, ... в app.css).
        // Полная тема (ThemeExtension<TsundokuTheme> из tokens.css, тема
        // "obsidian") появится при портировании Фазы 0:
        // lib/shared/theme/tsundoku_theme.dart.
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF473BB8)),
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
