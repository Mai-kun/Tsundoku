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
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'shared/api/api.dart';
import 'shared/platform/dev_tools.dart';
import 'shared/platform/platform.dart';
import 'shared/ui/tsundoku_scroll.dart';
import 'shared/utils/ui_settings.dart';

export 'app/app.dart' show TsundokuApp;
export 'shared/platform/dev_tools.dart' show buildDebugAgentationOverlay;

/// Извлекает базовый URL API из CLI-аргументов или окружения.
///
/// - `--url <value>` или `--url=<value>`: приоритетное значение;
/// - Web (`kIsWeb`): `Uri.base.origin`;
/// - Desktop fallback: `http://127.0.0.1:5000` (стандартный порт бэкенда).
String parseBaseUrl(List<String> args) {
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--url=')) {
      final val = arg.substring('--url='.length).trim();
      if (val.isNotEmpty) return val;
    } else if (arg == '--url' && i + 1 < args.length) {
      final val = args[i + 1].trim();
      if (val.isNotEmpty) return val;
    }
  }

  if (kIsWeb) {
    try {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null') {
        return origin;
      }
    } catch (_) {}
  }

  return 'http://127.0.0.1:5000';
}

Future<void> main(List<String> args) async {
  if (!kDebugMode) {
    SmoothWheelBinding.ensureInitialized(scale: kTsundokuWheelScale);
  } else {
    ensureAppBindingInitialized();
  }
  await platformService.initWindow();

  final initialUrl = parseBaseUrl(args);
  final prefs = await SharedPreferences.getInstance();

  // window.onerror → sendClientLog (1-в-1 с main.ts).
  FlutterError.onError = (details) {
    if (kDebugMode) FlutterError.presentError(details);
    _sendClientLog(
      details.exceptionAsString(),
      details.stack?.toString(),
    );
  };

  runApp(ProviderScope(
    overrides: [
      apiBaseUrlProvider.overrideWith(() => ApiBaseUrlController(initialUrl)),
      uiSettingsProvider.overrideWith(() => UiSettingsController(prefs)),
    ],
    child: TsundokuRoot(initialBaseUrl: initialUrl),
  ));
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
  final String initialBaseUrl;

  const TsundokuRoot({super.key, this.initialBaseUrl = 'http://127.0.0.1:5000'});

  @override
  Widget build(BuildContext context) {
    return _ApiBootstrap(initialBaseUrl: initialBaseUrl);
  }
}

/// Прикрепляет apiBaseUrlProvider к App и рендерит App.
class _ApiBootstrap extends ConsumerStatefulWidget {
  final String initialBaseUrl;

  const _ApiBootstrap({required this.initialBaseUrl});

  @override
  ConsumerState<_ApiBootstrap> createState() => _ApiBootstrapState();
}

class _ApiBootstrapState extends ConsumerState<_ApiBootstrap> {
  @override
  void initState() {
    super.initState();
    // Провайдер-модификации — после монтирования дерева (Riverpod запрет).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(apiBaseUrlProvider.notifier).set(widget.initialBaseUrl);
      final api = ref.read(apiClientProvider);
      AppClientLogHook.api = api;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TsundokuApp(
      debugOverlayBuilder: kDebugMode ? buildDebugAgentationOverlay() : null,
    );
  }
}
