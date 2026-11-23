import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 指针位于 [child] 上方时，滚轮每格调整五个音量点。
class VolumeWheelControl extends StatelessWidget {
  const VolumeWheelControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
          final next =
              (value + (event.scrollDelta.dy < 0 ? 5 : -5)).clamp(0.0, 100.0);
          if (next != value) onChanged(next);
        },
        child: child,
      );
}
