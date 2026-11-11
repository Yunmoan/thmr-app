import 'package:flutter/material.dart';

/// Character themes. Each carries its own accent, paper gradient,
/// background illustration and dark variants.
enum AccentTheme { reimu, marisa, cirno, tenshi, sanae, koishi, remilia, satori }

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

  /// Tenshi — 绀蓝(裙装的深绀青)。
  static const ThmrTokens tenshiLight = ThmrTokens(
    accent: Color(0xFF5C6BB0),
    onAccent: Color(0xFFF4F6FC),
    pageBg: Color(0xFFF2F4F9),
    ink: Color(0xFF171C2A),
    mutedInk: Color(0xFF5A6275),
    supportInk: Color(0xFF4E5D6E),
    panelBg: Color(0xEBFAFBFE),
    panelBorder: Color(0x29262C44),
    panelSoft: Color(0x125C6BB0),
    accentSoft: Color(0x215C6BB0),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x14171C2A),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0F2F4F9), Color(0x92E2E7F2), Color(0x9CD5DCF0)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A262C44),
    solidPanel: Color(0xFFFAFBFE),
    codeInk: Color(0xFF1E2638),
    illustration: 'assets/brand/tenshi_background_alt.png',
  );

  static const ThmrTokens tenshiDark = ThmrTokens(
    accent: Color(0xFF5C6BB0),
    onAccent: Color(0xFFF4F6FC),
    pageBg: Color(0xFF0C0F18),
    ink: Color(0xFFEDF0F8),
    mutedInk: Color(0xFFC6CCDD),
    supportInk: Color(0xFFB4C0D2),
    panelBg: Color(0xE6131622),
    panelBorder: Color(0x21DCE4F4),
    panelSoft: Color(0x12DCE4F4),
    accentSoft: Color(0x385C6BB0),
    fieldBg: Color(0x14E8EEF8),
    secondaryButtonBg: Color(0x17DCE4F4),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD8141722), Color(0xA80D1018), Color(0xB4090C12)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF131622),
    codeInk: Color(0xFFDEE6F4),
    illustration: 'assets/brand/tenshi_background_alt.png',
  );

  /// Sanae — 青风(青蛙发饰与发色的翠绿)。
  static const ThmrTokens sanaeLight = ThmrTokens(
    accent: Color(0xFF4E9E62),
    onAccent: Color(0xFFF3FBF5),
    pageBg: Color(0xFFEFF6F0),
    ink: Color(0xFF14231A),
    mutedInk: Color(0xFF587061),
    supportInk: Color(0xFF4F6B62),
    panelBg: Color(0xEBF8FCF9),
    panelBorder: Color(0x292A4434),
    panelSoft: Color(0x114E9E62),
    accentSoft: Color(0x214E9E62),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x1414231A),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0EFF6F0), Color(0x92E0EFE5), Color(0x9CD2E8DA)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A2A4434),
    solidPanel: Color(0xFFF8FCF9),
    codeInk: Color(0xFF1C3428),
    illustration: 'assets/brand/sanae_background_alt.png',
  );

  static const ThmrTokens sanaeDark = ThmrTokens(
    accent: Color(0xFF4E9E62),
    onAccent: Color(0xFFF3FBF5),
    pageBg: Color(0xFF0A130D),
    ink: Color(0xFFEAF5EC),
    mutedInk: Color(0xFFC2D8C8),
    supportInk: Color(0xFFB0C8BC),
    panelBg: Color(0xE6101B14),
    panelBorder: Color(0x21D4EADC),
    panelSoft: Color(0x12D4EADC),
    accentSoft: Color(0x384E9E62),
    fieldBg: Color(0x14E0F2E6),
    secondaryButtonBg: Color(0x17D4EADC),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD8111C14), Color(0xA80C130E), Color(0xB4070D09)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF101B14),
    codeInk: Color(0xFFDAEEDE),
    illustration: 'assets/brand/sanae_background_alt.png',
  );

  /// Koishi — 紫瞳(第三只眼的藤紫)。
  static const ThmrTokens koishiLight = ThmrTokens(
    accent: Color(0xFF8E6FA8),
    onAccent: Color(0xFFFBF8FD),
    pageBg: Color(0xFFF6F2F9),
    ink: Color(0xFF1E1826),
    mutedInk: Color(0xFF685E78),
    supportInk: Color(0xFF5E5F70),
    panelBg: Color(0xEBFCFAFE),
    panelBorder: Color(0x29382A4C),
    panelSoft: Color(0x128E6FA8),
    accentSoft: Color(0x218E6FA8),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x141E1826),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0F6F2F9), Color(0x92ECE6F4), Color(0x9CDFD8EE)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A382A4C),
    solidPanel: Color(0xFFFCFAFE),
    codeInk: Color(0xFF2A2038),
    illustration: 'assets/brand/koishi_background_alt.png',
  );

  static const ThmrTokens koishiDark = ThmrTokens(
    accent: Color(0xFF8E6FA8),
    onAccent: Color(0xFFFBF8FD),
    pageBg: Color(0xFF110C16),
    ink: Color(0xFFF3EDF8),
    mutedInk: Color(0xFFD2C6DE),
    supportInk: Color(0xFFBEBACC),
    panelBg: Color(0xE6181220),
    panelBorder: Color(0x21E8DFF2),
    panelSoft: Color(0x12E8DFF2),
    accentSoft: Color(0x388E6FA8),
    fieldBg: Color(0x14F0EAF8),
    secondaryButtonBg: Color(0x17E8DFF2),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD8181220), Color(0xA8110C15), Color(0xB40B080F)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF181220),
    codeInk: Color(0xFFE8DEF4),
    illustration: 'assets/brand/koishi_background_alt.png',
  );

  /// Remilia — 猩红(深血红,与灵梦的玫瑰绯红区分)。
  static const ThmrTokens remiliaLight = ThmrTokens(
    accent: Color(0xFFAE3548),
    onAccent: Color(0xFFFFF6F5),
    pageBg: Color(0xFFFAF1F1),
    ink: Color(0xFF241417),
    mutedInk: Color(0xFF75565C),
    supportInk: Color(0xFF5C4E55),
    panelBg: Color(0xEBFFFAFA),
    panelBorder: Color(0x294E2028),
    panelSoft: Color(0x11AE3548),
    accentSoft: Color(0x21AE3548),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x14241417),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0FAF1F1), Color(0x92F2E0E3), Color(0x9CEAD6DA)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A4E2028),
    solidPanel: Color(0xFFFFFAFA),
    codeInk: Color(0xFF341F24),
    illustration: 'assets/brand/remilia_background_alt.png',
  );

  static const ThmrTokens remiliaDark = ThmrTokens(
    accent: Color(0xFFAE3548),
    onAccent: Color(0xFFFFF6F5),
    pageBg: Color(0xFF150C0E),
    ink: Color(0xFFF8ECEE),
    mutedInk: Color(0xFFD8C2C6),
    supportInk: Color(0xFFC4B2BA),
    panelBg: Color(0xE61E1316),
    panelBorder: Color(0x21F8E2E6),
    panelSoft: Color(0x12F8E2E6),
    accentSoft: Color(0x38AE3548),
    fieldBg: Color(0x14F6E8EC),
    secondaryButtonBg: Color(0x17F8E2E6),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD81E1316), Color(0xA8150C0E), Color(0xB411090B)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF1E1316),
    codeInk: Color(0xFFF2DDE2),
    illustration: 'assets/brand/remilia_background_alt.png',
  );

  /// Satori — 藕荷(淡粉紫,发色与裙装的藕荷色,与恋恋的藤紫区分)。
  static const ThmrTokens satoriLight = ThmrTokens(
    accent: Color(0xFFA86492),
    onAccent: Color(0xFFFFF7FA),
    pageBg: Color(0xFFFAF1F5),
    ink: Color(0xFF221822),
    mutedInk: Color(0xFF6F5A6B),
    supportInk: Color(0xFF655E6C),
    panelBg: Color(0xEBFCFAFD),
    panelBorder: Color(0x2940283A),
    panelSoft: Color(0x12A86492),
    accentSoft: Color(0x21A86492),
    fieldBg: Color(0xE6FFFFFF),
    secondaryButtonBg: Color(0x14221822),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD0FAF1F5), Color(0x92F2E3EC), Color(0x9CE7D7E2)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x1A40283A),
    solidPanel: Color(0xFFFCFAFD),
    codeInk: Color(0xFF322430),
    illustration: 'assets/brand/satori_background_alt.png',
  );

  static const ThmrTokens satoriDark = ThmrTokens(
    accent: Color(0xFFA86492),
    onAccent: Color(0xFFFFF7FA),
    pageBg: Color(0xFF140C11),
    ink: Color(0xFFF6EDF3),
    mutedInk: Color(0xFFD5C3D1),
    supportInk: Color(0xFFC1B5C1),
    panelBg: Color(0xE6191118),
    panelBorder: Color(0x21F2DFEA),
    panelSoft: Color(0x12F2DFEA),
    accentSoft: Color(0x38A86492),
    fieldBg: Color(0x14F3E7EF),
    secondaryButtonBg: Color(0x17F2DFEA),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xD8191118), Color(0xA8140C11), Color(0xB40F090D)],
      stops: [0.0, 0.54, 1.0],
    ),
    shadow: Color(0x52000000),
    solidPanel: Color(0xFF191118),
    codeInk: Color(0xFFF1DCE9),
    illustration: 'assets/brand/satori_background_alt.png',
  );

  static ThmrTokens resolve(AccentTheme theme, Brightness brightness) {
    switch (theme) {
      case AccentTheme.tenshi:
        return brightness == Brightness.dark ? tenshiDark : tenshiLight;
      case AccentTheme.sanae:
        return brightness == Brightness.dark ? sanaeDark : sanaeLight;
      case AccentTheme.koishi:
        return brightness == Brightness.dark ? koishiDark : koishiLight;
      case AccentTheme.remilia:
        return brightness == Brightness.dark ? remiliaDark : remiliaLight;
      case AccentTheme.marisa:
        return brightness == Brightness.dark ? marisaDark : marisaLight;
      case AccentTheme.cirno:
        return brightness == Brightness.dark ? cirnoDark : cirnoLight;
      case AccentTheme.reimu:
        return brightness == Brightness.dark ? reimuDark : reimuLight;
      case AccentTheme.satori:
        return brightness == Brightness.dark ? satoriDark : satoriLight;
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
