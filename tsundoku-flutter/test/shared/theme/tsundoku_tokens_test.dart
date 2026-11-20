import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

/// Тест 1-в-1 соответствия [TsundokuTheme.obsidian] значениям `tokens.css`.
void main() {
  Color rgb(int r, int g, int b, [double a = 1.0]) =>
      Color.fromRGBO(r, g, b, a);

  group('TsundokuTheme.obsidian — значения 1-в-1 из tokens.css', () {
    final t = TsundokuTheme.obsidian;
    test('surfaces', () {
      expect(t.bgCanvas, rgb(13, 15, 20)); // #0d0f14
      expect(t.bgSurface, rgb(18, 21, 28)); // #12151c
      expect(t.bgCard, rgb(21, 26, 38)); // #151a26
      expect(t.bgElevated, rgb(23, 27, 36)); // #171b24
      expect(t.bgOverlay, rgb(24, 27, 36)); // #181b24
      expect(t.bgHover, rgb(255, 255, 255, 0.06));
      expect(t.bgActive, rgb(255, 255, 255, 0.1));
    });

    test('borders + text', () {
      expect(t.borderSubtle, rgb(255, 255, 255, 0.06));
      expect(t.borderStrong, rgb(255, 255, 255, 0.14));
      expect(t.textPrimary, rgb(243, 244, 246)); // #f3f4f6
      expect(t.textSecondary, rgb(209, 213, 219)); // #d1d5db
      expect(t.textMuted, rgb(156, 163, 175)); // #9ca3af
    });

    test('accent', () {
      expect(t.accent, rgb(71, 59, 184)); // #473bb8
      expect(t.accentHover, rgb(61, 50, 160)); // #3d32a0
      expect(t.accentSoft, rgb(165, 180, 252)); // #a5b4fc
      expect(t.accentBright, rgb(84, 70, 207)); // #5446cf
      expect(t.accentBrightHover, rgb(95, 82, 184)); // #5f52b8
    });

    test('status', () {
      expect(t.danger, rgb(185, 43, 66)); // #b92b42
      expect(t.dangerHover, rgb(198, 51, 73)); // #c63349
      expect(t.dangerSoft, rgb(185, 43, 66, 0.12));
      expect(t.dangerText, rgb(253, 164, 175)); // #fda4af
      expect(t.success, rgb(34, 139, 87)); // #228b57
      expect(t.warning, rgb(184, 124, 20)); // #b87c14
      expect(t.warningText, rgb(252, 211, 77)); // #fcd34d
    });

    test('chart palette (13 серий, приглушённые)', () {
      expect(t.chartIndigo, rgb(99, 102, 241)); // #6366f1
      expect(t.chartCyan, rgb(61, 143, 163)); // #3d8fa3
      expect(t.chartBlue, rgb(74, 114, 184)); // #4a72b8
      expect(t.chartViolet, rgb(122, 99, 196)); // #7a63c4
      expect(t.chartPurple, rgb(143, 99, 196)); // #8f63c4
      expect(t.chartAmber, rgb(192, 138, 62)); // #c08a3e
      expect(t.chartOrange, rgb(201, 138, 90)); // #c98a5a
      expect(t.chartYellow, rgb(179, 154, 60)); // #b39a3c
      expect(t.chartLime, rgb(143, 174, 74)); // #8fae4a
      expect(t.chartGreen, rgb(127, 166, 63)); // #7fa63f
      expect(t.chartEmerald, rgb(63, 143, 107)); // #3f8f6b
      expect(t.chartRose, rgb(201, 79, 104)); // #c94f68
      expect(t.chartPink, rgb(184, 90, 134)); // #b85a86
    });

    test('import source themes (18 источников)', () {
      // MangaLib / SocialLib (Matte terracotta) — единственные с accentDim.
      expect(t.importMangalib.accent, rgb(194, 94, 46)); // #c25e2e
      expect(t.importMangalib.accentDim, rgb(194, 94, 46, 0.75));
      expect(t.importMangalib.border, rgb(194, 94, 46, 0.25));
      expect(t.importMangalib.surface, rgb(194, 94, 46, 0.08));
      expect(t.importMangalib.text, rgb(232, 154, 116)); // #e89a74
      expect(t.importSociallib, t.importMangalib);

      expect(t.importTmdb.accent, rgb(144, 206, 161)); // #90cea1
      expect(t.importTmdb.accentDim, isNull);
      expect(t.importTmdb.text, rgb(187, 247, 208)); // #bbf7d0

      expect(t.importRawg.accent, rgb(248, 113, 113)); // #f87171
      expect(t.importRawg.text, rgb(252, 165, 165)); // #fca5a5
      expect(t.importSimkl.accent, rgb(148, 180, 71)); // #94b447
      expect(t.importKinopoisk.accent, rgb(199, 148, 56)); // #c79438
      expect(t.importImdb.accent, rgb(207, 166, 62)); // #cfa63e
      expect(t.importKitsu.accent, rgb(224, 100, 108)); // #e0646c
      expect(t.importMangadex.accent, rgb(201, 96, 63)); // #c9603f
      expect(t.importMangaupdates.accent, rgb(167, 139, 250)); // #a78bfa
      expect(t.importOpenlibrary.accent, rgb(214, 168, 88)); // #d6a858
      expect(t.importLetterboxd.accent, rgb(34, 139, 87)); // #228b57
      expect(t.importLetterboxd.border, rgb(34, 139, 87, 0.25));
      expect(t.importGoodreads.accent, rgb(214, 168, 88));
      expect(t.importSteam.accent, rgb(102, 192, 244)); // #66c0f4
      expect(t.importAnilist.accent, rgb(61, 143, 201)); // #3d8fc9
      expect(t.importAnilist.text, rgb(125, 211, 252)); // #7dd3fc
      expect(t.importShikimori.accent, rgb(104, 140, 228)); // #688ce4
      expect(t.importCustom.accent, rgb(71, 59, 184)); // #473bb8
      expect(t.importCustom.surface, rgb(88, 68, 224, 0.05));
      expect(t.importAnixart.accent, rgb(154, 104, 208)); // #9a68d0
      expect(t.importAnixart.border, rgb(154, 104, 208, 0.25));
    });

    test('badge palette (брендовые оттенки бейджей)', () {
      expect(t.badgeAnilist.color, rgb(2, 169, 255)); // #02a9ff
      expect(t.badgeAnilist.surface, rgb(2, 169, 255, 0.15));
      expect(t.badgeAnilist.border, rgb(2, 169, 255, 0.3));

      expect(t.badgeSociallib.color, rgb(236, 72, 153)); // #ec4899
      expect(t.badgeSociallib.text, rgb(244, 114, 182)); // #f472b6

      expect(t.badgeShikimori.color, rgb(46, 81, 162)); // #2e51a2
      expect(t.badgeShikimori.borderSubtle, rgb(46, 81, 162, 0.3));
      expect(t.badgeShikimori.text, rgb(104, 140, 228)); // #688ce4
      expect(t.badgeMalText, rgb(96, 165, 250)); // #60a5fa

      expect(t.badgeMangadex.color, rgb(255, 103, 64)); // #ff6740
      expect(t.badgeMangaupdates.color, rgb(59, 130, 246)); // #3b82f6
      expect(t.badgeTmdb.color, rgb(1, 180, 228)); // #01b4e4
      expect(t.badgeKitsu.color, rgb(253, 117, 92)); // #fd755c
      expect(t.badgeKitsu.text, rgb(251, 146, 60)); // #fb923c
      expect(t.badgeIgdb.color, rgb(145, 70, 255)); // #9146ff
      expect(t.badgeIgdb.text, rgb(168, 85, 247)); // #a855f7
    });
  });

  group('ThemeExtension механика', () {
    test('lerp(0) → this, lerp(1) → other, lerp(0.5) — середина', () {
      final a = TsundokuTheme.obsidian;
      final other = TsundokuTheme(
        bgCanvas: const Color(0xFF000000),
        bgSurface: const Color(0xFF000000),
        bgCard: const Color(0xFF000000),
        bgElevated: const Color(0xFF000000),
        bgOverlay: const Color(0xFF000000),
        bgHover: const Color(0x00000000),
        bgActive: const Color(0x00000000),
        borderSubtle: const Color(0x00000000),
        borderStrong: const Color(0x00000000),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFF000000),
        textMuted: const Color(0xFF000000),
        accent: const Color(0xFF000000),
        accentHover: const Color(0xFF000000),
        accentSoft: const Color(0xFF000000),
        accentBright: const Color(0xFF000000),
        accentBrightHover: const Color(0xFF000000),
        danger: const Color(0xFF000000),
        dangerHover: const Color(0xFF000000),
        dangerSoft: const Color(0x00000000),
        dangerText: const Color(0xFF000000),
        success: const Color(0xFF000000),
        warning: const Color(0xFF000000),
        warningText: const Color(0xFF000000),
        chartIndigo: const Color(0xFF000000),
        chartCyan: const Color(0xFF000000),
        chartBlue: const Color(0xFF000000),
        chartViolet: const Color(0xFF000000),
        chartPurple: const Color(0xFF000000),
        chartAmber: const Color(0xFF000000),
        chartOrange: const Color(0xFF000000),
        chartYellow: const Color(0xFF000000),
        chartLime: const Color(0xFF000000),
        chartGreen: const Color(0xFF000000),
        chartEmerald: const Color(0xFF000000),
        chartRose: const Color(0xFF000000),
        chartPink: const Color(0xFF000000),
        importMangalib: a.importMangalib,
        importSociallib: a.importSociallib,
        importTmdb: a.importTmdb,
        importRawg: a.importRawg,
        importSimkl: a.importSimkl,
        importKinopoisk: a.importKinopoisk,
        importImdb: a.importImdb,
        importKitsu: a.importKitsu,
        importMangadex: a.importMangadex,
        importMangaupdates: a.importMangaupdates,
        importOpenlibrary: a.importOpenlibrary,
        importLetterboxd: a.importLetterboxd,
        importGoodreads: a.importGoodreads,
        importSteam: a.importSteam,
        importAnilist: a.importAnilist,
        importShikimori: a.importShikimori,
        importCustom: a.importCustom,
        importAnixart: a.importAnixart,
        badgeAnilist: a.badgeAnilist,
        badgeSociallib: a.badgeSociallib,
        badgeShikimori: a.badgeShikimori,
        badgeMalText: a.badgeMalText,
        badgeMangadex: a.badgeMangadex,
        badgeMangaupdates: a.badgeMangaupdates,
        badgeTmdb: a.badgeTmdb,
        badgeKitsu: a.badgeKitsu,
        badgeIgdb: a.badgeIgdb,
      );

      expect(a.lerp(other, 0), a);
      expect(a.lerp(other, 1), other);
      // Flutter 3.50: компоненты Color — double, lerp(0.5) даёт точные половины.
      bool channelClose(Color a, Color b) =>
          (a.r - b.r).abs() * 255 <= 1 &&
          (a.g - b.g).abs() * 255 <= 1 &&
          (a.b - b.b).abs() * 255 <= 1;
      final mid = a.lerp(other, 0.5);
      // #0d0f14 ↔ #000000: половина = (6.5, 7.5, 10).
      expect(channelClose(mid.bgCanvas, rgb(7, 8, 10)), isTrue,
          reason: 'bgCanvas lerp(0.5) ≈ rgb(6.5, 7.5, 10)');
      // #f3f4f6 ↔ #ffffff: половина = (249.0, 249.5, 250.5).
      expect(channelClose(mid.textPrimary, rgb(249, 250, 251)), isTrue,
          reason: 'textPrimary lerp(0.5) ≈ rgb(249, 249.5, 250.5)');
    });

    test('== и hashCode: одна тема равна самой себе', () {
      final a = TsundokuTheme.obsidian;
      final same = TsundokuTheme.themes['obsidian'];
      expect(a, same);
      expect(a.hashCode, same.hashCode);
    });

    test('themes содержит obsidian (аналог [data-theme])', () {
      expect(TsundokuTheme.themes.keys, contains('obsidian'));
    });

    test('copyWith без замен — копия (контракт SDK)', () {
      expect(TsundokuTheme.obsidian.copyWith(), TsundokuTheme.obsidian);
    });

    test('ImportSourceTheme lerp и ==', () {
      final black = const ImportSourceTheme(
        accent: Color(0xFF000000),
        accentDim: null,
        border: Color(0x00000000),
        surface: Color(0x00000000),
        text: Color(0xFF000000),
      );
      final mid = TsundokuTheme.obsidian.importTmdb.lerpWith(black, 0.5);
      // #90cea1 ↔ #000000: половина ≈ (72, 103, 80.5).
      bool channelClose(Color a, Color b) =>
          (a.r - b.r).abs() * 255 <= 1 &&
          (a.g - b.g).abs() * 255 <= 1 &&
          (a.b - b.b).abs() * 255 <= 1;
      expect(channelClose(mid.accent, rgb(72, 103, 80)), isTrue);
      expect(mid.accentDim, isNull); // null ↔ null остаётся null.
      expect(TsundokuTheme.obsidian.importTmdb == TsundokuTheme.obsidian.importTmdb, isTrue);
    });

    test('BadgeSourceTheme lerp сохраняет nullable borderSubtle/text', () {
      final mid = TsundokuTheme.obsidian.badgeShikimori
          .lerpWith(TsundokuTheme.obsidian.badgeShikimori, 0.5);
      expect(mid.borderSubtle, TsundokuTheme.obsidian.badgeShikimori.borderSubtle);
      expect(mid.text, TsundokuTheme.obsidian.badgeShikimori.text);
    });
  });
}
