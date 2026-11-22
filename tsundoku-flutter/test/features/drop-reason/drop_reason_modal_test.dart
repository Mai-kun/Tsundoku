import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/drop-reason/drop_reason_modal.dart';
import 'package:tsundoku_flutter/features/drop-reason/drop_reason_prompt.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    lastRequest = options;
    lastBody = options.data;
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'success': true}),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  DropPromptTarget? target,
  bool? isOpen,
  VoidCallback? onClose,
  _CapturingAdapter? adapter,
  DropPromptTarget? promptStateTarget,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
      if (promptStateTarget != null)
        dropPromptStateProvider.overrideWith(() {
          final c = DropReasonPromptController();
          c.open(promptStateTarget);
          return c;
        }),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: DropReasonModal(
          target: target,
          isOpen: isOpen,
          onClose: onClose,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hides when isOpen is false or target is null', (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('Почему вы решили бросить?'), findsNothing);
  });

  testWidgets('renders modal header, chips and inputs when target is passed',
      (tester) async {
    final target = DropPromptTarget(
      id: 'm123',
      title: 'Steins;Gate',
      type: 'anime',
      isAnime: true,
    );

    await tester.pumpWidget(_buildSubject(target: target, isOpen: true));
    await tester.pumpAndSettle();

    expect(find.text('Почему вы решили бросить?'), findsOneWidget);
    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.text('Скучно / Затянуто'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    // Delete reason button should not be present when dropReason is null.
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
  });

  testWidgets('toggles reason chip on click', (tester) async {
    final target = DropPromptTarget(
      id: 'm123',
      title: 'Steins;Gate',
      type: 'anime',
    );

    await tester.pumpWidget(_buildSubject(target: target, isOpen: true));
    await tester.pumpAndSettle();

    final chipFinder = find.text('Скучно / Затянуто');
    expect(chipFinder, findsOneWidget);

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    // Tap again to toggle off
    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
  });

  testWidgets('saves selected reason and notes via API and triggers onSaved',
      (tester) async {
    final adapter = _CapturingAdapter();
    String? savedReason;
    String? savedNotes;
    var closed = false;

    final target = DropPromptTarget(
      id: 'm123',
      title: 'Steins;Gate',
      type: 'anime',
      onSaved: (r, n) {
        savedReason = r;
        savedNotes = n;
      },
    );

    await tester.pumpWidget(_buildSubject(
      target: target,
      isOpen: true,
      onClose: () => closed = true,
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    // Select reason
    await tester.tap(find.text('Скучно / Затянуто'));
    await tester.pumpAndSettle();

    // Enter note
    await tester.enterText(find.byType(TextField), 'Не зашло начало');
    await tester.pumpAndSettle();

    // Click Save
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(adapter.lastRequest?.path, contains('/api/media/m123/status'));
    expect(adapter.lastBody, {
      'status': 4, // MediaStatus.dropped.value
      'dropReason': 'boring',
      'dropNotes': 'Не зашло начало',
    });
    expect(savedReason, 'boring');
    expect(savedNotes, 'Не зашло начало');
    expect(closed, isTrue);
  });

  testWidgets('shows delete reason button when dropReason exists and calls API on delete',
      (tester) async {
    final adapter = _CapturingAdapter();
    String? savedReason = 'existing';
    String? savedNotes = 'existing notes';
    var closed = false;

    final target = DropPromptTarget(
      id: 'm123',
      title: 'Steins;Gate',
      type: 'anime',
      dropReason: 'boring',
      dropNotes: 'Some notes',
      onSaved: (r, n) {
        savedReason = r;
        savedNotes = n;
      },
    );

    await tester.pumpWidget(_buildSubject(
      target: target,
      isOpen: true,
      onClose: () => closed = true,
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Удалить причину'), findsOneWidget);

    await tester.tap(find.text('Удалить причину'));
    await tester.pumpAndSettle();

    expect(adapter.lastRequest?.path, contains('/api/media/m123/status'));
    expect(adapter.lastBody, {
      'status': 4,
      'dropReason': '',
      'dropNotes': '',
    });
    expect(savedReason, isNull);
    expect(savedNotes, isNull);
    expect(closed, isTrue);
  });

  testWidgets('skip calls onClose callback', (tester) async {
    var closed = false;
    final target = DropPromptTarget(
      id: 'm123',
      title: 'Steins;Gate',
      type: 'anime',
    );

    await tester.pumpWidget(_buildSubject(
      target: target,
      isOpen: true,
      onClose: () => closed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
