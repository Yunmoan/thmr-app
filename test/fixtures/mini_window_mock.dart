import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/platform/window_presentation.dart';

const miniPresentationChannel = MethodChannel('thmr/window_presentation');
const primaryMiniDisplay = (
  bounds: Rect.fromLTWH(0, 0, 1920, 1080),
  workArea: Rect.fromLTWH(0, 0, 1920, 1040),
);

void mockMiniWindow(
  WidgetTester tester, {
  required Rect Function() bounds,
  required FutureOr<void> Function(Offset) move,
  List<WindowDisplay> displays = const [primaryMiniDisplay],
  int dpi = 96,
}) {
  Map<String, int> encode(Rect rect) => {
        'left': rect.left.round(),
        'top': rect.top.round(),
        'right': rect.right.round(),
        'bottom': rect.bottom.round(),
      };

  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(miniPresentationChannel, (call) async {
    switch (call.method) {
      case 'miniWindowGeometry':
        return {
          'bounds': encode(bounds()),
          'dpi': dpi,
          'displays': [
            for (final display in displays)
              {
                'bounds': encode(display.bounds),
                'workArea': encode(display.workArea),
              },
          ],
        };
      case 'windowBoundsInPixels':
        return encode(bounds());
      case 'setWindowPositionInPixels':
        final arguments = call.arguments as Map;
        await move(Offset(
          (arguments['x'] as int).toDouble(),
          (arguments['y'] as int).toDouble(),
        ));
    }
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(miniPresentationChannel, null));
}
