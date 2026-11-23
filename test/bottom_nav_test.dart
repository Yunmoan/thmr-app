import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/platform/linux_tray.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/shell/home_shell.dart';

const _captureKey = ValueKey('bottom-nav-capture');

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station() : super(const StationUiState(initialLoading: false));

  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState(phase: PlaybackPhase.online));

  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RadioApi extends RadioApi {
  @override
  Future<int> siteListeners() async => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stationProvider.overrideWith((ref) => _Station()),
        playbackProvider.overrideWith((ref) => _Playback()),
        radioSourceProvider.overrideWith((ref) =>
            RadioSourceController(preference: RadioSourcePreference.source1)),
        radioApiProvider.overrideWithValue(_RadioApi()),
        channelCatalogProvider.overrideWith((ref) async => []),
        desktopTrayAvailableProvider.overrideWith((ref) => false),
      ],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
          home: const HomeShell(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('hovering and pressing a bottom tab leave its appearance intact',
      (tester) async {
    await mount(tester);
    final item = find.byKey(const ValueKey('bottom-nav-item-1'));
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    final rect =
        tester.getRect(item).shift(-boundary.localToGlobal(Offset.zero));

    Future<ByteData?> pixels() => tester.runAsync(() async {
          final layer = boundary.debugLayer! as OffsetLayer;
          final image = await layer.toImage(rect);
          try {
            return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba))!;
          } finally {
            image.dispose();
          }
        });

    final before = (await pixels())!;
    final center = tester.getCenter(item);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(center);
    await tester.pumpAndSettle();
    expect((await pixels())!.buffer.asUint8List(), before.buffer.asUint8List());
    await mouse.removePointer();
    final press = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect((await pixels())!.buffer.asUint8List(), before.buffer.asUint8List());
    await press.up();
    await tester.pumpAndSettle();
    expect(find.text('曲库搜索需要登录后使用'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bottom navigation still activates from the keyboard',
      (tester) async {
    await mount(tester);
    final label = find.text('曲库');
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('曲库搜索需要登录后使用'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
