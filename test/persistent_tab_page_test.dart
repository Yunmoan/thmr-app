import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';

void main() {
  testWidgets('tabs are ready before switching and retain input and scroll',
      (tester) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: active,
          child: Column(children: [
            const TextField(),
            Expanded(
              child: ListView(controller: scroll, children: const [
                SizedBox(height: 2000),
              ]),
            ),
          ]),
          builder: (context, value, child) =>
              PersistentTabPage(active: value, child: child!),
        ),
      ),
    ));
    expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    active.value = true;
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Touhou');
    scroll.jumpTo(500);
    await tester.pump();
    active.value = false;
    await tester.pump();
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(ListView, skipOffstage: false), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    active.value = true;
    await tester.pumpAndSettle();
    expect(scroll.offset, 500);
    expect(find.text('Touhou'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
