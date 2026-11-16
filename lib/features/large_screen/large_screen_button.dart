import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/desktop_window.dart';
import 'large_screen_controller.dart';
import 'large_screen_symbols.dart';

class LargeScreenButton extends ConsumerWidget {
  const LargeScreenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasDesktopWindowControls) return const SizedBox.shrink();
    final busy = ref.watch(largeScreenProvider.select((s) => s.busy));
    return IconButton(
      tooltip: '大屏幕模式',
      onPressed: busy
          ? null
          : () =>
              unawaited(ref.read(largeScreenProvider.notifier).change(true)),
      icon: const LargeScreenGlyph(LargeScreenSymbol.enter, size: 18),
      style: IconButton.styleFrom(
          minimumSize: const Size(34, 30),
          padding: const EdgeInsets.all(6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}
