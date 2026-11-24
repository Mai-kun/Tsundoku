/// 1:1 port of `mediatracker-ui/src/features/lists/CreateListModal.svelte`.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/cover_url.dart';
import 'package:tsundoku_flutter/features/lists/smart_list_builder.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/media_cover_placeholder.dart';
import 'package:tsundoku_flutter/shared/ui/modal.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

const List<String> kCustomListColors = <String>[
  '#473bb8',
  '#4a72b8',
  '#3f8f6b',
  '#c08a3e',
  '#b85a86',
  '#3d8fa3',
];

const List<({String key, IconData icon})> kCustomListIcons =
    <({String key, IconData icon})>[
  (key: 'list', icon: LucideIcons.list),
  (key: 'bookmark', icon: LucideIcons.bookmark),
  (key: 'heart', icon: LucideIcons.heart),
  (key: 'star', icon: LucideIcons.star),
  (key: 'sparkles', icon: LucideIcons.sparkles),
  (key: 'flame', icon: LucideIcons.flame),
];

typedef SmartListBuilderWidget = Widget Function(
  BuildContext context, {
  required SmartListQuery query,
  required ValueChanged<SmartListQuery> onQueryChange,
  required ValueChanged<List<MediaItem>> onMatchesChange,
  required List<MediaItem> allMedia,
});

class CreateListModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final CustomListSummary? list;
  final VoidCallback onClose;
  final VoidCallback onSaved;
  final SmartListBuilderWidget? smartListBuilder;

  const CreateListModal({
    super.key,
    required this.isOpen,
    this.list,
    required this.onClose,
    required this.onSaved,
    this.smartListBuilder,
  });

  @override
  ConsumerState<CreateListModal> createState() => _CreateListModalState();
}

