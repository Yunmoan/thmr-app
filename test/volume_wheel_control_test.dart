import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/volume_wheel_control.dart';

void main() {
  testWidgets('wheel over volume button adjusts volume without clicking it',
      (tester) async {
    var volume = 50.0;
    var clicks = 0;
    final changes = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Row(
            children: [
              VolumeWheelControl(
                value: volume,
                onChanged: (value) => setState(() {
                  volume = value;
                  changes.add(value);
                }),
                child: IconButton(
                  onPressed: () => clicks++,
                  icon: const Icon(Icons.volume_up),
                ),
              ),
              const SizedBox(key: ValueKey('outside'), width: 100, height: 48),
            ],
          ),
        ),
      ),
    ));

    Future<void> scrollAt(Offset position, Offset delta) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: position, scrollDelta: delta),
      );
      await tester.pump();
    }

    final icon = find.byIcon(Icons.volume_up);
    await scrollAt(tester.getCenter(icon), const Offset(0, -20));
    expect(volume, 55);
    await scrollAt(tester.getCenter(icon), const Offset(0, 20));
    expect(volume, 50);
    await scrollAt(tester.getCenter(icon), const Offset(20, 0));
    await scrollAt(tester.getCenter(find.byKey(const ValueKey('outside'))),
        const Offset(0, -20));
    expect(changes, [55, 50]);
    expect(clicks, 0);

    await tester.tap(icon);
    expect(clicks, 1);
  });

  testWidgets('wheel volume stays within 0 to 100', (tester) async {
    var volume = 98.0;
    final changes = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => VolumeWheelControl(
            value: volume,
            onChanged: (value) => setState(() {
              volume = value;
              changes.add(value);
            }),
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    ));

    Future<void> scroll(double dy) async {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(find.byType(VolumeWheelControl)),
        scrollDelta: Offset(0, dy),
      ));
      await tester.pump();
    }

    await scroll(-20);
    await scroll(-20);
    expect(changes, [100]);
    for (var i = 0; i < 20; i++) {
      await scroll(20);
    }
    await scroll(20);
    expect(volume, 0);
    expect(changes.length, 21);
    expect(changes.last, 0);
  });
}
