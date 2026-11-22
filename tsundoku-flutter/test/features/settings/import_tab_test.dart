import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/import_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _CapturingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/api/lists')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (path.contains('/api/sources')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('ImportTab renders embedded ImportPanel with all providers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dio = Dio()..httpClientAdapter = _CapturingAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(TsundokuApi(dio)),
        ],
        child: MaterialApp(
          theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
          home: const Scaffold(
            body: ImportTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('MangaLib'), findsOneWidget);
    expect(find.text('MyAnimeList'), findsOneWidget);
    expect(find.text('Steam'), findsOneWidget);
    expect(find.text('CSV / JSON'), findsOneWidget);
  });
}
