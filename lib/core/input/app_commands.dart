import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppCommand {
  up,
  down,
  left,
  right,
  activate,
  back,
  previousTab,
  nextTab,
  tab,
  search,
  playPause,
  mute,
  volumeUp,
  volumeDown,
  mini,
  help,
  scrollUp,
  scrollDown,
}

class AppCommandIntent extends Intent {
  const AppCommandIntent(this.command, [this.index]);
  final AppCommand command;
  final int? index;
}

final appTabProvider = StateProvider<int>((ref) => 0);

final librarySearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: '曲库搜索');
  ref.onDispose(node.dispose);
  return node;
});
