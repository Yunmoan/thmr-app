import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'thmr_colors.dart';
import 'thmr_focus_ring.dart';

export 'thmr_colors.dart' show AccentTheme;

/// THMR 主题工厂:把 tokens.css 的语义色映射进 Material 3。
/// 排版与 Web 端一致 — 思源宋体(Noto Serif SC)通栏,行高 1.62。
class ThmrTheme {
  const ThmrTheme._();

  static ThemeData light([AccentTheme theme = AccentTheme.reimu]) =>
      _build(ThmrTokens.resolve(theme, Brightness.light), Brightness.light);
  static ThemeData dark([AccentTheme theme = AccentTheme.reimu]) =>
      _build(ThmrTokens.resolve(theme, Brightness.dark), Brightness.dark);

  static ThemeData _build(ThmrTokens t, Brightness brightness) {
    t = t.accessible();
    final accent = t.accent;
    final base = GoogleFonts.notoSerifScTextTheme();
    final textTheme = base.apply(bodyColor: t.ink, displayColor: t.ink);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.codeInk,
      secondary: ThmrColors.shrineGreen,
      onSecondary: Colors.white,
      secondaryContainer: t.panelSoft,
      onSecondaryContainer: t.supportInk,
      tertiary: t.supportInk,
      onTertiary: Colors.white,
      error: brightness == Brightness.dark
          ? const Color(0xFFF28B91)
          : const Color(0xFFA63D4A),
      onError: brightness == Brightness.dark ? t.pageBg : Colors.white,
      surface: t.solidPanel,
      onSurface: t.ink,
      onSurfaceVariant: t.mutedInk,
      outline: t.panelBorder,
      outlineVariant: t.panelBorder,
      surfaceContainerHighest: t.solidPanel,
      surfaceContainerHigh: t.solidPanel,
      surfaceContainer: t.solidPanel,
      surfaceContainerLow: t.solidPanel,
      surfaceContainerLowest: t.solidPanel,
      inverseSurface: t.ink,
      onInverseSurface: t.pageBg,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      focusColor: accent.withValues(alpha: 0.12),
      scaffoldBackgroundColor: t.pageBg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme.copyWith(
        // 正文行高对齐 Web 端 1.62
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.62),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.62),
        bodySmall: textTheme.bodySmall?.copyWith(height: 1.5),
      ),
      iconTheme: IconThemeData(color: t.ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: t.ink,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: base.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, color: t.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme:
          DividerThemeData(color: t.panelBorder, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.panelBg,
        indicatorColor: t.accentSoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return base.labelMedium?.copyWith(
            color: selected ? t.ink : t.mutedInk,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 23,
              color:
                  states.contains(WidgetState.selected) ? accent : t.mutedInk,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.panelBg,
        indicatorColor: t.accentSoft,
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: t.mutedInk),
        selectedLabelTextStyle: base.labelLarge
            ?.copyWith(color: accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: base.labelLarge?.copyWith(color: t.mutedInk),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: t.onAccent,
          textStyle: base.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ).copyWith(backgroundBuilder: ThmrFocusRing.buttonBuilder),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          side: BorderSide(color: t.panelBorder),
          textStyle: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ).copyWith(backgroundBuilder: ThmrFocusRing.buttonBuilder),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ).copyWith(backgroundBuilder: ThmrFocusRing.circularButtonBuilder),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.ink)
            .copyWith(backgroundBuilder: ThmrFocusRing.circularButtonBuilder),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.fieldBg,
        hintStyle:
            base.bodyMedium?.copyWith(color: t.mutedInk.withValues(alpha: 0.7)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.panelBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.panelBorder),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.panelSoft,
        side: BorderSide(color: t.panelBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: base.labelLarge?.copyWith(color: t.ink),
        selectedColor: t.accentSoft,
        secondaryLabelStyle: base.labelLarge?.copyWith(color: t.ink),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? t.accentSoft : null),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? t.ink : t.mutedInk),
          side: WidgetStatePropertyAll(BorderSide(color: t.panelBorder)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: WidgetStatePropertyAll(
            base.labelLarge
                ?.copyWith(color: t.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.solidPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: t.panelBorder),
        ),
        titleTextStyle: base.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, color: t.ink),
        contentTextStyle: base.bodyMedium?.copyWith(color: t.mutedInk),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.solidPanel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.solidPanel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        showDragHandle: true,
        dragHandleColor: t.panelBorder,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.ink,
        contentTextStyle: base.bodyMedium?.copyWith(color: t.pageBg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.solidPanel),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: t.panelBorder),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.solidPanel,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: t.panelBorder),
        ),
        textStyle: base.bodyMedium?.copyWith(color: t.ink),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.solidPanel),
          elevation: const WidgetStatePropertyAll(6),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(t.panelBorder),
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(6.0),
      ),
      extensions: <ThemeExtension<dynamic>>[t],
    );
  }
}

/// 从 ThemeData 直接取 tokens(挂在 extension 上)。
extension ThmrTokensX on ThemeData {
  ThmrTokens get thmr =>
      extension<ThmrTokens>() ??
      ThmrTokens.resolve(AccentTheme.reimu, brightness);
}
