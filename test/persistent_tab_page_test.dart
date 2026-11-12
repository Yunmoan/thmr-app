import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';

class _Page extends StatefulWidget {
  const _Page({super.key});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final text = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: scroll,
        children: [
          TextField(controller: text),
          const SizedBox(height: 2000),
        ],
      );
}

void main() {
  testWidgets('tabs are ready before switching and retain input and scroll',
      (tester) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    final page = GlobalKey<_PageState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: active,
          child: _Page(key: page),
          builder: (context, value, child) =>
              PersistentTabPage(active: value, child: child!),
        ),
      ),
    ));
    final prepared = page.currentState;
    expect(prepared, isNotNull);
    active.value = true;
    await tester.pumpAndSettle();
    final state = page.currentState!;
    expect(state, same(prepared));
    state.text.text = 'Touhou';
    state.scroll.jumpTo(500);
    await tester.pump();
    active.value = false;
    await tester.pumpAndSettle();
    expect(page.currentState, same(state));
    expect(find.byType(TextField), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    active.value = true;
    await tester.pumpAndSettle();
    expect(page.currentState, same(state));
    expect(state.text.text, 'Touhou');
    expect(state.scroll.offset, 500);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
