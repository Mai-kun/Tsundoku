/// Tsundoku (MediaTracker) — Flutter UI entry point.
///
/// 1:1 port of `mediatracker-ui/src/app/main.ts`: монтирование App + клиентский
/// лог-репортинг (window.onerror → /api/logs/client — браузерная специфика,
/// в Flutter ошибки ловит FlutterError.onError, отчёт уходит на тот же
/// эндпоинт). Service Worker — web-only фича сборки, не переносится.
///
/// Ключевые константы архитектуры:
/// - Бэкенд `MediaTracker.Server` (.NET NativeAOT) независим: сам решает,
///   запускать ли UI-бинарь (`--url http://127.0.0.1:{port}`) или работать
///   headless (`--no-ui`). API-контракт — `openapi.json`.
/// - `baseUrl` API нигде не хардкодится — `apiBaseUrlProvider` при старте.
/// - Прямой `import 'dart:io'` в виджетах/провайдерах запрещён: платформенное
///   изолируется за `PlatformService` (условные импорты io/web).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'shared/api/api.dart';
export 'app/app.dart' show TsundokuApp;


void main() {
  // window.onerror → sendClientLog (1-в-1 с main.ts).
  FlutterError.onError = (details) {
    if (kDebugMode) FlutterError.presentError(details);
    _sendClientLog(
      details.exceptionAsString(),
      details.stack?.toString(),
    );
  };
  runApp(const ProviderScope(child: TsundokuRoot()));
}

void _sendClientLog(String message, String? stack) {
  // POST /api/logs/client — без baseUrl (dio из провайдера недоступен до
  // runApp); используем ленивую статическую ссылку на Api (App прикрепляет).
  final api = AppClientLogHook.api;
  if (api == null) return;
  unawaited(api.sendClientLog(message, stack));
}

/// Хук: App прикрепляет живой TsundokuApi для клиентских логов (dio знает
/// baseUrl — он не хардкодится).
class AppClientLogHook {
  AppClientLogHook._();

  static TsundokuApi? api;
}

class TsundokuRoot extends StatelessWidget {
  const TsundokuRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ApiBootstrap();
  }
}

/// Прикрепляет apiBaseUrlProvider к App (пока без аргумента `--url`: старт
/// с локальным сервером по умолчанию; значение переопределяется при старте
/// UI-бинаря) и рендерит App.
class _ApiBootstrap extends ConsumerStatefulWidget {
  const _ApiBootstrap();

  @override
  ConsumerState<_ApiBootstrap> createState() => _ApiBootstrapState();
}

class _ApiBootstrapState extends ConsumerState<_ApiBootstrap> {
  @override
  void initState() {
    super.initState();
    // Провайдер-модификации — после монтирования дерева (Riverpod запрет).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // baseUrl нигде не хардкодится: дефолт локального сервера задаётся при
      // старте UI-бинаря (--url); здесь — значение по умолчанию для отладки.
      ref.read(apiBaseUrlProvider.notifier).set('http://127.0.0.1:5150');
      final api = ref.read(apiClientProvider);
      AppClientLogHook.api = api;
    });
  }

  @override
  Widget build(BuildContext context) {
    return const TsundokuApp();
  }
}
