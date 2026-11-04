import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';

void main() {
  testWidgets('the home track card copies the title and artist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThmrTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 210,
            child: NowPlayingTrackInfo(
              cur: CurrentTrack(
                trackId: 'track-1',
                title: '幽雅に咲かせ、墨染の桜',
                artist: '上海アリス幻樂団',
                coverUrl: '',
                startedAtMs: 1,
                expectedEndMs: 2,
                positionSec: 0,
                durationSec: 240,
              ),
              favorited: false,
            ),
          ),
        ),
      ),
    ));

    expect(find.text('复制信息'), findsOneWidget);
    await tester.tap(find.text('复制信息'));
    await tester.pump();
    expect(copied, '幽雅に咲かせ、墨染の桜 - 上海アリス幻樂団');
    expect(find.text('歌曲信息已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
