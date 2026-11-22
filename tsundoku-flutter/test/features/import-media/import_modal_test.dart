import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/import-media/import_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{}),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  required bool isOpen,
  VoidCallback? onClose,
  VoidCallback? onImportCompleted,
  ValueChanged<String>? onNavigateToList,
  ImportPanelBuilder? panelBuilder,
}) {
  final dio = Dio()..httpClientAdapter = _StubAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: ImportModal(
          isOpen: isOpen,
          onClose: onClose ?? () {},
          onImportCompleted: onImportCompleted ?? () {},
          onNavigateToList: onNavigateToList,
          panelBuilder: panelBuilder,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hides when isOpen is false', (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('Импорт медиатеки'), findsNothing);
  });

  testWidgets('renders default modal header and close button when open',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      onClose: () => closed = true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Импорт медиатеки'), findsOneWidget);
    expect(find.byIcon(LucideIcons.folderInput), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });

  testWidgets('renders custom panel via panelBuilder and forwards callbacks',
      (tester) async {
    var completed = false;
    String? navigatedList;
    var closed = false;

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      onClose: () => closed = true,
      onImportCompleted: () => completed = true,
      onNavigateToList: (id) => navigatedList = id,
      panelBuilder: (context, {
        required onImportCompleted,
        required onClose,
        onNavigateToList,
        bool showCloseButton = false,
      }) {
        return Column(
          children: [
            const Text('Custom Import Panel'),
            ElevatedButton(
              onPressed: onImportCompleted,
              child: const Text('Complete Import'),
            ),
            ElevatedButton(
              onPressed: () => onNavigateToList?.call('list-99'),
              child: const Text('Go To List'),
            ),
            ElevatedButton(
              onPressed: onClose,
              child: const Text('Close Modal'),
            ),
          ],
        );
      },
    ));
    await tester.pumpAndSettle();

    expect(find.text('Custom Import Panel'), findsOneWidget);

    await tester.tap(find.text('Complete Import'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);

    await tester.tap(find.text('Go To List'));
    await tester.pumpAndSettle();
    expect(navigatedList, 'list-99');

    await tester.tap(find.text('Close Modal'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
