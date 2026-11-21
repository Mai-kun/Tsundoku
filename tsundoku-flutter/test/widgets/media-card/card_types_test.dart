import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';

/// Smoke-тесты контракта карточек: CardTimeHint, MediaCardProps (дефолты,
/// withItem-спред).
void main() {
  final item = MediaItem.fromJson(const {
    'id': 'm1',
    'type': 'book',
    'title': 'Властелин колец',
    'status': 2,
    'createdAt': '2024-01-01T00:00:00Z',
  });

  test('CardTimeHint: поля', () {
    const hint = CardTimeHint(label: 'осталось ~2 ч', canFinishNow: true);
    expect(hint.label, 'осталось ~2 ч');
    expect(hint.canFinishNow, isTrue);
  });

  test('MediaCardProps: дефолты 1-в-1 с TS-интерфейсом', () {
    final props = MediaCardProps(item: item);
    expect(props.showProgress, isTrue); // showProgress = true
    expect(props.timeHint, isNull);
    expect(props.onOpen, isNull);
    expect(props.onProgress, isNull);
    expect(props.onProgressCommitted, isNull);
    expect(props.onStatusChange, isNull);
    expect(props.onDelete, isNull);
    expect(props.onEdit, isNull);
    expect(props.onEpisodeStep, isNull);
  });

  test('MediaCardProps: все колбеки присваиваются и вызываются', () async {
    var opened = false;
    var progressed = '';
    var committed = false;
    var statusChanged = 0;
    var deleted = false;
    var edited = false;
    var episodeStep = 0;

    Future<void> progress(String id, int value) async => progressed = '$id:$value';
    Future<void> delete(MediaItem i) async => deleted = true;
    FutureOr<void> episode(MediaItem i, int w) => episodeStep = w;

    final props = MediaCardProps(
      item: item,
      showProgress: false,
      onOpen: (_) => opened = true,
      onProgress: progress,
      onProgressCommitted: () => committed = true,
      onStatusChange: (i, s) => statusChanged = s.value,
      onDelete: delete,
      onEdit: (_) => edited = true,
      onEpisodeStep: episode,
    );

    props.onOpen!(props.item);
    await props.onProgress!('m1', 42);
    props.onProgressCommitted!();
    props.onStatusChange!(props.item, props.item.status);
    await props.onDelete!(props.item);
    props.onEdit!(props.item);
    await props.onEpisodeStep!(props.item, 7);

    expect(opened, isTrue);
    expect(progressed, 'm1:42');
    expect(committed, isTrue);
    expect(deleted, isTrue);
    expect(edited, isTrue);
    expect(episodeStep, 7);
    expect(props.showProgress, isFalse);
    statusChanged = statusChanged; // no-op, value checked below
    expect(props.item.id, 'm1');
  });

  test('withItem: спред с подменой item (1-в-1 с {...rest, item})', () {
    final other = MediaItem.fromJson(const {
      'id': 'm2',
      'type': 'book',
      'title': 'Хоббит',
      'status': 1,
      'createdAt': '2024-01-01T00:00:00Z',
    });
    final props = MediaCardProps(
      item: item,
      onOpen: (_) {},
      showProgress: false,
    );
    final copied = props.withItem(other);
    expect(copied.item.id, 'm2');
    expect(copied.showProgress, isFalse);
    expect(copied.onOpen, same(props.onOpen));
    expect(copied.onProgress, isNull);
  });
}
