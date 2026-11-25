import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DesktopWindowTransition { largeScreen, miniPlayer }

/// 两种模式共用一个 Windows 窗口，从接收请求到原生操作结束只允许一方切换。
final desktopWindowTransitionProvider =
    StateProvider<DesktopWindowTransition?>((ref) => null);

final miniPlayerProvider = StateProvider<bool>((ref) => false);
