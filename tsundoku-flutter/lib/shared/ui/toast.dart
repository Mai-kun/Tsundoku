/// 1:1 port of `mediatracker-ui/src/shared/ui/toast.svelte.ts` + `ToastContainer.svelte`.
///
/// $state items → Riverpod Notifier; serverRestart-гейт — через
/// [serverRestartProvider]; рендер тостов — [ToastOverlay] (стек снизу-справа,
/// 1-в-1 с ToastContainer.svelte из widgets/layout — Фаза 3 его смонтирует).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_restart.dart';

/// `"success" | "info" | "warning" | "error"`.
enum ToastType {
  success('success'),
  info('info'),
  warning('warning'),
  error('error');

  final String wire;
  const ToastType(this.wire);

  static ToastType? tryFromWire(String wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

/// A custom labelled button (e.g. the keepStatus action). Rendered as a
/// compact icon in the collapsed corner row and as a full text button in the
/// expanded footer.
class ToastAction {
  /// Machine id, e.g. "keepStatus"; also picks the collapsed icon glyph.
  final String id;
  final String label;
  final void Function() onClick;

  /// "primary" renders filled, "neutral" (default) renders outlined.
  final String kind;

  const ToastAction({
    required this.id,
    required this.label,
    required this.onClick,
    this.kind = 'neutral',
  });
}

class ToastOptions {
  /// Strict contract: every toast carries a readable headline.
  final String title;

  /// Strict contract: every toast carries a detailed explanation revealed on
  /// expand.
  final String description;
  final ToastType? type;

  /// Auto-dismiss delay; 0 disables the timer and the countdown bar.
  final int? durationMs;

  /// Standard "OK" button — confirm and close.
  final bool? showOk;

  /// Standard "Undo" button; the callback must persist the revert
  /// server-side.
  final void Function()? undo;

  /// Extra custom buttons rendered next to OK/Undo (e.g. keepStatus).
  final List<ToastAction> actions;

  /// Fired only for an explicit user close (X button) — never for auto-expiry,
  /// so a toast whose expiry itself performs an action can safely cancel on X.
  final void Function()? onClose;

  const ToastOptions({
    required this.title,
    required this.description,
    this.type,
    this.durationMs,
    this.showOk,
    this.undo,
    this.actions = const <ToastAction>[],
    this.onClose,
  });
}

@immutable
class ToastItem {
  final String id;
  final String title;
  final String description;
  final ToastType type;
  final int durationMs;
  final bool showOk;
  final void Function()? undo;
  final List<ToastAction> actions;
  final void Function()? onClose;

  const ToastItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.durationMs,
    required this.showOk,
    required this.undo,
    required this.actions,
    required this.onClose,
  });
}

const int defaultDurationMs = 4000;
const int maxToasts = 5;

class ToastStoreController extends Notifier<List<ToastItem>> {
  final Map<String, Timer> _timers = <String, Timer>{};

  @override
  List<ToastItem> build() {
    ref.onDispose(_disposeTimers);
    return const <ToastItem>[];
  }

  String show(ToastOptions options) {
    final type = options.type ?? ToastType.success;
    // During a backend restart the background refresh catches "connection
    // failed" and tries to show an "unexpected error" — that failure is
    // expected, the modal state already shows a spinner.
    if (type == ToastType.error &&
        ref.read(serverRestartProvider)) {
      return '';
    }

    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final item = ToastItem(
      id: id,
      title: options.title,
      description: options.description,
      type: type,
      durationMs: options.durationMs ?? defaultDurationMs,
      showOk: options.showOk ?? false,
      undo: options.undo,
      actions: options.actions,
      onClose: options.onClose,
    );
    final list = [...state];
    if (list.length >= maxToasts) {
      list.removeRange(0, list.length - (maxToasts - 1));
    }
    list.add(item);
    state = list;

    if (item.durationMs > 0) {
      _timers[id] = Timer(Duration(milliseconds: item.durationMs), () {
        dismiss(id);
      });
    }
    return id;
  }

  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    state = state.where((t) => t.id != id).toList();
  }

  void _disposeTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// `export const toastStore = new ToastStore();`
final toastStoreProvider =
    NotifierProvider<ToastStoreController, List<ToastItem>>(
        ToastStoreController.new);

/// Strict-contract toast: `title` and `description` are mandatory at compile
/// time.
String showToast(WidgetRef ref, ToastOptions options) {
  return ref.read(toastStoreProvider.notifier).show(options);
}

void dismissToast(WidgetRef ref, String id) {
  ref.read(toastStoreProvider.notifier).dismiss(id);
}
