import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/TastePersonaCard.svelte`.
///
/// Карточка «Архетип вкуса»:
/// - Градиентный фон с атмосферными размытыми свечениями
/// - Большая иконка архетипа в полупрозрачном контейнере
/// - Название и подробное описание архетипа (с локализацией)
/// - Чипы ключевых черт характера
class TastePersonaCard extends ConsumerWidget {
  final TastePersona persona;

  const TastePersonaCard({
    super.key,
    required this.persona,
  });

  static IconData _getPersonaIcon(String icon) {
    switch (icon) {
      case 'critic':
        return LucideIcons.scale;
      case 'enthusiast':
        return LucideIcons.sparkles;
      case 'perfectionist':
        return LucideIcons.listChecks;
      case 'tsundoku_master':
        return LucideIcons.boxes;
      case 'manga_reader':
        return LucideIcons.bookOpen;
      case 'otaku':
        return LucideIcons.tv;
      case 'gamer':
        return LucideIcons.gamepad2;
      case 'bookworm':
        return LucideIcons.bookmark;
      case 'cinephile':
        return LucideIcons.film;
      case 'serial_binger':
        return LucideIcons.clapperboard;
      case 'dark_philosopher':
        return LucideIcons.compass;
      case 'cozy_hedonist':
        return LucideIcons.heart;
      case 'action_junkie':
        return LucideIcons.flame;
      case 'visionary':
        return LucideIcons.compass;
      case 'omnivore':
        return LucideIcons.layers;
      case 'archivist':
        return LucideIcons.archive;
      default:
        return LucideIcons.sparkles;
    }
  }

  static const _knownPersonas = {
    'action_junkie',
    'archivist',
    'bookworm',
    'cinephile',
    'cozy_hedonist',
    'critic',
    'dark_philosopher',
    'enthusiast',
    'gamer',
    'manga_reader',
    'omnivore',
    'otaku',
    'perfectionist',
    'serial_binger',
    'tsundoku_master',
    'visionary',
  };

  static String _traitLabel(I18nDictionary t, String trait) {
    try {
      return t.tr('stats.taste.traits.$trait');
    } on ArgumentError {
      return trait;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final isKnown = _knownPersonas.contains(persona.icon);
    final title = isKnown
        ? t.tr('stats.taste.personas.${persona.icon}.title')
        : persona.title;
    final description = isKnown
        ? t.tr('stats.taste.personas.${persona.icon}.description')
        : persona.description;
    final traits = isKnown
        ? t.tl('stats.taste.personas.${persona.icon}.traits')
        : persona.traits.map((trait) => _traitLabel(t, trait)).toList();

    final iconData = _getPersonaIcon(persona.icon);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
          color: theme.accent.withAlpha(64), // border-accent-bright/25
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.accent.withAlpha(64), // from-accent-bright/25
            const Color(0xFF151A26), // via-[#151a26]
            const Color(0xFF151A26), // to-[#151a26]
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Размытые декоративные свечения
          Positioned(
            top: -64, // -top-16
            right: -64, // -right-16
            width: 224, // size-56
            height: 224,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.accent.withAlpha(77), // bg-accent-bright/30
                      blurRadius: 96,
                      spreadRadius: 32,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80, // -bottom-20
            left: -40, // -left-10
            width: 160, // size-40
            height: 160,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1AFBBF24), // bg-amber-400/10
                      blurRadius: 96,
                      spreadRadius: 32,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Основной контент
          Padding(
            padding: const EdgeInsets.all(24), // p-6
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSm = constraints.maxWidth >= 640;

                final iconBox = Container(
                  width: 80, // size-20
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.accent.withAlpha(77), // bg-accent-bright/30
                    borderRadius: BorderRadius.circular(16), // rounded-2xl
                    border: Border.all(
                      color: Colors.white.withAlpha(26), // ring-white/10
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    iconData,
                    size: 40, // size-10
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                );

                final details = Column(
                  crossAxisAlignment: isSm
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Text(
                      t.tr('stats.taste.personaBadge').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: 1.2, // tracking-widest
                        color: Color(0xFFA5B4FC), // text-[#a5b4fc]
                      ),
                    ),
                    const SizedBox(height: 4), // mt-1
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24, // text-2xl
                        fontWeight: FontWeight.bold, // font-bold
                        letterSpacing: -0.6, // tracking-tight
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8), // mt-2
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 672), // max-w-2xl
                      child: Text(
                        description,
                        textAlign: isSm ? TextAlign.left : TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14, // text-sm
                          height: 1.625, // leading-relaxed
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                    ),
                    const SizedBox(height: 16), // mt-4
                    Wrap(
                      spacing: 8, // gap-2
                      runSpacing: 8,
                      alignment:
                          isSm ? WrapAlignment.start : WrapAlignment.center,
                      children: [
                        for (final trait in traits)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ), // px-3 py-1
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(13), // bg-white/5
                              border: Border.all(
                                color: Colors.white.withAlpha(26), // border-white/10
                              ),
                              borderRadius: BorderRadius.circular(9999), // rounded-full
                            ),
                            child: Text(
                              trait,
                              style: const TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w500, // font-medium
                                color: Color(0xFFE2E8F0), // text-slate-200
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );

                if (isSm) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconBox,
                      const SizedBox(width: 20), // gap-5
                      Expanded(child: details),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      iconBox,
                      const SizedBox(height: 20), // gap-5
                      details,
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
