/// 1:1 port of `mediatracker-ui/src/widgets/layout/Header.svelte`.
///
/// Шапка: фиксированный заголовок (w-56 truncate), строго центрированный
/// поиск (Button secondary w-[28rem]/sm:w-[32rem] + kbd Ctrl K) с офлайн-
/// бейджем и ActivityDropdown справа от поиска; правый кластер — спиннер
/// обновления (networkActivity || activeJobs), селектор языка (PopoverMenu,
/// bottom-end), Power-кнопка.
///
/// Absolute-центрирование через Stack; hover-border accent-line и focus-ring
/// — стили Tailwind-классов, покрываются базовым secondary-вариантом Button.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/jobs_client.dart';
import '../../shared/api/network_activity.dart';
import '../../shared/api/offline_mode.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/ui/button.dart';
import '../../shared/ui/popover_menu.dart';
import 'activity_dropdown.dart';

class Header extends ConsumerWidget {
  final String title;
  final VoidCallback onSearch;
  final VoidCallback? onExitClick;

  const Header({
    super.key,
    required this.title,
    required this.onSearch,
    this.onExitClick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final isOffline = ref.watch(offlineModeProvider).isOffline;
    final isUpdating = ref.watch(networkActivityLoadingProvider) ||
        ref.watch(jobsClientProvider).jobs.where(isActiveJob).isNotEmpty;

    final localeOptions = <PopoverOption<Locale>>[
      for (final l in Locale.values)
        PopoverOption(value: l, label: l.wire.toUpperCase()),
    ];

    return SizedBox(
      height: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              // Заголовок: w-56 min-w-0 shrink-0 truncate.
              SizedBox(
                width: 224, // w-56
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // truncate
                  style: TextStyle(
                    fontSize: 16, // text-base
                    fontWeight: FontWeight.w600, // font-semibold
                    letterSpacing: -0.4, // tracking-tight @ 16px
                    color: th.textPrimary, // text-ink
                  ),
                ),
              ),
              const Spacer(),
              // Правый кластер: [спиннер] -> [язык] -> [power].
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUpdating)
                    Tooltip(
                      message: t.tr('header.updatingData'),
                      child: const SizedBox(
                        width: 36, // size-9
                        height: 36,
                        child: Center(
                          // LoaderCircle size={16} animate-spin; конвенция
                          // Button — CircularProgressIndicator (16px, 2px).
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF818CF8), // --color-accent-soft
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10), // gap-2.5
                  TsundokuPopoverMenu<Locale>(
                    id: 'language-select',
                    options: localeOptions,
                    selected: locale,
                    onSelect: (next) {
                      unawaited(
                          ref.read(i18nProvider.notifier).setLocale(next));
                    },
                    label: t.tr('header.language'),
                    placement: PopoverPlacement.bottomEnd,
                    trigger: (context, ctx) => SizedBox(
                      width: 88, // w-[88px]
                      height: 40, // Button h-10 (md)
                      child: Row(
                        children: [
                          const SizedBox(width: 10), // px-2.5
                          Icon(
                            LucideIcons.languages, // Languages size={15}
                            size: 15,
                            color: th.textMuted, // text-muted
                          ),
                          const Spacer(), // justify-between
                          Text(
                            locale.wire.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w600, // font-semibold
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            LucideIcons.chevronDown, // ChevronDown size={14}
                            size: 14,
                            color: th.textMuted, // text-muted
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ),
                  if (onExitClick != null) ...[
                    const SizedBox(width: 10), // gap-2.5
                    Tooltip(
                      message: t.tr('header.exit'),
                      child: TsundokuButton(
                        variant: ButtonVariant.secondary,
                        size: ButtonSize.icon,
                        iconOnly: true,
                        onPressed: onExitClick,
                        child: Icon(
                          LucideIcons.power, // Power size={16}
                          size: 16,
                          color: th.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Строго центрированный поиск (absolute left-1/2 -translate-x-1/2).
          _CenteredSearch(
            t: t,
            th: th,
            isOffline: isOffline,
            onSearch: onSearch,
          ),
        ],
      ),
    );
  }
}

/// Центральный поиск: офлайн-бейдж + Button secondary 28rem/32rem + kbd
/// Ctrl K; ActivityDropdown прижат справа (absolute left-full ml-2.5).
class _CenteredSearch extends ConsumerWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final bool isOffline;
  final VoidCallback onSearch;

  const _CenteredSearch({
    required this.t,
    required this.th,
    required this.isOffline,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isOffline)
          Padding(
            padding: const EdgeInsets.only(right: 10), // mr-2.5
            child: Tooltip(
              message: t.tr('header.offlineBadgeTooltip'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4), // px-2.5 py-1
                decoration: BoxDecoration(
                  color: const Color(0x26F59E0B), // bg-amber-500/15
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  border: Border.all(
                      color: const Color(0x4DF59E0B)), // border-amber-500/30
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.cloudOff, // CloudOff size={15}
                      size: 15,
                      color: Color(0xFFFBBF24), // text-amber-400
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    Text(
                      t.tr('header.offlineBadgeText'),
                      style: const TextStyle(
                        fontSize: 11, // text-[11px]
                        fontWeight: FontWeight.w600, // font-semibold
                        color: Color(0xFFFBBF24), // text-amber-400
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Кнопка поиска: hidden sm:flex w-[28rem] sm:w-[32rem]; на <640 —
        // icon-only.
        LayoutBuilder(
          builder: (context, _) {
            final compact = MediaQuery.sizeOf(context).width < 640; // sm:
            if (compact) {
              return Tooltip(
                message: t.tr('header.searchTooltip'),
                child: TsundokuButton(
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.icon,
                  iconOnly: true,
                  onPressed: onSearch,
                  child: Icon(
                    LucideIcons.search, // Search size={17}
                    size: 17,
                    color: th.textMuted,
                  ),
                ),
              );
            }
            final width = MediaQuery.sizeOf(context).width >= 1024
                ? 512.0 // sm:w-[32rem] (lg ≥1024)
                : 448.0; // w-[28rem]
            return Tooltip(
              message: t.tr('header.searchTooltip'),
              child: SizedBox(
                width: width,
                height: 40, // Button h-10 (md)
                child: TsundokuButton(
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.md,
                  onPressed: onSearch,
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.search, // Search size={16}
                        size: 16,
                        color: th.textMuted, // text-muted
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            t.tr('header.searchButton'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis, // truncate
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA), // text-zinc-400
                              fontWeight: FontWeight.w400, // font-normal
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2), // px-1.5 py-0.5
                        decoration: BoxDecoration(
                          color: th.bgCanvas, // bg-canvas
                          borderRadius: BorderRadius.circular(4), // rounded
                          border: Border.all(
                              color: Colors.white.withAlpha(20)), // white/[0.08]
                        ),
                        child: Text(
                          'Ctrl K',
                          style: TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w500, // font-medium
                            color: th.textMuted, // text-muted
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // ActivityDropdown справа от поиска (absolute left-full ml-2.5).
        Padding(
          padding: const EdgeInsets.only(left: 10), // ml-2.5
          child: const ActivityDropdown(),
        ),
      ],
    );
  }
}
