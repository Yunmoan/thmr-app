import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LargeScreenSymbol {
  enter,
  fullscreen,
  windowed,
  collapse,
  clock,
  date,
  text,
  adaptive,
  left,
  right,
  centered,
  fill,
  fit,
}

/// 小图标沿用播放器控件的颜色和一像素线宽，预览图对应实际布局选项。
class LargeScreenGlyph extends StatelessWidget {
  const LargeScreenGlyph(this.symbol, {super.key, this.size = 22, this.color});

  final LargeScreenSymbol symbol;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final diagram = symbol.index >= LargeScreenSymbol.adaptive.index;
    final paths = switch (symbol) {
      LargeScreenSymbol.enter =>
        '<rect x="3" y="4" width="18" height="13" rx="1.5"/><path d="M8 21h8m-4-4v4M7 8h4m-4 0v4m10 1h-4m4 0V9"/>',
      LargeScreenSymbol.fullscreen =>
        '<path d="M4 9V4h5m6 0h5v5M4 15v5h5m6 0h5v-5"/>',
      LargeScreenSymbol.windowed =>
        '<path d="M9 4v5H4m16 0h-5V4M4 15h5v5m6 0v-5h5"/>',
      LargeScreenSymbol.collapse => '<path d="m6 9 6 6 6-6"/>',
      LargeScreenSymbol.clock =>
        '<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
      LargeScreenSymbol.date =>
        '<rect x="4" y="6" width="16" height="14" rx="2"/><path d="M8 3v6m8-6v6M4 11h16m-12 4h3m3 0h2"/>',
      LargeScreenSymbol.text => '<path d="M5 8V5h14v3m-7-3v14m-4 0h8"/>',
      LargeScreenSymbol.adaptive =>
        '<rect x="3" y="4" width="44" height="34" rx="2"/><rect x="8" y="10" width="17" height="18" rx="1"/><path d="M30 12h11m-11 6h8m-22 15h25"/><rect x="54" y="4" width="23" height="40" rx="2"/><rect x="59" y="10" width="13" height="13" rx="1"/><path d="M59 29h13m-11 6h9"/>',
      LargeScreenSymbol.left =>
        '<rect x="3" y="4" width="74" height="40" rx="2"/><rect x="9" y="10" width="27" height="27" rx="1"/><path d="M43 13h26m-26 7h22m-22 10h26m-26 6h17"/>',
      LargeScreenSymbol.right =>
        '<rect x="3" y="4" width="74" height="40" rx="2"/><rect x="44" y="10" width="27" height="27" rx="1"/><path d="M10 13h26m-26 7h22m-22 10h26m-26 6h17"/>',
      LargeScreenSymbol.centered =>
        '<rect x="3" y="4" width="74" height="40" rx="2"/><rect x="30" y="9" width="20" height="20" rx="1"/><path d="M22 34h36m-28 5h20"/>',
      LargeScreenSymbol.fill =>
        '<rect x="3" y="4" width="74" height="40" rx="2"/><rect x="8" y="9" width="64" height="30" rx="1"/><path d="M15 18v-3h3m44 0h3v3M15 30v3h3m44 0h3v-3"/>',
      LargeScreenSymbol.fit =>
        '<rect x="3" y="4" width="74" height="40" rx="2"/><rect x="20" y="12" width="40" height="24" rx="1"/><path d="M8 20v8m64-8v8"/>',
    };
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${diagram ? '0 0 80 48' : '0 0 24 24'}" fill="none" stroke="#000" stroke-width="${diagram ? 1.3 : 1.5}" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
      width: diagram ? size * 1.67 : size,
      height: size,
      colorFilter: ColorFilter.mode(
          color ?? Theme.of(context).colorScheme.onSurface, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
