/// 1:1 port of `mediatracker-ui/src/app/app.css`.
///
/// Здесь живут:
/// - [TsundokuPalette] — статические константы `@theme static`-блока app.css
///   (значения, не ссылающиеся на tokens.css);
/// - кривые/длительности анимаций (`--ease-tap`, popover/dialog/view-fade);
/// - [buildTsundokuTheme] — сборка `ThemeData` из [TsundokuTheme.obsidian]
///   (daisyUI-слой `tsundoku` + базовые правила `:root`, scrollbar, dialog).
library;

import 'package:material_ui/material_ui.dart';

import 'tsundoku_tokens.dart';

/// Статические значения `@theme static` и daisyUI-темы `tsundoku` из app.css.
/// Токены, ссылающиеся на `tokens.css` (`var(--bg-canvas)` и т.п.), берутся
/// из [TsundokuTheme] — тут только фиксированные литералы.
abstract final class TsundokuPalette {
  // daisyUI theme `tsundoku`.
  static const Color base300 = Color(0xFF14171F);
  static const Color primaryContent = Color(0xFFFFFFFF);
  static const Color secondaryContent = Color(0xFF101114);
  static const Color neutral = Color(0xFF242D42);
  static const Color info = Color(0xFF7DD3FC);
  static const Color daisySuccess = Color(0xFF2EA879);
  static const Color daisyWarning = Color(0xFFC2821B);
  static const Color daisyError = Color(0xFFE05265);

  // Радиусы: --radius-selector / --radius-field / --radius-box (rem → dp).
  static const double radiusSelector = 6.0;
  static const double radiusField = 8.0;
  static const double radiusBox = 12.0;

  // @theme static-литералы.
  static const Color cardHover = Color(0xFF1A1E28);
  static const Color panel = Color(0xFF1A1E28);
  static const Color panelRaised = Color(0xFF1A1E28);
  static const Color overlayStrong = Color(0xFF1E222D);
  static const Color accentLine = Color(0xFF7786EE);
  static const Color accentDeep = Color(0xFF6B58EB);
  static const Color inkFaint = Color(0xFF93C5FD);
  static const Color infoSoft = Color(0xFF7DD3FC);
  static const Color infoLine = Color(0xFF66C0F4);
  static const Color successSoft = Color(0xFF86EFAC);
  static const Color successLine = Color(0xFF34D399);
  static const Color successDeep = Color(0xFF13231B);
  static const Color successSurface = Color(0xFF0F241D);
  static const Color warningLine = Color(0xFFD97706);
  static const Color warningSurface = Color(0xFF281E0E);
  static const Color dangerSurface = Color(0xFF2B1016);
  static const Color scoreBg = Color(0xFF4A63C9);
  static const Color track = Color(0xFF2A3040);
  static const Color trackDeep = Color(0xFF12151C);
  static const Color trackMid = Color(0xFF14171F);
  static const Color trackSoft = Color(0xFF1A1E28);
  static const Color trackFaint = Color(0xFF161A22);
  static const Color trackAlt = Color(0xFF181B24);
  static const Color brandBlue = Color(0xFF2563EB);
  static const Color brandGreen = Color(0xFF228B57);
  static const Color brandSky = Color(0xFF38BDF8);
  static const Color slateDeep = Color(0xFF032541);

  // Muted overrides Tailwind-палитры для solid-кнопок (WCAG AA на тёмном).
  static const Color indigo600 = Color(0xFF4338CA);
  static const Color indigo500 = Color(0xFF4F46E5);
  static const Color rose600 = Color(0xFF9F2437);
  static const Color rose500 = Color(0xFFB92B42);
  static const Color emerald600 = Color(0xFF1B7348);
  static const Color emerald500 = Color(0xFF228B57);
  static const Color amber500 = Color(0xFFB87C14);
  static const Color amber600 = Color(0xFF9A650D);

  // Scrollbar (`*::-webkit-scrollbar*` и `.thin-scroll`).
  static const Color scrollbarThumb = Color(0xFF2B3348);
  static const Color scrollbarThumbHover = Color(0xFF39435C);
  static const Color thinScrollbarThumb = Color(0xFF39435C);
  static const Color thinScrollbarThumbHover = Color(0xFF4A5573);
  static const double scrollbarWidth = 10.0;
  static const double thinScrollbarWidth = 6.0;

  /// `--ease-tap: cubic-bezier(0.2, 0, 0, 1)`.
  static const Cubic easeTap = Cubic(0.2, 0, 0, 1);

