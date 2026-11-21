import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/main.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

/// Тест сборки [buildTsundokuTheme] — 1-в-1 daisyUI-слой + `:root`-правила
/// `app.css`. Значения самих токенов — в `tsundoku_tokens_test.dart`.
class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(<dynamic>[]), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
}

Dio _themeStubDio() {
  final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
  dio.httpClientAdapter = _StubAdapter();
  return dio;
}

void main() {
  Color rgb(int r, int g, int b, [double a = 1.0]) =>
      Color.fromRGBO(r, g, b, a);

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('buildTsundokuTheme — сборка ThemeData', () {
    final data = buildTsundokuTheme();

    testWidgets('fontFamily Inter + фон canvas + расширение в дереве',
        (tester) async {
      await tester.pumpWidget(TsundokuApp(providerOverrides: <dynamic>[
        apiClientProvider.overrideWithValue(
            TsundokuApi(_themeStubDio())),
        jobsClientProvider.overrideWith(_NoopJobs.new),
      ]));
      // 20s > 15s safety-таймера networkActivity (dio-запросы HomeView).
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Каркас Фазы 3: AppShell вместо Scaffold-заглушки — берём контекст
      // под MaterialApp (Material внутри AppShell).
      final ctx = tester.element(find.byType(SizedBox).first);
      final theme = Theme.of(ctx);

      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      // `:root { color: var(--color-ink); }` — onSurface = textPrimary.
      expect(theme.textTheme.bodyMedium?.color,
          TsundokuTheme.obsidian.textPrimary);
      expect(theme.scaffoldBackgroundColor, TsundokuTheme.obsidian.bgCanvas);
      expect(
        Theme.of(ctx).extension<TsundokuTheme>(),
        TsundokuTheme.obsidian,
      );
      expect(TsundokuTheme.of(ctx), TsundokuTheme.obsidian);
    });

    test('colorScheme из токенов', () {
      expect(data.colorScheme.primary, TsundokuTheme.obsidian.accent);
      expect(data.colorScheme.onPrimary, TsundokuPalette.primaryContent);
      expect(data.colorScheme.surface, TsundokuTheme.obsidian.bgCard);
      expect(data.colorScheme.onSurface, TsundokuTheme.obsidian.textPrimary);
      // daisyUI secondary = --accent-soft.
      expect(data.colorScheme.secondary, TsundokuTheme.obsidian.accentSoft);
    });

    test('dialog/modal — opaque overlay над постерами', () {
      expect(data.dialogTheme.backgroundColor, TsundokuTheme.obsidian.bgOverlay);
      expect(data.popupMenuTheme.color, TsundokuTheme.obsidian.bgOverlay);
    });

    test('scrollbar 1-в-1 с app.css', () {
      expect(
        data.scrollbarTheme.thumbColor?.resolve(const <WidgetState>{}),
        TsundokuPalette.scrollbarThumb,
      );
      expect(
        data.scrollbarTheme.trackColor?.resolve(const <WidgetState>{}),
        TsundokuTheme.obsidian.bgSurface,
      );
      expect(
        data.scrollbarTheme.thickness?.resolve(const <WidgetState>{}),
        TsundokuPalette.scrollbarWidth,
      );
    });

    test('input-поля на --color-field (bg-surface)', () {
      expect(data.inputDecorationTheme.fillColor,
          TsundokuTheme.obsidian.bgSurface);
    });

    test('TsundokuPalette: литералы @theme static 1-в-1', () {
      expect(TsundokuPalette.panel, rgb(26, 30, 40)); // #1a1e28
      expect(TsundokuPalette.overlayStrong, rgb(30, 34, 45)); // #1e222d
      expect(TsundokuPalette.rose500, rgb(185, 43, 66)); // #b92b42
      expect(TsundokuPalette.indigo600, rgb(67, 56, 202)); // #4338ca
      expect(TsundokuPalette.scoreBg, rgb(74, 99, 201)); // #4a63c9
      expect(TsundokuPalette.slateDeep, rgb(3, 37, 65)); // #032541
      expect(TsundokuPalette.dangerSurface, rgb(43, 16, 22)); // #2b1016
      expect(TsundokuPalette.successSurface, rgb(15, 36, 29)); // #0f241d
      expect(TsundokuPalette.warningSurface, rgb(40, 30, 14)); // #281e0e
      expect(TsundokuPalette.radiusBox, 12.0);
      expect(TsundokuPalette.radiusField, 8.0);
      expect(TsundokuPalette.radiusSelector, 6.0);
      expect(TsundokuPalette.thinScrollbarWidth, 6.0);
      // ease-tap: cubic-bezier(0.2, 0, 0, 1).
      expect(TsundokuPalette.easeTap, const Cubic(0.2, 0, 0, 1));
      expect(TsundokuPalette.curveEnter, const Cubic(0.16, 1, 0.3, 1));
      expect(TsundokuPalette.durationViewFade, const Duration(milliseconds: 150));
      expect(TsundokuPalette.durationPopover, const Duration(milliseconds: 140));
    });

    test('buildTsundokuTheme с кастомными токенами подменяет палитру', () {
      final custom = buildTsundokuTheme(
        tokens: TsundokuTheme.obsidian.copyWith().lerp(
              TsundokuTheme.obsidian,
              0,
            ) as TsundokuTheme,
      );
      expect(custom.scaffoldBackgroundColor, TsundokuTheme.obsidian.bgCanvas);
    });
  });
}