class _CreateListModalState extends ConsumerState<CreateListModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _color = kCustomListColors[0];
  String _icon = 'list';
  bool _busy = false;
  String? _error;
  String _listType = 'manual'; // 'manual' | 'smart'
  SmartListQuery _smartQuery = const SmartListQuery();
  List<MediaItem> _allMedia = const <MediaItem>[];
  List<MediaItem> _matchedItems = const <MediaItem>[];
  bool _lastOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) {
      _initFields();
      _lastOpen = true;
    }
  }

  @override
  void didUpdateWidget(covariant CreateListModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !_lastOpen) {
      _initFields();
    }
    _lastOpen = widget.isOpen;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initFields() {
    final list = widget.list;
    _nameController.text = list?.name ?? '';
    _descriptionController.text = list?.description ?? '';
    _color = list?.color ?? kCustomListColors[0];
    _icon = list?.icon ?? 'list';
    _error = null;

    if (list?.smartQueryJson != null && list!.smartQueryJson!.isNotEmpty) {
      _listType = 'smart';
      try {
        _smartQuery = SmartListQuery.fromJson(
            jsonDecode(list.smartQueryJson!) as Map<String, dynamic>);
      } catch (_) {
        _smartQuery = const SmartListQuery();
      }
    } else {
      _listType = 'manual';
      _smartQuery = const SmartListQuery();
    }

    if (widget.list == null) {
      ref.read(apiClientProvider).getMedia().then((items) {
        if (mounted) setState(() => _allMedia = items);
      }).catchError((_) {});
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final payload = CreateListPayload(
      name: name,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      icon: _icon,
      color: _color,
      smartQueryJson:
          _listType == 'smart' ? jsonEncode(_smartQuery.toJson()) : null,
    );

    try {
      final api = ref.read(apiClientProvider);
      if (widget.list != null) {
        await api.updateList(widget.list!.id, payload);
      } else {
        await api.createList(payload);
      }
      widget.onSaved();
      widget.onClose();
    } catch (caught) {
      if (mounted) {
        setState(() {
          _error = errorMessage(caught, ref.read(i18nProvider));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Color _parseHex(String hex) {
    try {
      return Color(int.parse(hex.replaceAll('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF473BB8);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) {
      return TsundokuModal(
        isOpen: false,
        onClose: widget.onClose,
        size: ModalSize.lg,
        child: const SizedBox.shrink(),
      );
    }

    final t = ref.watch(tProvider);
    final accentColor = TsundokuTheme.of(context).accent;

    return TsundokuModal(
      isOpen: true,
      onClose: widget.onClose,
      size: ModalSize.lg,
      contentPadding: EdgeInsets.zero,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF151A26),
                border: Border(
                  bottom: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.list != null
                                ? t.tr('views.listEdit')
                                : t.tr('views.listCreate'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.tr('views.listModalHint'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          LucideIcons.x,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  if (widget.list == null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeButton(
                            icon: '📁',
                            label: t.tr('views.listTypeManual'),
                            active: _listType == 'manual',
                            activeColor: accentColor,
                            onTap: () {
                              setState(() {
                                _listType = 'manual';
                                _smartQuery = const SmartListQuery();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTypeButton(
                            icon: '⚡',
                            label: t.tr('views.listTypeSmart'),
                            active: _listType == 'smart',
                            activeColor: const Color(0xFFA78BFA), // violet-400
                            onTap: () {
                              setState(() => _listType = 'smart');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // 2. Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      t.tr('views.listName'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: _nameController,
                      maxLength: 100,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    Text(
                      t.tr('views.listDescription'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: _descriptionController,
                      maxLength: 500,
                      multiline: true,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Color
                    Text(
                      t.tr('views.listColor'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: kCustomListColors.map((colorHex) {
                        final isSelected = _color == colorHex;
                        final parsed = _parseHex(colorHex);
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _color = colorHex),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: parsed,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                              boxShadow: isSelected
                                  ? const [
                                      BoxShadow(
                                        color: Colors.black45,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Icon
                    Text(
                      t.tr('views.listIcon'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kCustomListIcons.map((entry) {
                        final isSelected = _icon == entry.key;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _icon = entry.key),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? accentColor
                                    : const Color(0x1AFFFFFF),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                entry.icon,
                                size: 18,
                                color: isSelected
                                    ? accentColor
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Smart List block
                    if (_listType == 'smart') ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0x0DA78BFA), // violet-400/5
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0x33A78BFA), // violet-400/20
                          ),
                        ),
                        child: widget.smartListBuilder != null
                            ? widget.smartListBuilder!(
                                context,
                                query: _smartQuery,
                                onQueryChange: (q) =>
                                    setState(() => _smartQuery = q),
                                onMatchesChange: (m) =>
                                    setState(() => _matchedItems = m),
                                allMedia: _allMedia,
                              )
                            : SmartListBuilder(
                                query: _smartQuery,
                                onQueryChange: (q) =>
                                    setState(() => _smartQuery = q),
                                onMatchesChange: (m) =>
                                    setState(() => _matchedItems = m),
                                allMedia: _allMedia,
                              ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFDA4AF),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),

            // 3. Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xE612151C),
                border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
              child: Row(
                children: [
                  // Left preview
                  Expanded(
                    child: _listType == 'smart'
                        ? Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x268B5CF6),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0x668B5CF6),
                                  ),
                                ),
                                child: Text(
                                  '⚡ ${_matchedItems.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDDD6FE),
                                  ),
                                ),
                              ),
                              if (_matchedItems.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ..._matchedItems.take(5).map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4.0),
                                    child: Container(
                                      width: 24,
                                      height: 36,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0x1AFFFFFF),
                                        ),
                                      ),
                                      child: item.coverUrl != null
                                          ? TsundokuImage(
                                              imageUrl: fullSizeCoverUrl(item.coverUrl!),
                                              fit: BoxFit.cover,
                                              errorWidget: const MediaCoverPlaceholder(),
                                            )
                                          : const MediaCoverPlaceholder(),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Right actions
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text(
                      t.tr('common.cancel'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _nameController.text.trim().isEmpty || _busy
                        ? null
                        : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          accentColor.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _busy
                          ? t.tr('common.saving')
                          : widget.list != null
                              ? t.tr('common.save')
                              : t.tr('views.listCreate'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton({
    required String icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? activeColor : const Color(0x1AFFFFFF),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? activeColor : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
