import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';

void main() {
  test('muting restores the previous nonzero volume', () {
    var state = const PlaybackState().copyWith(volume: 70);
    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volume, 0);
    expect(state.lastAudibleVolume, 70);

    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volume, 70);

    state = state.copyWith(volume: 35);
    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volumeAfterMuteToggle, 35);
  });

  test('track search text includes available fields only', () {
    expect(
      trackSearchText(title: '曲名', artist: '艺术家'),
      '曲名 - 艺术家',
    );
    expect(
      trackSearchText(title: ' 曲名 ', artist: '', album: ' 专辑 '),
      '曲名 · 专辑',
    );
  });
}
