/// 1:1 port of `mediatracker-ui/src/features/drop-reason/dropReasonPrompt.svelte.ts`.
///
/// $state target → Riverpod Notifier. window.history.pushState/back для
/// модалки — браузерная фича, во Flutter стек навигации управляет сам
/// (решение #10).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class DropPromptTarget {
  final String id;
  final String title;
  final String? type;
  final bool? isAnime;
  final String? dropReason;
  final String? dropNotes;
  final void Function(String? dropReason, String? dropNotes)? onSaved;
  final void Function()? onClose;

  const DropPromptTarget({
    required this.id,
    required this.title,
    this.type,
    this.isAnime,
    this.dropReason,
    this.dropNotes,
    this.onSaved,
    this.onClose,
  });
}

class DropReasonPromptController extends Notifier<DropPromptTarget?> {
  @override
  DropPromptTarget? build() => null;

  void open(DropPromptTarget target) {
    state = target;
    // history.pushState — браузерная фича; во Flutter модалка ставится в стек
    // Navigator'ом (решение #10).
  }

  void close() {
    state?.onClose?.call();
    state = null;
  }
}

/// `export const dropPromptState = new DropReasonState();`
final dropPromptStateProvider =
    NotifierProvider<DropReasonPromptController, DropPromptTarget?>(
        DropReasonPromptController.new);
