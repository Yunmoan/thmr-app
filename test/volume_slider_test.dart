import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/volume_slider.dart';

void main() {
  testWidgets('dragging volume does not start the surrounding window drag',
      (tester) async {
    var movedWindow = false;
    var volume = 50.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GestureDetector(
            onPanStart: (_) => movedWindow = true,
            child: Center(
              child: SizedBox(
                width: 200,
                child: VolumeSlider(
                  value: volume,
                  onChanged: (value) => setState(() => volume = value),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.drag(find.byType(VolumeSlider), const Offset(40, 0));
    await tester.pump();
    expect(movedWindow, isFalse);
    expect(volume, greaterThan(50));
  });

  testWidgets('volume control works in a pushed route without OverlayPortal',
      (tester) async {
    var volume = 50.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) => Center(
                      child: SizedBox(
                        width: 200,
                        child: VolumeSlider(
                          value: volume,
                          onChanged: (value) => setState(() => volume = value),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(VolumeSlider), findsOneWidget);
    expect(find.byType(OverlayPortal), findsNothing);
    final rect = tester.getRect(find.byType(VolumeSlider));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
    await tester.pump();
    expect(volume, closeTo(77, 1));

    await tester.drag(find.byType(VolumeSlider), const Offset(-35, 0));
    await tester.pump();
    expect(volume, lessThan(77));

    final paint = find.descendant(
      of: find.byType(VolumeSlider),
      matching: find.byType(CustomPaint),
    );
    Focus.of(tester.element(paint)).requestFocus();
    await tester.pump();
    final beforeKey = volume;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(volume, closeTo(beforeKey - 5, .01));
    expect(tester.takeException(), isNull);
  });
}
