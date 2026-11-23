import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/settings_provider.dart';

/// 在窗口边缘提示开发者模式，点击仍由下方界面处理。
class DeveloperModeStrip extends ConsumerWidget {
  const DeveloperModeStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider.select((s) => s.developerMode))) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Semantics(
        label: '开发者模式已启用',
        child: const CustomPaint(
          size: Size.fromHeight(5),
          painter: _StripePainter(),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 16.0;
    final bounds = Offset.zero & size;
    final stripes = Path();
    for (var x = 0.0; x < size.width + size.height; x += stripeWidth * 2) {
      stripes
        ..moveTo(x, 0)
        ..lineTo(x + stripeWidth, 0)
        ..lineTo(x + stripeWidth - size.height, size.height)
        ..lineTo(x - size.height, size.height)
        ..close();
    }
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = const Color(0xBF3E474B));
    canvas.drawPath(stripes, Paint()..color = const Color(0xFFFFD857));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => false;
}
