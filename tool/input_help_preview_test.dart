// Run explicitly: flutter test tool/input_help_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/shared/widgets/input_help.dart';

void main() {
  testWidgets('export keyboard and gamepad input help', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Use a local CJK font for deterministic previews, without font downloads.
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('HelpPreview')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await tester.runAsync(loader.load);
    }
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final capture = GlobalKey();
      final brightness = dark ? Brightness.dark : Brightness.light;
      final tokens =
          ThmrTokens.resolve(AccentTheme.reimu, brightness).accessible();
      final theme = ThemeData(
        useMaterial3: true,
        brightness: brightness,
        fontFamily: 'HelpPreview',
        colorScheme: ColorScheme.fromSeed(
                seedColor: tokens.accent, brightness: brightness)
            .copyWith(
                primary: tokens.accent,
                onPrimary: tokens.onAccent,
                onSurface: tokens.ink,
                surface: tokens.solidPanel),
        scaffoldBackgroundColor: tokens.pageBg,
        dialogTheme: DialogThemeData(backgroundColor: tokens.solidPanel),
        textTheme: ThemeData(brightness: brightness).textTheme.apply(
            fontFamily: 'HelpPreview',
            bodyColor: tokens.ink,
            displayColor: tokens.ink),
        extensions: [tokens],
      );
      await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Builder(
                builder: (context) => Scaffold(
                    body: Center(
                        child: TextButton(
                            onPressed: () => showInputHelp(context),
                            child: const Text('open'))))),
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (dark) {
        await tester.tap(find.text('手柄'));
        await tester.pumpAndSettle();
      }
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      await tester.runAsync(() async {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
                'build/input-help-${dark ? 'gamepad-dark' : 'keyboard-light'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      image.dispose();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
