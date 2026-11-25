import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/state/app_providers.dart';
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

class _LibraryApi extends ThmrApi {
  int searches = 0;
  final result = Completer<List<LibraryTrack>>();
  String? addedTo;
  final writeFinished = Completer<void>();
  final track = LibraryTrack.fromJson({'trackId': 'track', 'title': '搜索结果'});
  @override
  Future<ThmrUser> me() async =>
      ThmrUser.fromJson({'id': 'listener', 'username': 'listener'});
  @override
  Future<List<LibraryTrack>> searchTracks(
      {required String stationId,
      required String q,
      int page = 1,
      int pageSize = 50,
      String sort = 'title'}) {
    searches++;
    return result.future;
  }

  @override
  Future<List<Collection>> collections() async => List.generate(
      15,
      (i) => Collection.fromJson(
          {'id': '$i', 'name': '歌单 $i', 'itemCount': addedTo == '$i' ? 1 : 0}));
  @override
  Future<(Collection, List<CollectionItem>)> collectionDetail(String cid,
          {String sort = 'position', String order = 'asc'}) async =>
      (
        (await collections()).firstWhere((folder) => folder.id == cid),
        <CollectionItem>[]
      );
  @override
  Future<CollectionItem> addToCollection(String cid,
      {required String stationId, required String trackId}) async {
    await writeFinished.future;
    addedTo = cid;
    return CollectionItem.fromJson(
        {'id': 'item', 'trackId': trackId, 'stationId': stationId});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mount(WidgetTester tester, {_LibraryApi? library}) async {
    SharedPreferences.setMockInitialValues(
        {if (library != null) 'thmr_session_token': 'test'});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        if (library != null) ...[
          authProvider.overrideWith((ref) => AuthController(client: library)),
          favoritesStatusProvider
              .overrideWith((ref) async => FavoritesStatus.fromJson({
                    'collections': [
                      {
                        'collectionId': '14',
                        'favorited': library.addedTo == '14'
                      }
                    ]
                  })),
        ],
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

  testWidgets('library search survives resizing during and after the request',
      (tester) async {
    final api = _LibraryApi();
    await mount(tester, library: api);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '上海');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('上海'), findsOneWidget);
    api.result.complete([api.track]);
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('上海'), findsOneWidget);
    expect(find.text('搜索结果'), findsOneWidget);
    expect(api.searches, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'last folder is selectable and a dismissed sheet still refreshes favorites',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _LibraryApi();
    api.result.complete([api.track]);
    await mount(tester, library: api);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final favorite = container.listen(favoritesStatusProvider, (_, __) {});
    addTearDown(favorite.close);
    expect(
        (await container.read(favoritesStatusProvider.future))
            .collections
            .single
            .favorited,
        isFalse);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-item-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '上海');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加到收藏夹'));
    await tester.pumpAndSettle();
    final last = find.text('歌单 14');
    await tester.scrollUntilVisible(last, 220,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    await tester.tap(last);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    api.writeFinished.complete();
    await tester.pumpAndSettle();
    expect(api.addedTo, '14');
    expect(
        (await container.read(collectionsProvider.future))
            .collections
            .last
            .itemCount,
        1);
    expect(
        (await container.read(favoritesStatusProvider.future))
            .collections
            .single
            .favorited,
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
