import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/input/app_commands.dart';
import 'package:thmr_app/core/platform/linux_tray.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/shell/home_shell.dart';

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
      child: MaterialApp(
        theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
        home: const HomeShell(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('bottom navigation suppresses Material ink effects',
      (tester) async {
    await mount(tester);
    final item = find.byKey(const ValueKey('bottom-nav-item-1'));
    final ink = tester.widget<InkWell>(
      find.descendant(of: item, matching: find.byType(InkWell)),
    );
    expect(ink.splashFactory, NoSplash.splashFactory);
    expect(ink.splashColor, Colors.transparent);
    expect(ink.highlightColor, Colors.transparent);
    expect(ink.hoverColor, Colors.transparent);
    expect(ink.focusColor, Colors.transparent);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(container.read(appTabProvider), 0);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(container.read(appTabProvider), 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bottom navigation still activates from the keyboard',
      (tester) async {
    await mount(tester);
    final item = find.byKey(const ValueKey('bottom-nav-item-1'));
    final label = find.descendant(of: item, matching: find.text('曲库'));

    final focus = Focus.of(tester.element(label));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(container.read(appTabProvider), 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
