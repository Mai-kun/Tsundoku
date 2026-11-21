/// 1:1 port of `mediatracker-ui/src/shared/ui/contextMenu.svelte.ts`.
///
/// Svelte writable-сторы → Riverpod Notifier'ы. openContextMenu/closeContextMenu
/// и ListPicker-модал (activeListPickerMediaId) — та же семантика.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Context menu item. For separator `kind: 'separator'` label and action are
/// optional.
class MenuItem {
  final String id;
  final String? label;
  final String? icon;
  /// `"default" | "separator" | "danger"`.
  final String kind;
  final bool disabled;
  final void Function()? action;
  final List<MenuItem>? children;
  final String? mediaId;
  /// Requires a 1-second hold instead of a click; the menu stays open until it
  /// completes.
  final bool holdToDelete;

  const MenuItem({
    required this.id,
    this.label,
    this.icon,
    this.kind = 'default',
    this.disabled = false,
    this.action,
    this.children,
    this.mediaId,
    this.holdToDelete = false,
  });

  const MenuItem.separator()
      : this(id: 'sep', kind: 'separator');
}

@immutable
class ContextMenuState {
  final bool isOpen;
  final double x;
  final double y;
  final List<MenuItem> items;

  const ContextMenuState({
    this.isOpen = false,
    this.x = 0,
    this.y = 0,
    this.items = const <MenuItem>[],
  });
}

class ContextMenuController extends Notifier<ContextMenuState> {
  @override
  ContextMenuState build() => const ContextMenuState();

  void open(double x, double y, List<MenuItem> items) {
    state = ContextMenuState(isOpen: true, x: x, y: y, items: items);
  }

  void close() {
    state = const ContextMenuState();
  }
}

/// `export const contextMenuStore = createContextMenuStore();`
final contextMenuStoreProvider =
    NotifierProvider<ContextMenuController, ContextMenuState>(
        ContextMenuController.new);

/// Open context menu at (x, y) coordinates.
void openContextMenu(Ref ref, double x, double y, List<MenuItem> items) {
  ref.read(contextMenuStoreProvider.notifier).open(x, y, items);
}

/// Close context menu.
void closeContextMenu(Ref ref) {
  ref.read(contextMenuStoreProvider.notifier).close();
}

/// Media ID for the ListPicker add-to-list modal.
class ActiveListPickerMediaIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? mediaId) => state = mediaId;
}

final activeListPickerMediaIdProvider =
    NotifierProvider<ActiveListPickerMediaIdController, String?>(
        ActiveListPickerMediaIdController.new);

void openListPicker(Ref ref, String mediaId) {
  ref.read(activeListPickerMediaIdProvider.notifier).set(mediaId);
}

void closeListPicker(Ref ref) {
  ref.read(activeListPickerMediaIdProvider.notifier).set(null);
}
