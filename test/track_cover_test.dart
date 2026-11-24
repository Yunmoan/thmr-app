import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';

const _first = 'https://cover.test/first.png';
const _second = 'https://cover.test/second.png';

Future<Completer<ImageInfo>> _pending(String url, {int width = 56}) async {
  final key = await TrackCover.providerFor(url, cacheWidth: width)
      .obtainKey(ImageConfiguration.empty);
  final result = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache
      .putIfAbsent(key, () => OneFrameImageStreamCompleter(result.future));
  return result;
}

Future<ui.Image> _image(WidgetTester tester, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(56, 56));
  picture.dispose();
  return image!;
}

Widget _host(String url, {bool reduced = false, double size = 56}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Center(child: TrackCover(url: url, size: size)),
      ),
    );

Finder _pixels(ui.Image image) => find.byWidgetPredicate((widget) =>
    widget is RawImage && (widget.image?.isCloneOf(image) ?? false));

double _opacity(WidgetTester tester, ui.Image image) {
  final pixels = _pixels(image);
  if (pixels.evaluate().isEmpty) return 0;
  var opacity = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: pixels, matching: find.byType(FadeTransition)))) {
    opacity *= fade.opacity.value;
  }
  return opacity;
}

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final reduced in [false, true]) {
    testWidgets('placeholder waits for decoded cover with reduced=$reduced',
        (tester) async {
      final fallback = await _image(tester, Colors.white);
      final cover = await _image(tester, Colors.red);
      (await _pending('')).complete(ImageInfo(image: fallback));
      final pending = await _pending(_first);

      await tester.pumpWidget(_host(_first, reduced: reduced));
      await tester.pumpAndSettle();
      expect(_opacity(tester, fallback), 1);
      expect(_pixels(cover), findsNothing);
      expect(tester.getSize(find.byType(TrackCover)), const Size(56, 56));
      await tester.pump(const Duration(seconds: 2));
      expect(_opacity(tester, fallback), 1,
          reason: 'Elapsed time alone must not dismiss the placeholder.');

      pending.complete(ImageInfo(image: cover));
      await tester.pump();
      await tester.pump();
      await tester.pump(ThmrMotion.duration ~/ 3);
      expect(_opacity(tester, cover), reduced ? 1 : inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_opacity(tester, cover), 1);
      expect(_pixels(fallback), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new source clears old cover and ignores late previous results',
      (tester) async {
    final fallback = await _image(tester, Colors.white);
    final first = await _image(tester, Colors.red);
    final second = await _image(tester, Colors.blue);
    (await _pending('')).complete(ImageInfo(image: fallback));
    final oldRequest = await _pending(_first);
    final newRequest = await _pending(_second);
    final thirdRequest = await _pending('https://cover.test/third.png');

    await tester.pumpWidget(_host(_first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(_second));
    await tester.pumpAndSettle();
    oldRequest.complete(ImageInfo(image: first));
    await tester.pumpAndSettle();
    expect(_opacity(tester, fallback), 1);
    expect(_pixels(first), findsNothing);
    newRequest.complete(ImageInfo(image: second));
    await tester.pumpAndSettle();
    expect(_opacity(tester, second), 1);

    await tester.pumpWidget(_host(_first));
    expect(_opacity(tester, first), 1);
    await tester.pumpWidget(_host('https://cover.test/third.png'));
    expect(_opacity(tester, fallback), 1);
    expect(_pixels(first), findsNothing,
        reason:
            'A loaded old cover must disappear as soon as its URL changes.');
    await tester.pumpWidget(_host(''));
    thirdRequest.complete(ImageInfo(image: second.clone()));
    await tester.pump();
    expect(_opacity(tester, fallback), 1);
    expect(_pixels(first), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed cover keeps the placeholder', (tester) async {
    final fallback = await _image(tester, Colors.white);
    (await _pending('')).complete(ImageInfo(image: fallback));
    final pending = await _pending(_first);
    await tester.pumpWidget(_host(_first));
    await tester.pumpAndSettle();
    pending.completeError(StateError('cover unavailable'));
    await tester.pumpAndSettle();
    expect(_opacity(tester, fallback), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed resize retains the current cover until another decodes',
      (tester) async {
    final original = await _image(tester, Colors.red);
    final resized = await _image(tester, Colors.blue);
    (await _pending(_first)).complete(ImageInfo(image: original));
    final failed = await _pending(_first, width: 112);
    final next = await _pending(_first, width: 128);

    await tester.pumpWidget(_host(_first));
    await tester.pumpAndSettle();
    expect(_opacity(tester, original), 1);

    await tester.pumpWidget(_host(_first, size: 112));
    failed.completeError(StateError('cover resize failed'));
    await tester.pumpAndSettle();
    expect(_opacity(tester, original), 1);

    await tester.pumpWidget(_host(_first, size: 128));
    expect(_opacity(tester, original), 1);
    next.complete(ImageInfo(image: resized));
    await tester.pumpAndSettle();
    expect(_opacity(tester, resized), 1);
    expect(_pixels(original), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
