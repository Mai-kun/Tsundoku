/// 1:1 port of `mediatracker-ui/src/app/tokens.css`.
///
/// Semantic primitives — the single source of truth for surface/border/text/
/// accent colors. `tsundoku_theme.dart` собирает из них `ThemeData`; будущая
/// тема переопределяет только этот блок (аналог `html[data-theme="..."]`).
library;

import 'package:material_ui/material_ui.dart';

/// Группа accent/border/surface/text одного внешнего источника
/// (import-провайдеры + список источников в настройках).
@immutable
class ImportSourceTheme {
  final Color accent;
  /// The accent dimmed for large CTA fills (есть только у MangaLib/SocialLib).
  final Color? accentDim;
  final Color border;
  final Color surface;
  final Color text;

  const ImportSourceTheme({
    required this.accent,
    required this.accentDim,
    required this.border,
    required this.surface,
    required this.text,
  });

  ImportSourceTheme lerpWith(ImportSourceTheme other, double t) =>
      ImportSourceTheme(
        accent: Color.lerp(accent, other.accent, t)!,
        accentDim: accentDim == null && other.accentDim == null
            ? null
            : Color.lerp(accentDim, other.accentDim, t),
        border: Color.lerp(border, other.border, t)!,
        surface: Color.lerp(surface, other.surface, t)!,
        text: Color.lerp(text, other.text, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is ImportSourceTheme &&
      other.accent == accent &&
      other.accentDim == accentDim &&
      other.border == border &&
      other.surface == surface &&
      other.text == text;

  @override
  int get hashCode => Object.hash(accent, accentDim, border, surface, text);
}

/// Каноничные брендовые оттенки бейджей источников (Related-таб, поиск).
@immutable
class BadgeSourceTheme {
  final Color color;
  final Color surface;
  final Color border;
  /// Есть только у Shikimori.
  final Color? borderSubtle;
  final Color? text;

  const BadgeSourceTheme({
    required this.color,
    required this.surface,
    required this.border,
    required this.borderSubtle,
    required this.text,
  });

  BadgeSourceTheme lerpWith(BadgeSourceTheme other, double t) =>
      BadgeSourceTheme(
        color: Color.lerp(color, other.color, t)!,
        surface: Color.lerp(surface, other.surface, t)!,
        border: Color.lerp(border, other.border, t)!,
        borderSubtle: borderSubtle == null && other.borderSubtle == null
            ? null
            : Color.lerp(borderSubtle, other.borderSubtle, t),
        text: text == null && other.text == null
            ? null
            : Color.lerp(text, other.text, t),
      );

  @override
  bool operator ==(Object other) =>
      other is BadgeSourceTheme &&
      other.color == color &&
      other.surface == surface &&
      other.border == border &&
      other.borderSubtle == borderSubtle &&
      other.text == text;

  @override
  int get hashCode => Object.hash(color, surface, border, borderSubtle, text);
}

/// Все CSS-переменные `tokens.css` ([data-theme="obsidian"]) как
/// `ThemeExtension<TsundokuTheme>`.
@immutable
class TsundokuTheme extends ThemeExtension<TsundokuTheme> {
  // --- Surfaces (Steam Deck Dark base) ---
  final Color bgCanvas;
  final Color bgSurface;
  final Color bgCard;
  final Color bgElevated;
  /// Popovers, dialogs and other chrome that must stay fully opaque over posters.
  final Color bgOverlay;
  final Color bgHover;
  final Color bgActive;

  // --- Borders ---
  final Color borderSubtle;
  final Color borderStrong;

  // --- Text ---
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // --- Accent ---
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color accentBright;
  /// Hover step for accent-bright CTAs: one notch lighter, still matte.
  final Color accentBrightHover;

  // --- Status ---
  final Color danger;
  final Color dangerHover;
  final Color dangerSoft;
  final Color dangerText;
  final Color success;
  final Color warning;
  final Color warningText;

  // --- Chart series palette (muted hues, 8+ series distinguishable) ---
  final Color chartIndigo;
  final Color chartCyan;
  final Color chartBlue;
  final Color chartViolet;
  final Color chartPurple;
  final Color chartAmber;
  final Color chartOrange;
  final Color chartYellow;
  final Color chartLime;
  final Color chartGreen;
  final Color chartEmerald;
  final Color chartRose;
  final Color chartPink;

  // --- Source Themes (import providers + settings sources) ---
  final ImportSourceTheme importMangalib;
  final ImportSourceTheme importSociallib;
  final ImportSourceTheme importTmdb;
  final ImportSourceTheme importRawg;
  final ImportSourceTheme importSimkl;
  final ImportSourceTheme importKinopoisk;
  final ImportSourceTheme importImdb;
  final ImportSourceTheme importKitsu;
  final ImportSourceTheme importMangadex;
  final ImportSourceTheme importMangaupdates;
  final ImportSourceTheme importOpenlibrary;
  final ImportSourceTheme importLetterboxd;
  final ImportSourceTheme importGoodreads;
  final ImportSourceTheme importSteam;
  final ImportSourceTheme importAnilist;
  final ImportSourceTheme importShikimori;
  final ImportSourceTheme importCustom;
  final ImportSourceTheme importAnixart;

  // --- External Search & Source Badges ---
  final BadgeSourceTheme badgeAnilist;
  final BadgeSourceTheme badgeSociallib;
  final BadgeSourceTheme badgeShikimori;
  final Color badgeMalText;
  final BadgeSourceTheme badgeMangadex;
  final BadgeSourceTheme badgeMangaupdates;
  final BadgeSourceTheme badgeTmdb;
  final BadgeSourceTheme badgeKitsu;
  final BadgeSourceTheme badgeIgdb;

  const TsundokuTheme({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgCard,
    required this.bgElevated,
    required this.bgOverlay,
    required this.bgHover,
    required this.bgActive,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentBright,
    required this.accentBrightHover,
    required this.danger,
    required this.dangerHover,
    required this.dangerSoft,
    required this.dangerText,
    required this.success,
    required this.warning,
    required this.warningText,
    required this.chartIndigo,
    required this.chartCyan,
    required this.chartBlue,
    required this.chartViolet,
    required this.chartPurple,
    required this.chartAmber,
    required this.chartOrange,
    required this.chartYellow,
    required this.chartLime,
    required this.chartGreen,
    required this.chartEmerald,
    required this.chartRose,
    required this.chartPink,
    required this.importMangalib,
    required this.importSociallib,
    required this.importTmdb,
    required this.importRawg,
    required this.importSimkl,
    required this.importKinopoisk,
    required this.importImdb,
    required this.importKitsu,
    required this.importMangadex,
    required this.importMangaupdates,
    required this.importOpenlibrary,
    required this.importLetterboxd,
    required this.importGoodreads,
    required this.importSteam,
    required this.importAnilist,
    required this.importShikimori,
    required this.importCustom,
    required this.importAnixart,
    required this.badgeAnilist,
    required this.badgeSociallib,
    required this.badgeShikimori,
    required this.badgeMalText,
    required this.badgeMangadex,
    required this.badgeMangaupdates,
    required this.badgeTmdb,
    required this.badgeKitsu,
    required this.badgeIgdb,
  });

  /// Значения `:root` / `[data-theme="obsidian"]` — 1-в-1 из tokens.css.
  static const TsundokuTheme obsidian = TsundokuTheme(
    // --- Surfaces ---
    bgCanvas: Color(0xFF0D0F14),
    bgSurface: Color(0xFF12151C),
    bgCard: Color(0xFF151A26),
    bgElevated: Color(0xFF171B24),
    bgOverlay: Color(0xFF181B24),
    bgHover: Color.fromRGBO(255, 255, 255, 0.06),
    bgActive: Color.fromRGBO(255, 255, 255, 0.1),
    // --- Borders ---
    borderSubtle: Color.fromRGBO(255, 255, 255, 0.06),
    borderStrong: Color.fromRGBO(255, 255, 255, 0.14),
    // --- Text ---
    textPrimary: Color(0xFFF3F4F6),
    textSecondary: Color(0xFFD1D5DB),
    textMuted: Color(0xFF9CA3AF),
    // --- Accent ---
    accent: Color(0xFF473BB8),
    accentHover: Color(0xFF3D32A0),
    accentSoft: Color(0xFFA5B4FC),
    accentBright: Color(0xFF5446CF),
    accentBrightHover: Color(0xFF5F52B8),
    // --- Status ---
    danger: Color(0xFFB92B42),
    dangerHover: Color(0xFFC63349),
    dangerSoft: Color.fromRGBO(185, 43, 66, 0.12),
    dangerText: Color(0xFFFDA4AF),
    success: Color(0xFF228B57),
    warning: Color(0xFFB87C14),
    warningText: Color(0xFFFCD34D),
    // --- Chart series palette ---
    chartIndigo: Color(0xFF6366F1),
    chartCyan: Color(0xFF3D8FA3),
    chartBlue: Color(0xFF4A72B8),
    chartViolet: Color(0xFF7A63C4),
    chartPurple: Color(0xFF8F63C4),
    chartAmber: Color(0xFFC08A3E),
    chartOrange: Color(0xFFC98A5A),
    chartYellow: Color(0xFFB39A3C),
    chartLime: Color(0xFF8FAE4A),
    chartGreen: Color(0xFF7FA63F),
    chartEmerald: Color(0xFF3F8F6B),
    chartRose: Color(0xFFC94F68),
    chartPink: Color(0xFFB85A86),
    // --- Source Themes ---
    importMangalib: ImportSourceTheme(
      accent: Color(0xFFC25E2E),
      accentDim: Color.fromRGBO(194, 94, 46, 0.75),
      border: Color.fromRGBO(194, 94, 46, 0.25),
      surface: Color.fromRGBO(194, 94, 46, 0.08),
      text: Color(0xFFE89A74),
    ),
    importSociallib: ImportSourceTheme(
      accent: Color(0xFFC25E2E),
      accentDim: Color.fromRGBO(194, 94, 46, 0.75),
      border: Color.fromRGBO(194, 94, 46, 0.25),
      surface: Color.fromRGBO(194, 94, 46, 0.08),
      text: Color(0xFFE89A74),
    ),
    importTmdb: ImportSourceTheme(
      accent: Color(0xFF90CEA1),
      accentDim: null,
      border: Color.fromRGBO(144, 206, 161, 0.2),
      surface: Color.fromRGBO(144, 206, 161, 0.05),
      text: Color(0xFFBBF7D0),
    ),
    importRawg: ImportSourceTheme(
      accent: Color(0xFFF87171),
      accentDim: null,
      border: Color.fromRGBO(248, 113, 113, 0.2),
      surface: Color.fromRGBO(248, 113, 113, 0.05),
      text: Color(0xFFFCA5A5),
    ),
    importSimkl: ImportSourceTheme(
      accent: Color(0xFF94B447),
      accentDim: null,
      border: Color.fromRGBO(148, 180, 71, 0.22),
      surface: Color.fromRGBO(148, 180, 71, 0.06),
      text: Color(0xFFC8DC8F),
    ),
    importKinopoisk: ImportSourceTheme(
      accent: Color(0xFFC79438),
      accentDim: null,
      border: Color.fromRGBO(199, 148, 56, 0.22),
      surface: Color.fromRGBO(199, 148, 56, 0.06),
      text: Color(0xFFFCD34D),
    ),
    importImdb: ImportSourceTheme(
      accent: Color(0xFFCFA63E),
      accentDim: null,
      border: Color.fromRGBO(207, 166, 62, 0.22),
      surface: Color.fromRGBO(207, 166, 62, 0.06),
      text: Color(0xFFFDE68A),
    ),
    importKitsu: ImportSourceTheme(
      accent: Color(0xFFE0646C),
      accentDim: null,
      border: Color.fromRGBO(224, 100, 108, 0.22),
      surface: Color.fromRGBO(224, 100, 108, 0.06),
      text: Color(0xFFFDA4AF),
    ),
    importMangadex: ImportSourceTheme(
      accent: Color(0xFFC9603F),
      accentDim: null,
      border: Color.fromRGBO(201, 96, 63, 0.22),
      surface: Color.fromRGBO(201, 96, 63, 0.06),
      text: Color(0xFFE8A28C),
    ),
    importMangaupdates: ImportSourceTheme(
      accent: Color(0xFFA78BFA),
      accentDim: null,
      border: Color.fromRGBO(167, 139, 250, 0.2),
      surface: Color.fromRGBO(167, 139, 250, 0.05),
      text: Color(0xFFC4B5FD),
    ),
    importOpenlibrary: ImportSourceTheme(
      accent: Color(0xFFD6A858),
      accentDim: null,
      border: Color.fromRGBO(214, 168, 88, 0.2),
      surface: Color.fromRGBO(214, 168, 88, 0.05),
      text: Color(0xFFFDE68A),
    ),
    importLetterboxd: ImportSourceTheme(
      accent: Color(0xFF228B57),
      accentDim: null,
      border: Color.fromRGBO(34, 139, 87, 0.25),
      surface: Color.fromRGBO(34, 139, 87, 0.08),
      text: Color(0xFF72D59E),
    ),
    importGoodreads: ImportSourceTheme(
      accent: Color(0xFFD6A858),
      accentDim: null,
      border: Color.fromRGBO(214, 168, 88, 0.2),
      surface: Color.fromRGBO(214, 168, 88, 0.05),
      text: Color(0xFFFDE68A),
    ),
    importSteam: ImportSourceTheme(
      accent: Color(0xFF66C0F4),
      accentDim: null,
      border: Color.fromRGBO(102, 192, 244, 0.2),
      surface: Color.fromRGBO(102, 192, 244, 0.05),
      text: Color(0xFFBAE6FD),
    ),
    importAnilist: ImportSourceTheme(
      accent: Color(0xFF3D8FC9),
      accentDim: null,
      border: Color.fromRGBO(61, 143, 201, 0.22),
      surface: Color.fromRGBO(61, 143, 201, 0.06),
      text: Color(0xFF7DD3FC),
    ),
    importShikimori: ImportSourceTheme(
      accent: Color(0xFF688CE4),
      accentDim: null,
      border: Color.fromRGBO(104, 140, 228, 0.2),
      surface: Color.fromRGBO(104, 140, 228, 0.05),
      text: Color(0xFFC7D2FE),
    ),
    importCustom: ImportSourceTheme(
      accent: Color(0xFF473BB8),
      accentDim: null,
      border: Color.fromRGBO(71, 59, 184, 0.2),
      surface: Color.fromRGBO(88, 68, 224, 0.05),
      text: Color(0xFFA5B4FC),
    ),
    importAnixart: ImportSourceTheme(
      accent: Color(0xFF9A68D0),
      accentDim: null,
      border: Color.fromRGBO(154, 104, 208, 0.25),
      surface: Color.fromRGBO(154, 104, 208, 0.08),
      text: Color(0xFFC9A8EC),
    ),
    // --- External Search & Source Badges ---
    badgeAnilist: BadgeSourceTheme(
      color: Color(0xFF02A9FF),
      surface: Color.fromRGBO(2, 169, 255, 0.15),
      border: Color.fromRGBO(2, 169, 255, 0.3),
      borderSubtle: null,
      text: null,
    ),
    badgeSociallib: BadgeSourceTheme(
      color: Color(0xFFEC4899),
      surface: Color.fromRGBO(236, 72, 153, 0.15),
      border: Color.fromRGBO(236, 72, 153, 0.3),
      borderSubtle: null,
      text: Color(0xFFF472B6),
    ),
    badgeShikimori: BadgeSourceTheme(
      color: Color(0xFF2E51A2),
      surface: Color.fromRGBO(46, 81, 162, 0.2),
      border: Color.fromRGBO(46, 81, 162, 0.4),
      borderSubtle: Color.fromRGBO(46, 81, 162, 0.3),
      text: Color(0xFF688CE4),
    ),
    badgeMalText: Color(0xFF60A5FA),
    badgeMangadex: BadgeSourceTheme(
      color: Color(0xFFFF6740),
      surface: Color.fromRGBO(255, 103, 64, 0.15),
      border: Color.fromRGBO(255, 103, 64, 0.3),
      borderSubtle: null,
      text: null,
    ),
    badgeMangaupdates: BadgeSourceTheme(
      color: Color(0xFF3B82F6),
      surface: Color.fromRGBO(59, 130, 246, 0.2),
      border: Color.fromRGBO(59, 130, 246, 0.3),
      borderSubtle: null,
      text: null,
    ),
    badgeTmdb: BadgeSourceTheme(
      color: Color(0xFF01B4E4),
      surface: Color.fromRGBO(1, 180, 228, 0.15),
      border: Color.fromRGBO(1, 180, 228, 0.3),
      borderSubtle: null,
      text: null,
    ),
    badgeKitsu: BadgeSourceTheme(
      color: Color(0xFFFD755C),
      surface: Color.fromRGBO(253, 117, 92, 0.15),
      border: Color.fromRGBO(253, 117, 92, 0.3),
      borderSubtle: null,
      text: Color(0xFFFB923C),
    ),
    badgeIgdb: BadgeSourceTheme(
      color: Color(0xFF9146FF),
      surface: Color.fromRGBO(145, 70, 255, 0.2),
      border: Color.fromRGBO(145, 70, 255, 0.4),
      borderSubtle: null,
      text: Color(0xFFA855F7),
    ),
  );

  /// Доступные темы (аналог `[data-theme="..."]`); будущая тема добавляется
  /// сюда без изменения потребляемого кода.
  static const Map<String, TsundokuTheme> themes = <String, TsundokuTheme>{
    'obsidian': obsidian,
  };

  /// Per-field copyWith не используется (тема мержится целиком через lerp —
  /// YAGNI); контракт SDK — копия без замен = this.
  @override
  ThemeExtension<TsundokuTheme> copyWith() => this;

  @override
  TsundokuTheme lerp(TsundokuTheme other, double t) {
    if (identical(this, other)) return this;
    if (t == 0.0) return this;
    if (t == 1.0) return other;
    ImportSourceTheme i(ImportSourceTheme a, ImportSourceTheme b) =>
        a.lerpWith(b, t);
    BadgeSourceTheme b(BadgeSourceTheme a, BadgeSourceTheme b2) =>
        a.lerpWith(b2, t);
    return TsundokuTheme(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgOverlay: Color.lerp(bgOverlay, other.bgOverlay, t)!,
      bgHover: Color.lerp(bgHover, other.bgHover, t)!,
      bgActive: Color.lerp(bgActive, other.bgActive, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentBrightHover:
          Color.lerp(accentBrightHover, other.accentBrightHover, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerHover: Color.lerp(dangerHover, other.dangerHover, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      chartIndigo: Color.lerp(chartIndigo, other.chartIndigo, t)!,
      chartCyan: Color.lerp(chartCyan, other.chartCyan, t)!,
      chartBlue: Color.lerp(chartBlue, other.chartBlue, t)!,
      chartViolet: Color.lerp(chartViolet, other.chartViolet, t)!,
      chartPurple: Color.lerp(chartPurple, other.chartPurple, t)!,
      chartAmber: Color.lerp(chartAmber, other.chartAmber, t)!,
      chartOrange: Color.lerp(chartOrange, other.chartOrange, t)!,
      chartYellow: Color.lerp(chartYellow, other.chartYellow, t)!,
      chartLime: Color.lerp(chartLime, other.chartLime, t)!,
      chartGreen: Color.lerp(chartGreen, other.chartGreen, t)!,
      chartEmerald: Color.lerp(chartEmerald, other.chartEmerald, t)!,
      chartRose: Color.lerp(chartRose, other.chartRose, t)!,
      chartPink: Color.lerp(chartPink, other.chartPink, t)!,
      importMangalib: i(importMangalib, other.importMangalib),
      importSociallib: i(importSociallib, other.importSociallib),
      importTmdb: i(importTmdb, other.importTmdb),
      importRawg: i(importRawg, other.importRawg),
      importSimkl: i(importSimkl, other.importSimkl),
      importKinopoisk: i(importKinopoisk, other.importKinopoisk),
      importImdb: i(importImdb, other.importImdb),
      importKitsu: i(importKitsu, other.importKitsu),
      importMangadex: i(importMangadex, other.importMangadex),
      importMangaupdates: i(importMangaupdates, other.importMangaupdates),
      importOpenlibrary: i(importOpenlibrary, other.importOpenlibrary),
      importLetterboxd: i(importLetterboxd, other.importLetterboxd),
      importGoodreads: i(importGoodreads, other.importGoodreads),
      importSteam: i(importSteam, other.importSteam),
      importAnilist: i(importAnilist, other.importAnilist),
      importShikimori: i(importShikimori, other.importShikimori),
      importCustom: i(importCustom, other.importCustom),
      importAnixart: i(importAnixart, other.importAnixart),
      badgeAnilist: b(badgeAnilist, other.badgeAnilist),
      badgeSociallib: b(badgeSociallib, other.badgeSociallib),
      badgeShikimori: b(badgeShikimori, other.badgeShikimori),
      badgeMalText: Color.lerp(badgeMalText, other.badgeMalText, t)!,
      badgeMangadex: b(badgeMangadex, other.badgeMangadex),
      badgeMangaupdates: b(badgeMangaupdates, other.badgeMangaupdates),
      badgeTmdb: b(badgeTmdb, other.badgeTmdb),
      badgeKitsu: b(badgeKitsu, other.badgeKitsu),
      badgeIgdb: b(badgeIgdb, other.badgeIgdb),
    );
  }

  /// Доступ к теме по цепочке `Theme.of(context).extension<TsundokuTheme>()!`.
  static TsundokuTheme of(BuildContext context) =>
      Theme.of(context).extension<TsundokuTheme>() ?? obsidian;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TsundokuTheme &&
        other.bgCanvas == bgCanvas &&
        other.bgSurface == bgSurface &&
        other.bgCard == bgCard &&
        other.bgElevated == bgElevated &&
        other.bgOverlay == bgOverlay &&
        other.bgHover == bgHover &&
        other.bgActive == bgActive &&
        other.borderSubtle == borderSubtle &&
        other.borderStrong == borderStrong &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textMuted == textMuted &&
        other.accent == accent &&
        other.accentHover == accentHover &&
        other.accentSoft == accentSoft &&
        other.accentBright == accentBright &&
        other.accentBrightHover == accentBrightHover &&
        other.danger == danger &&
        other.dangerHover == dangerHover &&
        other.dangerSoft == dangerSoft &&
        other.dangerText == dangerText &&
        other.success == success &&
        other.warning == warning &&
        other.warningText == warningText &&
        other.chartIndigo == chartIndigo &&
        other.chartCyan == chartCyan &&
        other.chartBlue == chartBlue &&
        other.chartViolet == chartViolet &&
        other.chartPurple == chartPurple &&
        other.chartAmber == chartAmber &&
        other.chartOrange == chartOrange &&
        other.chartYellow == chartYellow &&
        other.chartLime == chartLime &&
        other.chartGreen == chartGreen &&
        other.chartEmerald == chartEmerald &&
        other.chartRose == chartRose &&
        other.chartPink == chartPink &&
        other.importMangalib == importMangalib &&
        other.importSociallib == importSociallib &&
        other.importTmdb == importTmdb &&
        other.importRawg == importRawg &&
        other.importSimkl == importSimkl &&
        other.importKinopoisk == importKinopoisk &&
        other.importImdb == importImdb &&
        other.importKitsu == importKitsu &&
        other.importMangadex == importMangadex &&
        other.importMangaupdates == importMangaupdates &&
        other.importOpenlibrary == importOpenlibrary &&
        other.importLetterboxd == importLetterboxd &&
        other.importGoodreads == importGoodreads &&
        other.importSteam == importSteam &&
        other.importAnilist == importAnilist &&
        other.importShikimori == importShikimori &&
        other.importCustom == importCustom &&
        other.importAnixart == importAnixart &&
        other.badgeAnilist == badgeAnilist &&
        other.badgeSociallib == badgeSociallib &&
        other.badgeShikimori == badgeShikimori &&
        other.badgeMalText == badgeMalText &&
        other.badgeMangadex == badgeMangadex &&
        other.badgeMangaupdates == badgeMangaupdates &&
        other.badgeTmdb == badgeTmdb &&
        other.badgeKitsu == badgeKitsu &&
        other.badgeIgdb == badgeIgdb;
  }

  @override
  int get hashCode => Object.hash(
      // Object.hash принимает до 20 аргументов — группируем вложенно.
      Object.hash(bgCanvas, bgSurface, bgCard, bgElevated, bgOverlay, bgHover,
          bgActive, borderSubtle, borderStrong, textPrimary, textSecondary,
          textMuted, accent, accentHover, accentSoft, accentBright,
          accentBrightHover, danger, dangerHover, dangerSoft),
      Object.hash(dangerText, success, warning, warningText, chartIndigo,
          chartCyan, chartBlue, chartViolet, chartPurple, chartAmber,
          chartOrange, chartYellow, chartLime, chartGreen, chartEmerald,
          chartRose, chartPink, importMangalib, importSociallib, importTmdb),
      Object.hash(importRawg, importSimkl, importKinopoisk, importImdb,
          importKitsu, importMangadex, importMangaupdates, importOpenlibrary,
          importLetterboxd, importGoodreads, importSteam, importAnilist,
          importShikimori, importCustom, importAnixart, badgeAnilist,
          badgeSociallib, badgeShikimori, badgeMalText, badgeMangadex),
      Object.hash(badgeMangaupdates, badgeTmdb, badgeKitsu, badgeIgdb));
}
