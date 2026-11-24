/// 1:1 port of `mediatracker-ui/src/features/settings/SettingsModal.svelte` (Tab: "apiTokens").
///
/// Вкладка «API-токены»:
/// - Список активных персональных API токенов (getApiTokens).
/// - Создание нового токена с опциональным сроком жизни (createApiToken).
/// - Модалка однократного показа созданного токена с копированием в буфер.
/// - Отзыв токена с подтверждением (revokeApiToken).
/// - Ссылка на /api/docs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/dtos.dart';
import '../../../shared/ui/text_field.dart';
import '../../../shared/ui/toast.dart';

class ApiTokensTab extends ConsumerStatefulWidget {
  const ApiTokensTab({super.key});

  @override
  ConsumerState<ApiTokensTab> createState() => _ApiTokensTabState();
}

class _ApiTokensTabState extends ConsumerState<ApiTokensTab> {
  List<ApiTokenSummary> _tokens = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTokens());
  }

  void _toast({
    required String title,
    required String description,
    ToastType type = ToastType.info,
  }) {
    ref.read(toastStoreProvider.notifier).show(
          ToastOptions(title: title, description: description, type: type),
        );
  }

  Future<void> _loadTokens() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(apiClientProvider).getApiTokens();
      if (mounted) setState(() => _tokens = res);
    } catch (_) {
      // Keep empty if failed
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String isoString) {
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)}';
  }

  Future<void> _showCreateTokenDialog(I18nDictionary t) async {
    final nameController = TextEditingController();
    final daysController = TextEditingController();
    bool isSubmitting = false;
    final theme = TsundokuTheme.of(context);

    final res = await showDialog<CreateApiTokenResponse?>(
      context: context,
      barrierColor: const Color(0xCC090B10),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isNameValid = nameController.text.trim().isNotEmpty;

          return Dialog(
            backgroundColor: const Color(0xFF151A26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.accent.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(LucideIcons.key, size: 20, color: theme.accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.tr('settingsModal.apiTokens.modalTitle'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.tr('settingsModal.apiTokens.description'),
                                style: TextStyle(fontSize: 11, color: theme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name input
                    RichText(
                      text: TextSpan(
                        text: t.tr('settingsModal.apiTokens.nameLabel'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textSecondary),
                        children: const [
                          TextSpan(text: ' *', style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: nameController,
                      onChanged: (_) => setDialogState(() {}),
                      placeholder: t.tr('settingsModal.apiTokens.namePlaceholder'),
                    ),
                    const SizedBox(height: 14),

                    // Expiration days input
                    Text(
                      t.tr('settingsModal.apiTokens.expiresInDaysLabel'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TsundokuTextField(
                      controller: daysController,
                      keyboardType: TextInputType.number,
                      placeholder: t.tr('settingsModal.apiTokens.expiresInDaysPlaceholder'),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSubmitting ? null : () => Navigator.of(dialogCtx).pop(null),
                          child: Text(
                            t.tr('settingsModal.apiTokens.cancel'),
                            style: TextStyle(color: theme.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: (!isNameValid || isSubmitting)
                              ? null
                              : () async {
                                  setDialogState(() => isSubmitting = true);
                                  try {
                                    final days = int.tryParse(daysController.text.trim());
                                    final response = await ref.read(apiClientProvider).createApiToken(
                                          nameController.text.trim(),
                                          expiresInDays: days,
                                        );
                                    if (context.mounted) {
                                      Navigator.of(dialogCtx).pop(response);
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSubmitting = false);
                                    _toast(
                                      title: t.tr('toast.actionFailed'),
                                      description: e.toString(),
                                      type: ToastType.error,
                                    );
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(LucideIcons.plus, size: 14),
                          label: Text(
                            isSubmitting
                                ? t.tr('settingsModal.apiTokens.generating')
                                : t.tr('settingsModal.apiTokens.generateSubmit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (res != null) {
      await _loadTokens();
      if (mounted) {
        await _showTokenRevealDialog(res, t);
      }
    }
  }

  Future<void> _showTokenRevealDialog(CreateApiTokenResponse token, I18nDictionary t) async {
    bool hasCopied = false;
    final theme = TsundokuTheme.of(context);

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC090B10),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF151A26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(LucideIcons.shieldCheck, size: 22, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                token.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.tr('settingsModal.apiTokens.modalTitle'),
                                style: TextStyle(fontSize: 12, color: theme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Amber warning box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.withAlpha(70)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.triangleAlert, size: 18, color: Colors.amber),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.tr('settingsModal.apiTokens.warningTitle'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.tr('settingsModal.apiTokens.warningText'),
                                  style: const TextStyle(fontSize: 11, height: 1.35, color: Color(0xFFFDE68A)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Raw Token Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(70),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withAlpha(25)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              token.rawToken,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () async {
                              await platformService.copyText(token.rawToken);
                              setDialogState(() => hasCopied = true);
                            },
                            icon: Icon(hasCopied ? LucideIcons.check : LucideIcons.copy, size: 13),
                            label: Text(
                              hasCopied
                                  ? t.tr('settingsModal.apiTokens.copied')
                                  : t.tr('settingsModal.apiTokens.copyToken'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.textPrimary,
                          side: BorderSide(color: theme.borderSubtle),
                        ),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: Text(t.tr('settingsModal.apiTokens.closeModal')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleRevokeToken(ApiTokenSummary token, I18nDictionary t) async {
    final theme = TsundokuTheme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC090B10),
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF151A26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(LucideIcons.triangleAlert, size: 20, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.tr('settingsModal.apiTokens.revokeConfirmTitle'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.tr('settingsModal.apiTokens.revokeConfirmText'),
                            style: TextStyle(fontSize: 12, height: 1.4, color: theme.textMuted),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.bgSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withAlpha(20)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${token.name}: ',
                                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                                ),
                                Text(
                                  '${token.tokenPrefix}••••••••',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFA5B4FC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(false),
                      child: Text(
                        t.tr('settingsModal.apiTokens.cancel'),
                        style: TextStyle(color: theme.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(dialogCtx).pop(true),
                      icon: const Icon(LucideIcons.trash2, size: 14),
                      label: Text(t.tr('settingsModal.apiTokens.revokeButton')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(apiClientProvider).revokeApiToken(token.id);
        _toast(
          title: t.tr('settingsModal.apiTokens.revokedToast'),
          description: t.tr('toast.descSaved'),
          type: ToastType.success,
        );
        await _loadTokens();
      } catch (e) {
        _toast(
          title: t.tr('toast.actionFailed'),
          description: e.toString(),
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme = TsundokuTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('settingsModal.apiTokens.title'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.tr('settingsModal.apiTokens.description'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.textSecondary,
                        side: BorderSide(color: theme.borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => platformService.openExternalUrl('/api/docs'),
                      icon: const Icon(LucideIcons.externalLink, size: 13),
                      label: Text(
                        t.tr('settingsModal.apiTokens.docsButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_tokens.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showCreateTokenDialog(t),
                        icon: const Icon(LucideIcons.plus, size: 14),
                        label: Text(
                          t.tr('settingsModal.apiTokens.createButton'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0x14FFFFFF)),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (_tokens.isEmpty) ...[
              // Empty State
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.key, size: 22, color: theme.accent),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t.tr('settingsModal.apiTokens.emptyState'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.tr('settingsModal.apiTokens.description'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: theme.textMuted),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showCreateTokenDialog(t),
                      icon: const Icon(LucideIcons.plus, size: 14),
                      label: Text(
                        t.tr('settingsModal.apiTokens.createButton'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Tokens List
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tokens.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final token = _tokens[index];

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    token.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(50),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.white.withAlpha(15)),
                                    ),
                                    child: Text(
                                      '${token.tokenPrefix}••••••••',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: Color(0xFFA5B4FC),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${t.tr('settingsModal.apiTokens.created')}: ${_formatDate(token.createdAt)}',
                                    style: TextStyle(fontSize: 11, color: theme.textMuted),
                                  ),
                                  Text('•', style: TextStyle(fontSize: 11, color: theme.textMuted)),
                                  Text(
                                    '${t.tr('settingsModal.apiTokens.lastUsed')}: ${token.lastUsedAt != null ? _formatDate(token.lastUsedAt!) : t.tr('settingsModal.apiTokens.neverUsed')}',
                                    style: TextStyle(fontSize: 11, color: theme.textSecondary),
                                  ),
                                  if (token.expiresAt != null) ...[
                                    Text('•', style: TextStyle(fontSize: 11, color: theme.textMuted)),
                                    Text(
                                      '${t.tr('settingsModal.apiTokens.expiresAt')}: ${_formatDate(token.expiresAt!)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.amber),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 16, color: Color(0xFFF87171)),
                          tooltip: t.tr('settingsModal.apiTokens.revokeButton'),
                          onPressed: () => _handleRevokeToken(token, t),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
