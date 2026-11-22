/// 1:1 port of `mediatracker-ui/src/features/drop-reason/DropReasonModal.svelte`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/drop_reasons.dart';
import 'package:tsundoku_flutter/features/drop-reason/drop_reason_prompt.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/ui/modal.dart';

class DropReasonModal extends ConsumerStatefulWidget {
  final DropPromptTarget? target;
  final bool? isOpen;
  final VoidCallback? onClose;

  const DropReasonModal({
    super.key,
    this.target,
    this.isOpen,
    this.onClose,
  });

  @override
  ConsumerState<DropReasonModal> createState() => _DropReasonModalState();
}

class _DropReasonModalState extends ConsumerState<DropReasonModal> {
  String? _selectedReason;
  late final TextEditingController _notesController;
  bool _saving = false;
  Object? _saveError;
  String? _lastTargetId;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _initFromTarget(_effectiveTarget(ref.read(dropPromptStateProvider)));
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DropPromptTarget? _effectiveTarget(DropPromptTarget? promptTarget) {
    return widget.target ?? promptTarget;
  }

  void _initFromTarget(DropPromptTarget? target) {
    if (target != null) {
      _lastTargetId = target.id;
      _selectedReason = target.dropReason;
      _notesController.text = target.dropNotes ?? '';
      _saveError = null;
    }
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      ref.read(dropPromptStateProvider.notifier).close();
    }
  }

  void _handleSkip() {
    if (_saving) return;
    _close();
  }

  void _toggleReason(String key) {
    setState(() {
      _selectedReason = _selectedReason == key ? null : key;
    });
  }

  Future<void> _handleSave(DropPromptTarget target) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final cleanNotes = _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim();
      final api = ref.read(apiClientProvider);
      await api.updateStatusWithDropInfo(
        target.id,
        MediaStatus.dropped,
        dropReason: _selectedReason,
        dropNotes: cleanNotes,
      );
      target.onSaved?.call(_selectedReason, cleanNotes);
      _close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _handleDeleteReason(DropPromptTarget target) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      await api.updateStatusWithDropInfo(
        target.id,
        MediaStatus.dropped,
        dropReason: '',
        dropNotes: '',
      );
      target.onSaved?.call(null, null);
      _close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final promptTarget = ref.watch(dropPromptStateProvider);
    final target = _effectiveTarget(promptTarget);
    final isExplicitOpen = widget.isOpen;
    final isOpen = isExplicitOpen ?? (target != null);

    // Sync state when target changes.
    if (target != null && target.id != _lastTargetId) {
      _initFromTarget(target);
    }

    if (!isOpen || target == null) {
      return TsundokuModal(
        isOpen: false,
        onClose: _handleSkip,
        size: ModalSize.md,
        child: const SizedBox.shrink(),
      );
    }

    final t = ref.watch(tProvider);
    final isRu = t.locale == Locale.ru;
    final options = getDropReasonsForMediaType(target.type, isAnime: target.isAnime);

    return TsundokuModal(
      isOpen: true,
      onClose: _handleSkip,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0), // p-6
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0x1AF43F5E), // rose-500/10
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x33F43F5E)), // rose-500/20
                        ),
                        child: const Center(
                          child: Icon(
                            LucideIcons.ban,
                            size: 20,
                            color: Color(0xFFFB7185), // rose-400
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.tr('dropReason.modalTitle'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              target.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8), // slate-400
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    LucideIcons.x,
                    size: 18,
                    color: Color(0xFF94A3B8), // slate-400
                  ),
                  onPressed: _handleSkip,
                ),
              ],
            ),
            const SizedBox(height: 20), // space-y-5

            // Chips container
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 224),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((option) {
                    final active = _selectedReason == option.key;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _toggleReason(option.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0x33F43F5E) // rose-500/20
                              : const Color(0x0AFFFFFF), // white/[0.04]
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active
                                ? const Color(0x66F43F5E) // rose-500/40
                                : const Color(0x14FFFFFF), // white/[0.08]
                          ),
                          boxShadow: active
                              ? const [
                                  BoxShadow(
                                    color: Color(0x4DF43F5E), // rose-500/30
                                    blurRadius: 1,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          isRu ? option.labelRu : option.labelEn,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                            color: active
                                ? const Color(0xFFFDA4AF) // rose-300
                                : const Color(0xFFCBD5E1), // slate-300
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20), // space-y-5

            // Note input
            TextField(
              controller: _notesController,
              maxLength: 200,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: t.tr('dropReason.notesPlaceholder'),
                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                filled: true,
                fillColor: const Color(0x08FFFFFF),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0x80FB7185)),
                ),
              ),
              onSubmitted: (_) => _handleSave(target),
            ),

            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage(_saveError!, t.locale),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFB7185), // rose-400
                ),
              ),
            ],
            const SizedBox(height: 20), // space-y-5

            // Footer actions
            Container(
              padding: const EdgeInsets.only(top: 4), // pt-1
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0x0DFFFFFF)), // white/5
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Delete reason
                  if (target.dropReason != null && target.dropReason!.isNotEmpty)
                    TextButton.icon(
                      onPressed: _saving ? null : () => _handleDeleteReason(target),
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 13,
                        color: Color(0xCCFB7185), // rose-400/80
                      ),
                      label: Text(
                        t.tr('dropReason.deleteReason'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xCCFB7185),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  // Right: Skip & Save
                  Row(
                    children: [
                      TextButton(
                        onPressed: _saving ? null : _handleSkip,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          t.tr('dropReason.skip'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFCBD5E1), // slate-300
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : () => _handleSave(target),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xE6E11D48), // rose-600/90
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0x80E11D48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _saving ? '...' : t.tr('dropReason.save'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