  /// Кривая входа popover/dialog/view-fade: `cubic-bezier(0.16, 1, 0.3, 1)`.
  static const Cubic curveEnter = Cubic(0.16, 1, 0.3, 1);

  /// `.view-fade` — 150ms; dialog — 150ms; popover — 140ms.
  static const Duration durationViewFade = Duration(milliseconds: 150);
  static const Duration durationModal = Duration(milliseconds: 150);
  static const Duration durationPopover = Duration(milliseconds: 140);
}

/// Сборка `ThemeData` — аналог `@plugin "daisyui/theme"` + `:root`-правил app.css.
///
/// `font-sans: Inter, ...` → `fontFamily: 'Inter'` (real Inter подключён в
/// pubspec; на web-канвасе CSS-фолбэки не нужны).
ThemeData buildTsundokuTheme({TsundokuTheme tokens = TsundokuTheme.obsidian}) {
  final colorScheme = ColorScheme.dark(
    primary: tokens.accent,
    onPrimary: TsundokuPalette.primaryContent,
    secondary: tokens.accentSoft,
    onSecondary: TsundokuPalette.secondaryContent,
    error: TsundokuPalette.daisyError,
    surface: tokens.bgCard,
    onSurface: tokens.textPrimary,
    onSurfaceVariant: tokens.textSecondary,
    outline: tokens.borderStrong,
    outlineVariant: tokens.borderSubtle,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // `:root { font-family: var(--font-sans); color: var(--color-ink); }`
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.bgCanvas,
    canvasColor: tokens.bgCanvas,
    hoverColor: tokens.bgHover,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: tokens.borderSubtle,
    disabledColor: tokens.textMuted,
    extensions: <ThemeExtension<dynamic>>[tokens],

    // `button:not(:disabled) { cursor: pointer; }` + radius-field.
    buttonTheme: const ButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TsundokuPalette.radiusField)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: TsundokuPalette.primaryContent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
              Radius.circular(TsundokuPalette.radiusField)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.borderStrong),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
              Radius.circular(TsundokuPalette.radiusField)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.accentSoft,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
              Radius.circular(TsundokuPalette.radiusField)),
        ),
      ),
    ),

    // `.panel` / карточки: --radius-box = 0.75rem.
    cardTheme: CardThemeData(
      color: tokens.bgCard,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.all(Radius.circular(TsundokuPalette.radiusBox)),
      ),
    ),

    // `dialog` / `--color-modal` (opaque над постерами).
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.bgOverlay,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.all(Radius.circular(TsundokuPalette.radiusBox)),
      ),
    ),

    // `[popover]` / `--color-overlay`.
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.bgOverlay,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(
            Radius.circular(TsundokuPalette.radiusSelector)),
        side: BorderSide(color: tokens.borderSubtle),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.bgOverlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(
                Radius.circular(TsundokuPalette.radiusSelector)),
            side: BorderSide(color: tokens.borderSubtle),
          ),
        ),
      ),
    ),

    // `input:focus-visible` без outline; поля на --color-field.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.bgSurface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
            Radius.circular(TsundokuPalette.radiusField)),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
            Radius.circular(TsundokuPalette.radiusField)),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
            Radius.circular(TsundokuPalette.radiusField)),
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      hintStyle: TextStyle(color: tokens.textMuted),
    ),

    // Chrome (sidebar/header) — surface.
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: tokens.textPrimary,
    ),

    // `:focus-visible { outline: 2px solid var(--color-accent); }`.
    focusColor: tokens.accent,

    // Основной scrollbar (10px; thin-вариант задаётся локальной темой).
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(TsundokuPalette.scrollbarWidth),
      thumbColor: const WidgetStatePropertyAll(TsundokuPalette.scrollbarThumb),
      trackColor: WidgetStatePropertyAll(tokens.bgSurface),
      trackBorderColor: WidgetStatePropertyAll(tokens.bgSurface),
      radius: const Radius.circular(999),
      crossAxisMargin: 0,
      mainAxisMargin: 0,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accent,
      linearTrackColor: TsundokuPalette.track,
      circularTrackColor: TsundokuPalette.track,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: TsundokuPalette.overlayStrong,
        borderRadius: const BorderRadius.all(
            Radius.circular(TsundokuPalette.radiusSelector)),
        border: Border.all(color: tokens.borderSubtle),
      ),
      textStyle: const TextStyle(fontSize: 12),
    ),
  );
}
