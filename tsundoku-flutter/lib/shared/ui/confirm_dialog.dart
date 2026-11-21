/// 1:1 port of `mediatracker-ui/src/shared/ui/confirmDialog.svelte.ts`.
///
/// Replaces every native `window.confirm()` with an in-app modal through the
/// shared Modal shell. Each action carries a memory key: при включённой
/// remember-галочке решение сохраняется в persisted-хранилище и тот же экшн
/// повторяется молча в следующий раз.
///
/// $state → Riverpod; localStorage → shared_preferences (ключ
/// tsundoku_confirm_memory, решение #13); Modal-виджет — Фаза 1 modal.dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _memoryKey = 'tsundoku_confirm_memory';
const Duration _hour = Duration(hours: 1);

/// `"none" | "forever" | "hour"`.
enum ConfirmRemember { none, forever, hour }

enum ConfirmDecision { confirmed, cancelled }

@immutable
class ConfirmMemoryEntry {
  final ConfirmDecision decision;
  /// "forever" | "hour".
  final String scope;
  /// Present for the hourly scope only; stale once `DateTime.now()` passes it.
  final int? expiresAt;

  const ConfirmMemoryEntry({
    required this.decision,
    required this.scope,
    this.expiresAt,
  });

  factory ConfirmMemoryEntry.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const ConfirmMemoryEntry(
          decision: ConfirmDecision.cancelled, scope: 'forever');
    }
    final decision = raw['decision'] == 'confirmed'
        ? ConfirmDecision.confirmed
        : ConfirmDecision.cancelled;
    final scope = raw['scope'] == 'hour' ? 'hour' : 'forever';
    return ConfirmMemoryEntry(
      decision: decision,
      scope: scope,
      expiresAt: (raw['expiresAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'decision': decision == ConfirmDecision.confirmed ? 'confirmed' : 'cancelled',
        'scope': scope,
        if (expiresAt != null) 'expiresAt': expiresAt,
      };
}

class ConfirmRequest {
  /// Memory key binding the decision to the action, e.g. "delete-media".
  final String key;
  final String title;

  /// Optional extra context line; omitted for short one-line questions.
  final String? description;
  final String? confirmLabel;
  final String? cancelLabel;

  /// Danger renders the confirm button in the destructive rose palette.
  final bool danger;

  const ConfirmRequest({
    required this.key,
    required this.title,
    this.description,
    this.confirmLabel,
    this.cancelLabel,
    this.danger = false,
  });
}

@immutable
class PendingConfirm {
  final ConfirmRequest request;
  final void Function(bool confirmed) resolve;

  const PendingConfirm({required this.request, required this.resolve});
}

@immutable
class ConfirmDialogState {
  /// The request currently showing its modal; null while nothing asks.
  final PendingConfirm? current;

  /// Mirror of the stored decisions so the Settings reset button can show
  /// what is kept.
  final int memoryVersion;

  const ConfirmDialogState({this.current, this.memoryVersion = 0});
}

class ConfirmDialogController extends Notifier<ConfirmDialogState> {
  @override
  ConfirmDialogState build() =>
      const ConfirmDialogState();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Map<String, ConfirmMemoryEntry>> _readMemory() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_memoryKey) ?? '{}';
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return {};
      return parsed.map((k, v) => MapEntry(k, ConfirmMemoryEntry.fromJson(v)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMemory(Map<String, ConfirmMemoryEntry> memory) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(
          _memoryKey,
          jsonEncode(memory
              .map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {
      // Storage full / disabled: the dialog simply asks again next time.
    }
  }

  /// Resolves immediately from memory when the action is remembered, otherwise
  /// opens the modal.
  Future<bool> request(ConfirmRequest options) async {
    final memory = await _readMemory();
    final entry = memory[options.key];
    if (entry != null) {
      final expired = entry.scope == 'hour' &&
          (entry.expiresAt ?? 0) <= DateTime.now().millisecondsSinceEpoch;
      if (!expired) {
        return entry.decision == ConfirmDecision.confirmed;
      }
      memory.remove(options.key);
      await _writeMemory(memory);
      state = ConfirmDialogState(
          memoryVersion: state.memoryVersion + 1);
    }
    // One question at a time: any racing second request queues behind the
    // live one.
    final completer = Completer<bool>();
    state = ConfirmDialogState(
      current: PendingConfirm(
          request: options, resolve: completer.complete),
      memoryVersion: state.memoryVersion,
    );
    return completer.future;
  }

  /// User picked a button inside the modal: persist the memory choice, then
  /// settle.
  Future<void> settle(bool confirmed, ConfirmRemember remember) async {
    final pending = state.current;
    state = ConfirmDialogState(memoryVersion: state.memoryVersion);
    if (pending == null) return;

    if (remember != ConfirmRemember.none) {
      final memory = await _readMemory();
      final decision =
          confirmed ? ConfirmDecision.confirmed : ConfirmDecision.cancelled;
      memory[pending.request.key] = remember == ConfirmRemember.forever
          ? ConfirmMemoryEntry(decision: decision, scope: 'forever')
          : ConfirmMemoryEntry(
              decision: decision,
              scope: 'hour',
              expiresAt:
                  DateTime.now().add(_hour).millisecondsSinceEpoch,
            );
      await _writeMemory(memory);
      state = ConfirmDialogState(
          memoryVersion: state.memoryVersion + 1);
    }
    pending.resolve(confirmed);
  }

  /// Backdrop click / Esc counts as cancel; never writes memory.
  void cancel() {
    final pending = state.current;
    state = ConfirmDialogState(memoryVersion: state.memoryVersion);
    pending?.resolve(false);
  }

  /// Settings escape hatch: drops every remembered decision so dialogs ask
  /// again. Returns how many were dropped.
  Future<int> clearMemory() async {
    final memory = await _readMemory();
    final count = memory.length;
    if (count > 0) {
      await _writeMemory({});
      state = ConfirmDialogState(
          memoryVersion: state.memoryVersion + 1);
    }
    return count;
  }

  /// How many actions currently hold a remembered decision (for the Settings
  /// row hint).
  Future<int> rememberedCount() async {
    final memory = await _readMemory();
    final now = DateTime.now().millisecondsSinceEpoch;
    return memory.values
        .where((entry) =>
            entry.scope == 'forever' || (entry.expiresAt ?? 0) > now)
        .length;
  }
}

/// `export const confirmDialog = new ConfirmDialogStore();`
final confirmDialogProvider =
    NotifierProvider<ConfirmDialogController, ConfirmDialogState>(
        ConfirmDialogController.new);

/// Fire-and-await confirmation: `if (!(await confirmAction({...}))) return;`
///
/// WidgetRef: функция вызывается из виджетов (1-в-1 с Svelte-компонентами).
Future<bool> confirmAction(WidgetRef ref, ConfirmRequest options) {
  return ref.read(confirmDialogProvider.notifier).request(options);
}
