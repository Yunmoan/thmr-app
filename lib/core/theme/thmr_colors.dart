import 'package:flutter/material.dart';

/// Character themes. Each carries its own accent, paper gradient,
/// background illustration and dark variants.
enum AccentTheme { reimu, marisa, cirno }

/// Static brand constants (default Reimu crimson kept for compatibility).
class ThmrColors {
  const ThmrColors._();

  static const Color accent = Color(0xFFC65A69);
  static const Color onAccent = Color(0xFFFFF8FA);

  /// Logo 中的深绿(神社注连绳),仅作点缀。
  static const Color shrineGreen = Color(0xFF3D6B4F);
}

/// Per-theme token bundle. Fields mirror the web tokens.css but are
/// parameterized per character; all values are hand-tuned.
class ThmrTokens extends ThemeExtension<ThmrTokens> {
  const ThmrTokens({
    required this.accent,
    required this.onAccent,
    required this.pageBg,
    required this.ink,
    required this.mutedInk,
    required this.supportInk,
    required this.panelBg,
    required this.panelBorder,
    required this.panelSoft,
    required this.accentSoft,
    required this.fieldBg,
    required this.secondaryButtonBg,
    required this.pageGradient,
    required this.shadow,
    required this.solidPanel,
    required this.codeInk,
    required this.illustration,
  });

  final Color accent;
  final Color onAccent;
  final Color pageBg;
  final Color ink;
  final Color mutedInk;
  final Color supportInk;
  final Color panelBg;
  final Color panelBorder;
  final Color panelSoft;
  final Color accentSoft;
  final Color fieldBg;
  final Color secondaryButtonBg;
  final Gradient pageGradient;
  final Color shadow;
  final Color solidPanel;
  final Color codeInk;
  final String illustration;

