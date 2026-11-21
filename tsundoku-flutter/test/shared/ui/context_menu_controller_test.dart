import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu_controller.dart';

/// Полный цикл контекстного меню и ListPicker-модала.
void main() {
  late ProviderContainer container;
  late ContextMenuController ctrl;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    ctrl = container.read(contextMenuStoreProvider.notifier);
  });

  test('open: координаты и items сохраняются', () {
    final items = [
      const MenuItem(id: 'edit', label: 'Edit'),
      MenuItem.separator(),
      const MenuItem(id: 'del', label: 'Delete', kind: 'danger', holdToDelete: true),
    ];
    ctrl.open(100, 200, items);
    final s = container.read(contextMenuStoreProvider);
    expect(s.isOpen, isTrue);
    expect(s.x, 100);
    expect(s.y, 200);
    expect(s.items, hasLength(3));
    expect(s.items[1].kind, 'separator');
    expect(s.items[2].holdToDelete, isTrue);
  });

  test('close: всё сбрасывается', () {
    ctrl.open(1, 2, const [MenuItem(id: 'a', label: 'A')]);
    ctrl.close();
    final s = container.read(contextMenuStoreProvider);
    expect(s.isOpen, isFalse);
    expect(s.items, isEmpty);
  });

  test('MenuItem: дефолты 1-в-1 (kind=default, holdToDelete=false)', () {
    const item = MenuItem(id: 'x', label: 'X');
    expect(item.kind, 'default');
    expect(item.holdToDelete, isFalse);
    expect(item.disabled, isFalse);
  });

  test('ListPicker media id: open/close', () {
    expect(container.read(activeListPickerMediaIdProvider), isNull);
    container.read(activeListPickerMediaIdProvider.notifier).set('media-42');
    expect(container.read(activeListPickerMediaIdProvider), 'media-42');
    container.read(activeListPickerMediaIdProvider.notifier).set(null);
    expect(container.read(activeListPickerMediaIdProvider), isNull);
  });
}
