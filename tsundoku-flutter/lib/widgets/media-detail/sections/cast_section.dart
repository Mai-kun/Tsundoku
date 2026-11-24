/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/CastSection.svelte`.
///
/// Три режима раскладки cast: сэйю-группировка (аниме, new payload),
/// персонажи (манга), плоский легаси. Portrait-сетка главных (целые ряды —
/// anti-orphan), overflow/secondary строки, reveal-фото сэйю (radial clip),
/// lightbox по клику на фото, PeopleSizeToggle.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/lightbox.dart';
import '../../../shared/ui/tsundoku_image.dart';
import '../../../shared/utils/ui_settings.dart';
import 'people_size_toggle.dart';

class _CharacterCard {
  final String name;
  final String? photoUrl;
  final String? role;
  final bool isMain;

  const _CharacterCard({
    required this.name,
    required this.photoUrl,
    required this.role,
    required this.isMain,
  });
}

class _VoiceEntry {
  final String name;
  final String? photoUrl;
  final List<_CharacterCard> characters;

  const _VoiceEntry({
    required this.name,
    required this.photoUrl,
    required this.characters,
  });
}

class _CastDisplay {
  final String title;
  final bool voiceMode;
  final List<_VoiceEntry> voices;
  final List<_CharacterCard> members;

  const _CastDisplay({
    required this.title,
    required this.voiceMode,
    required this.voices,
    required this.members,
  });
}

class _CastEntry {
  final String key;
  final String name;
  final String? photoUrl;
  final String? voicePhotoUrl;
  final String? role;
  final bool isMain;
  final String? sub;

  const _CastEntry({
    required this.key,
    required this.name,
    required this.photoUrl,
    required this.voicePhotoUrl,
    required this.role,
    required this.isMain,
    required this.sub,
  });
}

/// Секция каста (1-в-1 с CastSection.svelte).
class CastSection extends ConsumerStatefulWidget {
  final MediaDetail media;

  const CastSection({super.key, required this.media});

  @override
  ConsumerState<CastSection> createState() => _CastSectionState();
}

class _CastSectionState extends ConsumerState<CastSection> {
  bool _supportingCollapsed = false;
  String? _revealedVoice;

  static const int _portraitCols = 3;

  List<CastMember> get _cast => widget.media.cast ?? const <CastMember>[];

  String get _categoryKey {
    // Anime live-action types share the anime payload shape.
    final media = widget.media;
    return (media.type == MediaType.tvshow || media.type == MediaType.movie) &&
            (media.isAnime ?? false)
        ? 'anime'
        : media.type.wire;
  }

  bool get _isAnime =>
      (widget.media.type == MediaType.movie ||
          widget.media.type == MediaType.tvshow) &&
      (widget.media.isAnime ?? false);

  bool get _isManga => widget.media.type == MediaType.manga;

  _CastDisplay? get _display {
    final cast = _cast;
    if (cast.isEmpty) return null;
    final t = ref.read(tProvider);

    bool isMainRole(String? raw) => raw?.trim().toUpperCase() == 'MAIN';
    String? roleLabel(String? raw) {
      final value = raw?.trim().toUpperCase();
      if (value == 'MAIN') return t.tr('detail.roleMain');
      if (value == 'SUPPORTING') return t.tr('detail.roleSupporting');
      final trimmed = raw?.trim();
      return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    }

    // Anime with the new payload: group by the Japanese voice actor.
    if (_isAnime && cast.any((member) => member.voiceActorName?.trim().isNotEmpty ?? false)) {
      final voices = <_VoiceEntry>[];
      final byName = <String, _VoiceEntry>{};
      final headless = <_CharacterCard>[];
      for (final member in cast) {
        final character = _CharacterCard(
          name: member.character?.isNotEmpty ?? false
              ? member.character!
              : member.name,
          photoUrl: member.characterImageUrl ?? member.photoUrl,
          role: roleLabel(member.characterRole),
          isMain: isMainRole(member.characterRole),
        );
        final vaName = member.voiceActorName?.trim();
        if (vaName == null || vaName.isEmpty) {
          headless.add(character);
          continue;
        }
        var voice = byName[vaName];
        if (voice == null) {
          voice = _VoiceEntry(
            name: vaName,
            photoUrl: member.voiceActorImageUrl ?? member.photoUrl,
            characters: [],
          );
          byName[vaName] = voice;
          voices.add(voice);
        }
        voice.characters.add(character);
      }
      return _CastDisplay(
        title: t.tr('detail.voiceActorsTitle'),
        voiceMode: true,
        voices: voices,
        members: headless,
      );
    }

    // Manga (и любые payload с чистыми персонажами): карточка на персонажа.
    if (_isManga) {
      return _CastDisplay(
        title: t.tr('detail.charactersTitle'),
        voiceMode: false,
        voices: const [],
        members: [
          for (final member in cast)
            _CharacterCard(
              name: member.character?.isNotEmpty ?? false
                  ? member.character!
                  : member.name,
              photoUrl: member.characterImageUrl ?? member.photoUrl,
              role: roleLabel(member.characterRole),
              isMain: isMainRole(member.characterRole),
            ),
        ],
      );
    }

    // Legacy flat layout: «актёр + сыгранная роль».
    return _CastDisplay(
      title: t.tr('detail.castTitle'),
      voiceMode: false,
      voices: const [],
      members: [
        for (final member in cast)
          _CharacterCard(
            name: member.name,
            photoUrl: member.photoUrl,
            role: member.character,
            isMain: false,
          ),
      ],
    );
  }

  _CastEntry _voiceEntry(
      String voiceName, String? voicePhotoUrl, _CharacterCard character) {
    return _CastEntry(
      key: '$voiceName:${character.name}',
      name: character.name,
      photoUrl: character.photoUrl,
      voicePhotoUrl: voicePhotoUrl,
      role: character.role,
      isMain: character.isMain,
      sub: voiceName,
    );
  }

  _CastEntry _memberEntry(_CharacterCard member, {String? sub}) {
    return _CastEntry(
      key: '${member.name}:${member.photoUrl ?? ''}',
      name: member.name,
      photoUrl: member.photoUrl,
      voicePhotoUrl: null,
      role: member.role,
      isMain: member.isMain,
      // Роль уже видна бейджем; дублирование текстом — шум.
      sub: sub != null && sub != member.role ? sub : null,
    );
  }

  List<_CastEntry> _mainPool(_CastDisplay display) {
    if (display.voiceMode) {
      final entries = <_CastEntry>[];
      for (final voice in display.voices) {
        for (final character in voice.characters) {
          if (character.isMain) {
            entries.add(_voiceEntry(voice.name, voice.photoUrl, character));
          }
        }
      }
      for (final member in display.members) {
        if (member.isMain) entries.add(_memberEntry(member));
      }
      return entries;
    }
    return display.members.where((m) => m.isMain).map((m) {
      final sub = _isManga ? m.role ?? m.name : null;
      return _memberEntry(m, sub: sub);
    }).toList();
  }

  List<_CastEntry> _supportingEntries(_CastDisplay display) {
    final entries = <_CastEntry>[];
    if (display.voiceMode) {
      for (final voice in display.voices) {
        for (final character in voice.characters) {
          if (!character.isMain) {
            entries.add(_voiceEntry(voice.name, voice.photoUrl, character));
          }
        }
      }
    }
    for (final member in display.members) {
      if (!member.isMain) {
        entries.add(_memberEntry(member, sub: member.role));
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final settings = ref.watch(uiSettingsProvider);
    final display = _display;
    if (display == null) return const SizedBox.shrink();

    final large =
        settings.castSizeByCategory[_categoryKey] == PeopleCardSize.large;

    final mainPool = _mainPool(display);
    final portraitCount =
        (mainPool.length ~/ _portraitCols) * _portraitCols;
    final portraitEntries = mainPool.take(portraitCount).toList();
    final overflowEntries = mainPool.skip(portraitEntries.length).toList();
    final supporting = _supportingEntries(display);
    final hasSupporting = supporting.isNotEmpty;
    final hasVoiceActors = display.voiceMode;

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: th.bgSurface, // panel-line
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  display.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.6, // tracking-wider
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
              ),
              if (hasSupporting)
                _CollapseChevron(
                  collapsed: _supportingCollapsed,
                  showLabel: t.tr('detail.showSupporting'),
                  hideLabel: t.tr('detail.hideSupporting'),
                  onTap: () => setState(
                      () => _supportingCollapsed = !_supportingCollapsed),
                ),
              const SizedBox(width: 6), // gap-1.5
              PeopleSizeToggle(category: _categoryKey, block: PeopleBlock.cast),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          if (portraitEntries.isNotEmpty)
            // Portrait-сетка главных: только целые ряды (anti-orphan rule).
            LayoutBuilder(
              builder: (context, constraints) {
                // grid grid-cols-3 gap-3
                final cardWidth = (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12, // gap-3
                  runSpacing: 12,
                  children: [
                    for (final entry in portraitEntries)
                      SizedBox(
                        width: cardWidth,
                        child: _PortraitCard(
                          entry: entry,
                          large: large,
                          th: th,
                          revealed: _revealedVoice == entry.key,
                          onReveal: (revealed) => setState(
                              () => _revealedVoice = revealed ? entry.key : null),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (overflowEntries.isNotEmpty || supporting.isNotEmpty) ...[
            const SizedBox(height: 12), // space-y-3
            if (hasVoiceActors)
              Column(
                children: [
                  for (int i = 0; i < overflowEntries.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withAlpha(13), // divide-white/[0.05]
                      ),
                    _RowEntry(
                      entry: overflowEntries[i],
                      large: large,
                      th: th,
                      isRu: ref.read(i18nProvider).wire == 'ru',
                    ),
                  ],
                  if (!_supportingCollapsed) ...[
                    if (overflowEntries.isNotEmpty)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withAlpha(13), // border-t border-white/[0.05]
                      ),
                    for (int i = 0; i < supporting.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withAlpha(13),
                        ),
                      _RowEntry(
                        entry: supporting[i],
                        large: large,
                        th: th,
                        isRu: ref.read(i18nProvider).wire == 'ru',
                      ),
                    ],
                  ],
                ],
              )
            else
              // Flat payloads (манга, книги): две компактные колонки (grid-cols-1 md:grid-cols-2).
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMd = constraints.maxWidth >= 600;
                  final itemWidth = isMd ? (constraints.maxWidth - 24) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 24, // gap-x-6
                    runSpacing: 8, // gap-y-2
                    children: [
                      for (final entry in overflowEntries)
                        SizedBox(
                          width: itemWidth,
                          child: _RowEntry(
                            entry: entry,
                            large: large,
                            th: th,
                            isRu: ref.read(i18nProvider).wire == 'ru',
                          ),
                        ),
                      if (!_supportingCollapsed)
                        for (final entry in supporting)
                          SizedBox(
                            width: itemWidth,
                            child: _RowEntry(
                              entry: entry,
                              large: large,
                              th: th,
                              isRu: ref.read(i18nProvider).wire == 'ru',
                            ),
                          ),
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// Шеврон сворачивания secondary: голая иконка с rotate-180.
class _CollapseChevron extends StatefulWidget {
  final bool collapsed;
  final String showLabel;
  final String hideLabel;
  final VoidCallback onTap;

  const _CollapseChevron({
    required this.collapsed,
    required this.showLabel,
    required this.hideLabel,
    required this.onTap,
  });

  @override
  State<_CollapseChevron> createState() => _CollapseChevronState();
}

class _CollapseChevronState extends State<_CollapseChevron> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.collapsed ? widget.showLabel : widget.hideLabel,
      child: Semantics(
        button: true,
        label: widget.collapsed ? widget.showLabel : widget.hideLabel,
        toggled: !widget.collapsed, // aria-expanded
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 28, // size-7
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
              ),
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: widget.collapsed ? 0.5 : 0, // rotate-180
                child: Icon(
                  LucideIcons.chevronUp,
                  size: 15,
                  color: _hovered
                      ? Colors.white // hover:text-white
                      : const Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Portrait-карточка главного персонажа: aspect 2/3 + reveal сэйю-фото.
class _PortraitCard extends StatelessWidget {
  final _CastEntry entry;
  final bool large;
  final TsundokuTheme th;
  final bool revealed;
  final void Function(bool revealed) onReveal;

  const _PortraitCard({
    required this.entry,
    required this.large,
    required this.th,
    required this.revealed,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
          color: Colors.white.withAlpha(15), // /[0.06]
        ),
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: 2 / 3, // aspect-[2/3]
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (entry.photoUrl != null && entry.photoUrl!.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        ref
                            .read(lightboxProvider.notifier)
                            .openLightbox(entry.photoUrl, entry.name);
                      },
                      child: TsundokuImage(
                        src: entry.photoUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter, // object-top
                      ),
                    )
                  else
                    Container(
                      color: th.bgSurface.withAlpha(153), // bg-surface/60
                      child: Center(
                        child: Icon(LucideIcons.user,
                            size: 20, color: th.textMuted),
                      ),
                    ),
                  if (entry.voicePhotoUrl != null)
                    // Radial reveal сэйю-фото (clip-circle из угла аватара).
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: revealed ? 1 : 0,
                      child: TsundokuImage(
                        src: entry.voicePhotoUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (entry.voicePhotoUrl != null)
                    Positioned(
                      right: 8, // right-2
                      bottom: 8,
                      child: MouseRegion(
                        onEnter: (_) => onReveal(true),
                        onExit: (_) => onReveal(false),
                        child: GestureDetector(
                          onTap: () {
                            ref
                                .read(lightboxProvider.notifier)
                                .openLightbox(entry.voicePhotoUrl, entry.sub);
                          },
                          child: Container(
                            width: 36, // size-9
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF12151C),
                                  width: 2), // ring-[#12151c]
                            ),
                            child: ClipOval(
                              child: TsundokuImage(
                                src: entry.voicePhotoUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (entry.sub != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        width: 36, // size-9
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: th.bgSurface, // bg-surface
                          border: Border.all(
                              color: const Color(0xFF12151C), width: 2),
                        ),
                        child: Icon(LucideIcons.user,
                            size: 14, color: th.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8), // p-2
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 2, // line-clamp-2
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 13 : 12, // sm:text-[13px] : text-xs
                    height: 1.375, // leading-snug
                    fontWeight: FontWeight.w700, // font-bold
                    color: Colors.white,
                  ),
                ),
                if (entry.sub != null)
                  Text(
                    entry.sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10, // text-[10px]
                      color: th.textMuted, // text-muted
                    ),
                  ),
                if (entry.role != null) ...[
                  const SizedBox(height: 2),
                  _RoleBadge(role: entry.role!, isMain: entry.isMain),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка персонажа/актёра: фото + имя + роль-бейдж (+ сэйю справа).
class _RowEntry extends StatelessWidget {
  final _CastEntry entry;
  final bool large;
  final TsundokuTheme th;
  final bool isRu;

  const _RowEntry({
    required this.entry,
    required this.large,
    required this.th,
    required this.isRu,
  });

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final double photoH = large ? 96 : 52; // h-24 / size-13
    final double photoW = large ? 64 : 52; // w-20 / size-13

    return Padding(
      padding: EdgeInsets.symmetric(vertical: large ? 10 : 8), // py-2.5 / py-2
      child: Row(
        children: [
          if (entry.photoUrl != null && entry.photoUrl!.isNotEmpty)
            GestureDetector(
              onTap: () {
                ref
                    .read(lightboxProvider.notifier)
                    .openLightbox(entry.photoUrl, entry.name);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                child: Container(
                  width: photoW,
                  height: photoH,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withAlpha(26)), // ring-white/10
                  ),
                  child: TsundokuImage(
                    src: entry.photoUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            )
          else
            Container(
              width: photoW,
              height: photoH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(26)),
                color: th.bgSurface.withAlpha(153), // bg-surface/60
              ),
              child: Icon(LucideIcons.user, size: 15, color: th.textMuted),
            ),
          const SizedBox(width: 12), // gap-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 2, // line-clamp-2
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 14 : 12, // text-sm : text-xs
                    height: 1.375, // leading-snug
                    fontWeight: FontWeight.w700, // font-bold
                    color: Colors.white,
                  ),
                ),
                if (entry.role != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4), // mt-1
                    child: _RoleBadge(role: entry.role!, isMain: entry.isMain),
                  ),
              ],
            ),
          ),
          if (entry.sub != null)
            // Balanced pair: сэйю справа с собственным портретом.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      entry.sub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: large ? 14 : 12,
                        height: 1.375,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isRu ? 'сэйю' : 'voice',
                      style: TextStyle(
                        fontSize: 10, // text-[10px]
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: 0.6, // tracking-wider
                        color: th.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12), // gap-3
                if (entry.voicePhotoUrl != null)
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(lightboxProvider.notifier)
                          .openLightbox(entry.voicePhotoUrl, entry.sub);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: photoW,
                        height: photoH,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.white.withAlpha(26)),
                        ),
                        child: TsundokuImage(
                          src: entry.voicePhotoUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: photoW,
                    height: photoH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.white.withAlpha(26)),
                      color: th.bgSurface.withAlpha(153),
                    ),
                    child:
                        Icon(LucideIcons.user, size: 15, color: th.textMuted),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Бейдж роли: MAIN — accent-обработка; остальное — нейтральный.
class _RoleBadge extends StatelessWidget {
  final String role;
  final bool isMain;

  const _RoleBadge({required this.role, required this.isMain});

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final accentSoft = th.accentSoft;
    final accent = th.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 6, vertical: 2), // px-1.5 py-0.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6), // rounded-md
        border: Border.all(
          color: isMain
              ? accent.withAlpha(77) // border-accent/30
              : Colors.white.withAlpha(26), // border-white/10
        ),
        color: isMain
            ? accent.withAlpha(38) // bg-accent/15
            : Colors.white.withAlpha(10), // bg-white/[0.04]
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 10, // text-[10px]
          fontWeight: isMain ? FontWeight.w600 : FontWeight.w500,
          color: isMain
              ? accentSoft // text-accent-soft
              : const Color(0xFF94A3B8), // text-slate-400
        ),
      ),
    );
  }
}
