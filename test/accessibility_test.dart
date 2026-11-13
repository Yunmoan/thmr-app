import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/shared/widgets/desktop_title_bar.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';
import 'package:thmr_app/shared/widgets/volume_slider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';

void main() {
  testWidgets('hidden tab releases focus and cannot receive it again',
      (tester) async {
    final active = ValueNotifier(true);
    final focus = FocusNode();
    addTearDown(active.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, value, __) => PersistentTabPage(
              active: value, child: TextField(focusNode: focus))),
    )));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    active.value = false;
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    active.value = true;
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mini mode excludes the retained main window from focus',
      (tester) async {
    final focus = FocusNode();
    final container = ProviderContainer();
    addTearDown(focus.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DesktopPlayerSurface(
                miniPlayer: const Text('mini'),
                child: Material(child: TextField(focusNode: focus))))));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    container.read(miniPlayerProvider.notifier).state = true;
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all caption buttons expose meaningful names', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DesktopTitleBar(onMini: () {}))));
    for (final label in ['切换到迷你播放器', '最小化窗口', '最大化或还原窗口', '关闭窗口']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('volume has a visible focus state and handles keyboard repeat',
      (tester) async {
    var value = 50.0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (_, setState) => Center(
                    child: SizedBox(
                        width: 200,
                        child: VolumeSlider(
                            value: value,
                            onChanged: (v) => setState(() => value = v))))))));
    final paint = find.descendant(
        of: find.byType(VolumeSlider), matching: find.byType(CustomPaint));
    final unfocused = tester.widget<CustomPaint>(paint).painter!;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = tester.widget<CustomPaint>(paint).painter!;
    expect(focused.shouldRepaint(unfocused), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(value, 60);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(value, 100);
  });

  testWidgets('mini playback and mute controls expose action names',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            builder: (_, __) => const MiniPlayerWindow(
                stationState: StationUiState(), playbackState: PlaybackState()),
            home: const SizedBox.shrink())));
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
    expect(find.bySemanticsLabel('静音'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final preset in AccentTheme.values) {
    for (final brightness in Brightness.values) {
      test('small accent and button text meet contrast in $preset $brightness',
          () {
        final tokens = ThmrTokens.resolve(preset, brightness).accessible();
        expect(ThmrColors.contrast(tokens.accent, tokens.solidPanel),
            greaterThanOrEqualTo(4.5));
        expect(ThmrColors.contrast(tokens.accent, tokens.onAccent),
            greaterThanOrEqualTo(4.5));
      });
    }
  }
}