  /// Reimu (default) — 博丽红白.
  static const ThmrTokens reimuLight = ThmrTokens(
    accent: Color(0xFFC65A69),
    onAccent: Color(0xFFFFF8FA),
    pageBg: Color(0xFFFBF2F4),
    ink: Color(0xFF24161A),
    mutedInk: Color(0xFF6F5960),
    supportInk: Color(0xFF4D615C),
    panelBg: Color(0xEBFFFBFC),
    panelBorder: Color(0x2954222E),
    panelSoft: Color(0x11992B3E),
    accentSoft: Color(0x21C65A69),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x1424161A),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0FBF2F4), Color(0x92F2E2E7), Color(0x9CEAD8DE)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A54222E),
    solidPanel: Color(0xFFFFFBFC),
    codeInk: Color(0xFF342229),
    illustration: 'assets/brand/background_alt.png',
  );

  static const ThmrTokens reimuDark = ThmrTokens(
    accent: Color(0xFFC65A69),
    onAccent: Color(0xFFFFF8FA),
    pageBg: Color(0xFF160D10),
    ink: Color(0xFFF8EDF0),
    mutedInk: Color(0xFFD7C1C8),
    supportInk: Color(0xFFB8CBC5),
    panelBg: Color(0xE61F1317),
    panelBorder: Color(0x21FFE4EC),
    panelSoft: Color(0x12FFE4EC),
    accentSoft: Color(0x38C65A69),
    fieldBg: Color(0x14FFF0F4),
    secondaryButtonBg: Color(0x17FFE4EC),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD8211317), Color(0xA8160D10), Color(0xB412090C)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF1F1317),
    codeInk: Color(0xFFF4DFE6),
    illustration: 'assets/brand/background_alt.png',
  );

  /// Marisa — 黑金星尘.
  static const ThmrTokens marisaLight = ThmrTokens(
    accent: Color(0xFFD9A43C),
    onAccent: Color(0xFF231A06),
    pageBg: Color(0xFFFAF4E6),
    ink: Color(0xFF26200F),
    mutedInk: Color(0xFF75694F),
    supportInk: Color(0xFF6B6248),
    panelBg: Color(0xEBFFFDF4),
    panelBorder: Color(0x295A4A28),
    panelSoft: Color(0x14D9A43C),
    accentSoft: Color(0x21D9A43C),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x1426200F),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0FAF4E6), Color(0x92F1E6CF), Color(0x9CE9DBB8)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A5A4A28),
    solidPanel: Color(0xFFFFFDF4),
    codeInk: Color(0xFF3A3014),
    illustration: 'assets/brand/marisa_background_alt.png',
  );

  static const ThmrTokens marisaDark = ThmrTokens(
    accent: Color(0xFFD9A43C),
    onAccent: Color(0xFF231A06),
    pageBg: Color(0xFF131008),
    ink: Color(0xFFF6EEDC),
    mutedInk: Color(0xFFD8CBA8),
    supportInk: Color(0xFFC0BA9F),
    panelBg: Color(0xE61F1A10),
    panelBorder: Color(0x21F0E4C8),
    panelSoft: Color(0x12F0E4C8),
    accentSoft: Color(0x38D9A43C),
    fieldBg: Color(0x14F6EEDC),
    secondaryButtonBg: Color(0x17F0E4C8),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD81E1810), Color(0xA8131008), Color(0xB40E0B05)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF1F1A10),
    codeInk: Color(0xFFF2E6C8),
    illustration: 'assets/brand/marisa_background_alt.png',
  );

  /// Cirno — 冰蓝.
  static const ThmrTokens cirnoLight = ThmrTokens(
    accent: Color(0xFF4E9FD4),
    onAccent: Color(0xFFF2FAFE),
    pageBg: Color(0xFFEFF6FA),
    ink: Color(0xFF152430),
    mutedInk: Color(0xFF5A6E7A),
    supportInk: Color(0xFF57707E),
    panelBg: Color(0xEBF8FCFE),
    panelBorder: Color(0x29304450),
    panelSoft: Color(0x114E9FD4),
    accentSoft: Color(0x214E9FD4),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x14152430),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0EFF6FA), Color(0x92E0EEF5), Color(0x9CD3E6EF)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A304450),
    solidPanel: Color(0xFFF8FCFE),
    codeInk: Color(0xFF1E3440),
    illustration: 'assets/brand/baka_background_alt.png',
  );

  static const ThmrTokens cirnoDark = ThmrTokens(
    accent: Color(0xFF4E9FD4),
    onAccent: Color(0xFFF2FAFE),
    pageBg: Color(0xFF0A1216),
    ink: Color(0xFFEAF4F8),
    mutedInk: Color(0xFFC2D6E0),
    supportInk: Color(0xFFB0C4CC),
    panelBg: Color(0xE6101A20),
    panelBorder: Color(0x21D4E8F0),
    panelSoft: Color(0x12D4E8F0),
    accentSoft: Color(0x384E9FD4),
    fieldBg: Color(0x14E0F0F8),
    secondaryButtonBg: Color(0x17D4E8F0),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD80F1A20), Color(0xA80A1216), Color(0xB4070D10)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF101A20),
    codeInk: Color(0xFFD8ECF4),
    illustration: 'assets/brand/baka_background_alt.png',
  );

  static ThmrTokens resolve(AccentTheme theme, Brightness brightness) {
    switch (theme) {
      case AccentTheme.marisa:
        return brightness == Brightness.dark ? marisaDark : marisaLight;
      case AccentTheme.cirno:
        return brightness == Brightness.dark ? cirnoDark : cirnoLight;
      case AccentTheme.reimu:
        return brightness == Brightness.dark ? reimuDark : reimuLight;
    }
  }

  @override
  ThmrTokens copyWith({Color? accent}) => this; // 语义色为静态令牌,不做运行时插值

  @override
  ThmrTokens lerp(covariant ThmrTokens? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// 兼容别名(默认灵梦主题)。
const ThmrTokens kReimuLight = ThmrTokens.reimuLight;
const ThmrTokens kReimuDark = ThmrTokens.reimuDark;

/// 语义取色入口:`Thmr.of(context).panelBg`。
class Thmr extends InheritedWidget {
  const Thmr({super.key, required this.tokens, required super.child});

  final ThmrTokens tokens;

  static ThmrTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Thmr>()!.tokens;

  @override
  bool updateShouldNotify(Thmr oldWidget) => tokens != oldWidget.tokens;
}
