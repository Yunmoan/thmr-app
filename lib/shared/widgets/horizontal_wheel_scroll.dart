import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 在横向列表上将纵向滚轮映射为横向滚动。
class HorizontalWheelScroll extends StatelessWidget {
  const HorizontalWheelScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs() ||
        !controller.hasClients) {
      return;
    }
    final position = controller.position;
    if (position.axis != Axis.horizontal ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }

    final delta = axisDirectionIsReversed(position.axisDirection)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;

    // 横向列表到达边界时，把纵向滚轮交给外层滚动区域。
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      position.pointerScroll(delta);
      event.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerSignal: _handlePointerSignal, child: child);
}
