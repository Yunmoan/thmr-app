import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/theme/thmr_focus_ring.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/shared/widgets/focus_outline.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';

Finder get _visibleRings => find
    .byWidgetPredicate((widget) => widget is ThmrFocusRing && widget.focused);

Future<void> _expectRingPixels(
    WidgetTester tester, GlobalKey capture, ThemeData theme,
    {int colorTolerance = 0}) async {
  final target = find.descendant(
    of: _visibleRings,
    matching: find.byType(CompositedTransformTarget),
  );
  final origin = tester.getTopLeft(find.byKey(capture));
  final owner = tester
      .widget<ThmrFocusRing>(_visibleRings)
      .focusNode
      ?.context
      ?.findRenderObject();
  final rect = owner is RenderBox
      ? (owner.localToGlobal(Offset.zero) & owner.size).shift(-origin)
      : tester.getRect(target).shift(-origin);
  await tester.runAsync(() async {
    final image = await (capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (final point in [
      Offset(rect.left - 2.5, rect.center.dy),
      Offset(rect.right + 2.5, rect.center.dy),
      Offset(rect.center.dx, rect.top - 2.5),
      Offset(rect.center.dx, rect.bottom + 2.5),
    ]) {
      final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      final color = Color.fromARGB(
        pixels.getUint8(offset + 3),
        pixels.getUint8(offset),
        pixels.getUint8(offset + 1),
        pixels.getUint8(offset + 2),
      );
      for (final shift in [0, 8, 16, 24]) {
        final actual = (color.toARGB32() >> shift) & 0xff;
        final expected = (theme.colorScheme.primary.toARGB32() >> shift) & 0xff;
        expect(actual, closeTo(expected, colorTolerance),
            reason: 'ring pixel at $point, channel $shift');
      }
    }
    image.dispose();
  });
}

void main() {
  testWidgets('selected chips resize their ring around the painted chip',
      (tester) async {
    final selected = ValueNotifier(false);
    final focus = FocusNode();
    final capture = GlobalKey();
    final theme = ThemeData.dark().copyWith(
        chipTheme: const ChipThemeData(
      shape: StadiumBorder(),
      labelStyle: TextStyle(
          fontFamily: 'Ahem', fontSize: 14, letterSpacing: 0, height: 1),
    ));
    addTearDown(selected.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: 300,
        height: 180,
        child: RepaintBoundary(
          key: capture,
          child: ThmrFocusLayer(
              child: RepaintBoundary(
            child: Center(
                child: ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (_, value, __) => FocusOutline(
                radius: 999,
                focusBounds: true,
                child: ChoiceChip(
                  focusNode: focus,
                  label: const Text('quality'),
                  selected: value,
                  onSelected: (value) => selected.value = value,
                ),
              ),
            )),
          )),
        ),
      ))),
    ));
    focus.requestFocus();
    await tester.pumpAndSettle();
    final owner = focus.context!.findRenderObject()! as RenderBox;
    expect(owner.size.height, lessThan(tester.getSize(_visibleRings).height));
    for (final value in [true, false, true]) {
      selected.value = value;
      await tester.pumpAndSettle();
      // The tangent of the stadium curve has slight raster antialiasing.
      await _expectRingPixels(tester, capture, theme, colorTolerance: 12);
    }
  });

  testWidgets('button ring respects a local state-dependent shape',
      (tester) async {
    final states = WidgetStatesController();
    final focus = FocusNode();
    addTearDown(states.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(
        textButtonTheme: const TextButtonThemeData(
            style: ButtonStyle(
          backgroundBuilder: ThmrFocusRing.circularButtonBuilder,
        )),
      ),
      home: Scaffold(
          body: Center(
              child: TextButton(
        focusNode: focus,
        statesController: states,
        onPressed: () {},
        style: ButtonStyle(
            shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
            states.contains(WidgetState.selected) ? 12 : 5,
          )),
        )),
        child: const Text('channel'),
      ))),
    ));
    focus.requestFocus();
    await tester.pumpAndSettle();
    for (final selected in [false, true, false]) {
      states.update(WidgetState.selected, selected);
      await tester.pumpAndSettle();
      final size = tester.getSize(_visibleRings);
      final painter = tester
          .widget<CustomPaint>(find.descendant(
            of: _visibleRings,
            matching: find.byType(CustomPaint),
          ))
          .foregroundPainter!;
      expect(
          (Canvas canvas) => painter.paint(canvas, size),
          paints
            ..rrect(
              rrect: RRect.fromRectAndRadius(
                (Offset.zero & size).inflate(2.5),
                Radius.circular((selected ? 12 : 5) + 2.5),
              ),
              strokeWidth: 1,
            ));
    }
  });

  for (final animated in [false, true]) {
    testWidgets(
        'ring follows parent layout with animation=$animated without rebuilding its child',
        (tester) async {
      final width = ValueNotifier(80.0);
      final focus = FocusNode();
      final capture = GlobalKey();
      final theme = ThemeData.dark();
      addTearDown(width.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: Center(
                child: SizedBox(
          width: 300,
          height: 180,
          child: RepaintBoundary(
            key: capture,
            child: ThmrFocusLayer(
              child: RepaintBoundary(
                  child: ValueListenableBuilder<double>(
                valueListenable: width,
                child: FocusOutline(
                    child: Material(
                        child: InkWell(
                  focusNode: focus,
                  onTap: () {},
                  child: const SizedBox(height: 40),
                ))),
                builder: (_, value, child) => Center(
                  child: animated
                      ? AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: value,
                          child: child,
                        )
                      : SizedBox(width: value, child: child),
                ),
              )),
            ),
          ),
        ))),
      ));
      focus.requestFocus();
      await tester.pumpAndSettle();
      await _expectRingPixels(tester, capture, theme);
      for (final value in [140.0, 80.0, 200.0]) {
        width.value = value;
        if (animated) {
          await tester.pump();
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 60));
            await _expectRingPixels(tester, capture, theme);
          }
        } else {
          await tester.pumpAndSettle();
          await _expectRingPixels(tester, capture, theme);
        }
      }
    });
  }

  testWidgets('favorite ring follows label growth and shrink while focused',
      (tester) async {
    final favorite = ValueNotifier(false);
    final capture = GlobalKey();
    final theme = ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(primary: Color(0xFF4EA7D4)),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontFamily: 'Ahem', fontSize: 24, height: 1),
        bodySmall: TextStyle(fontFamily: 'Ahem', fontSize: 12, height: 1),
        labelSmall: TextStyle(
            fontFamily: 'Ahem', fontSize: 12, height: 1, letterSpacing: 0),
      ),
    );
    addTearDown(favorite.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeStationIdProvider.overrideWithValue('test'),
        favoritesStatusProvider.overrideWith((_) async => const FavoritesStatus(
              favorited: false,
              itemId: null,
              collectionId: null,
              collections: [],
            )),
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 300,
              child: RepaintBoundary(
                key: capture,
                child: ThmrFocusLayer(
                  child: RepaintBoundary(
                      child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: favorite,
                      builder: (_, value, __) => NowPlayingTrackInfo(
                        cur: const CurrentTrack(
                          trackId: 'test',
                          title: 'test',
                          artist: 'test',
                          coverUrl: '',
                          startedAtMs: 0,
                          expectedEndMs: 1,
                          positionSec: 0,
                          durationSec: 1,
                        ),
                        favorited: value,
                        onFavorite: () => favorite.value = !favorite.value,
                      ),
                    ),
                  )),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await _expectRingPixels(tester, capture, theme);
    final firstWidth = tester.getSize(_visibleRings).width;
    for (final label in ['已收藏', '收藏', '已收藏']) {
      await tester.tap(find.text(favorite.value ? '已收藏' : '收藏'));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(_visibleRings, findsOneWidget);
      expect(tester.getSize(_visibleRings).width,
          label == '收藏' ? firstWidth : greaterThan(firstWidth));
      await _expectRingPixels(tester, capture, theme);
    }
  });

  testWidgets('tab paints one ring per control without extra stops or resizing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThmrTheme.light(),
      home: Scaffold(
        body: Column(children: [
          FilledButton(onPressed: () {}, child: const Text('button')),
          FocusOutline(
            child: InkWell(
                onTap: () {}, child: const SizedBox(width: 80, height: 40)),
          ),
          FocusOutline(child: Switch(value: true, onChanged: (_) {})),
          const FilledButton(onPressed: null, child: Text('disabled')),
        ]),
      ),
    ));
    final size = tester.getSize(find.byType(Column));
    expect(_visibleRings, findsNothing);
    for (final control in [
      find.widgetWithText(FilledButton, 'button'),
      find.byType(FocusOutline).at(0),
      find.byType(FocusOutline).at(1),
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_visibleRings, findsOneWidget);
      expect(find.descendant(of: control, matching: _visibleRings),
          findsOneWidget);
      expect(tester.getSize(find.byType(Column)), size);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>()
            ?.onPressed,
        isNotNull);
  });

  testWidgets('menu entries and rail icons observe their owning focus node',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThmrTheme.dark(),
      home: Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: 0,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationRailDestination(
                icon: NavigationRailFocusIcon(icon: Icons.music_note),
                label: Text('music'),
              ),
              NavigationRailDestination(
                icon: NavigationRailFocusIcon(icon: Icons.settings),
                label: Text('settings'),
              ),
            ],
          ),
          FocusOutline(
            child: PopupMenuButton<int>(
              child: const Text('open menu'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 1,
                  child: AncestorFocusOutline(child: Text('entry')),
                ),
              ],
            ),
          ),
        ]),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_visibleRings, findsOneWidget);
    expect(
        find.ancestor(of: _visibleRings, matching: find.byType(NavigationRail)),
        findsOneWidget);
    final ringRect = tester.getRect(_visibleRings);
    expect(ringRect.size, const Size(56, 32));
    expect(ringRect.bottom + ThmrFocusRing.extent,
        lessThan(tester.getTopLeft(find.text('music')).dy));
    final ringPainter = tester
        .widget<CustomPaint>(find.descendant(
          of: _visibleRings,
          matching: find.byType(CustomPaint),
        ))
        .foregroundPainter!;
    expect(
        (Canvas canvas) => ringPainter.paint(canvas, ringRect.size),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(
              (Offset.zero & ringRect.size).inflate(2.5),
              const Radius.circular(18.5),
            ),
            strokeWidth: 1,
          ));
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_visibleRings, findsOneWidget);
    expect(
        find.ancestor(
            of: _visibleRings, matching: find.byType(PopupMenuItem<int>)),
        findsOneWidget);
  });

  testWidgets('segment outlines follow the full control bounds',
      (tester) async {
    final theme = ThmrTheme.light();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 1,
                label: AncestorFocusOutline(child: Text('one')),
              ),
              ButtonSegment(
                value: 2,
                label: AncestorFocusOutline(child: Text('two')),
              ),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    ));
    for (var index = 0; index < 2; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_visibleRings, findsOneWidget);
      final ring = tester.widget<ThmrFocusRing>(_visibleRings);
      final target = ring.focusNode!.context!.findRenderObject()! as RenderBox;
      final box = tester.renderObject<RenderBox>(_visibleRings);
      expect(target.size.width, greaterThan(box.size.width));
      final rect =
          box.globalToLocal(target.localToGlobal(Offset.zero)) & target.size;
      final painter = tester
          .widget<CustomPaint>(find.descendant(
            of: _visibleRings,
            matching: find.byType(CustomPaint),
          ))
          .foregroundPainter!;
      expect(
          (Canvas canvas) => painter.paint(canvas, box.size),
          paints
            ..rrect(
              rrect: RRect.fromRectAndRadius(
                  rect.inflate(2.5), const Radius.circular(10.5)),
              color: theme.colorScheme.primary,
              strokeWidth: 1,
            ));
    }
  });

  testWidgets('focused ring repaints when the accent or brightness changes',
      (tester) async {
    Future<CustomPainter> paint(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: const ThmrFocusRing(
          focused: true,
          child: SizedBox(width: 80, height: 40),
        ),
      ));
      return tester
          .widget<CustomPaint>(find.descendant(
            of: find.byType(ThmrFocusRing),
            matching: find.byType(CustomPaint),
          ))
          .foregroundPainter!;
    }

    final light = await paint(ThmrTheme.light());
    final dark = await paint(ThmrTheme.dark(AccentTheme.marisa));
    final otherAccent = await paint(ThmrTheme.dark(AccentTheme.sanae));
    expect(dark.shouldRepaint(light), isTrue);
    expect(otherAccent.shouldRepaint(dark), isTrue);
  });

  testWidgets('outward ring survives rounded and viewport clipping',
      (tester) async {
    final focus = FocusNode();
    final capture = GlobalKey();
    final theme = ThmrTheme.light();
    addTearDown(focus.dispose);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 120,
            child: RepaintBoundary(
              key: capture,
              child: ThmrFocusLayer(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 80,
                      height: 40,
                      child: SingleChildScrollView(
                        child: FilledButton(
                          focusNode: focus,
                          onPressed: () => taps++,
                          child: const Text('focus'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byType(OverlayPortal), findsNothing);
    await _expectRingPixels(tester, capture, theme);
    await tester.tap(find.text('focus'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.byType(CompositedTransformFollower), findsNothing);
  });

  testWidgets('ring follows scrolling and remains whole at the window edge',
      (tester) async {
    final focus = FocusNode();
    final scroll = ScrollController();
    final capture = GlobalKey();
    final theme = ThmrTheme.dark();
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 120,
            child: RepaintBoundary(
              key: capture,
              child: ThmrFocusLayer(
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 40),
                    FocusOutline(
                      child: Material(
                        child: InkWell(
                          focusNode: focus,
                          onTap: () {},
                          child: const SizedBox(height: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await _expectRingPixels(tester, capture, theme);
    scroll.jumpTo(40);
    await tester.pumpAndSettle();
    await _expectRingPixels(tester, capture, theme);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
