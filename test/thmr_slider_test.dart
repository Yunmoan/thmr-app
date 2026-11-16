import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/thmr_slider.dart';

void main() {
  testWidgets('snaps to divisions when tapped', (tester) async {
    var value = 0.5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: StatefulBuilder(
              builder: (context, setState) => ThmrSlider(
                value: value,
                min: 0,
                max: 1,
                divisions: 10,
                semanticsLabel: '不透明度',
                formatValue: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    ));
    final rect = tester.getRect(find.byType(ThmrSlider));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
    await tester.pump();
    expect(value, closeTo(.8, .001));
    expect(find.byType(OverlayPortal), findsNothing);
  });

  testWidgets('exposes slider label, value and stepping semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var value = 0.5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: StatefulBuilder(
              builder: (context, setState) => ThmrSlider(
                value: value,
                min: 0,
                max: 1,
                divisions: 10,
                semanticsLabel: '不透明度',
                formatValue: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    ));
    final slider = find.bySemanticsLabel('不透明度');
    expect(slider, findsOneWidget);
    final node = tester.getSemantics(slider);
    expect(node.value, '50%');
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(value, closeTo(.6, .001));
    semantics.dispose();
  });
}
