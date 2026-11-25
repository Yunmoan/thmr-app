import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../core/theme/thmr_motion.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/playback_controller.dart';
import '../../core/input/app_commands.dart';
import '../../core/player/audio_engine.dart';
import '../../core/platform/desktop_window.dart';
import '../../core/platform/desktop_tray.dart';
import '../../core/platform/linux_tray.dart';
import '../../core/player/shared_radio_stream.dart';
import '../../core/player/spectrum_linux.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/station_provider.dart';
import '../../core/state/radio_source_provider.dart';
import '../../shared/widgets/player_dock_bar.dart';
import '../../shared/widgets/persistent_tab_page.dart';
import '../../shared/widgets/focus_outline.dart';
import '../account/account_screen.dart';
import '../../core/theme/thmr_theme.dart';
import '../collections/collections_screen.dart';
import '../library/library_screen.dart';
import '../listen/listen_screen.dart';
import '../mini/mini_player.dart' show miniPlayerProvider;
import '../large_screen/large_screen_surface.dart';

/// 窄屏采用底部导航。从 980 逻辑像素起改用左侧导航栏。
/// Offstage 保留各页状态，切换时仅对新激活的页面执行滑入过渡。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WindowListener {
  int get _index => ref.read(appTabProvider);
  final _pageFocus = List.generate(
      4,
      (i) => FocusScopeNode(
            debugLabel: '主页面 $i',
            traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
            directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
          ));
  bool _autoTried = false;
  bool _closing = false;
  bool _closeDialogOpen = false;
  bool _hiddenToTray = false;
  bool _trayReady = false;
  LinuxTrayMonitor? _trayMonitor;
  late final _tray = DesktopTrayController(
    showWindow: () async {
      _hiddenToTray = false;
      await restoreDesktopWindow();
    },
    exitApplication: _reallyExit,
  );

  static const _destinations = [
    (icon: Icons.radio_outlined, selected: Icons.radio, label: '收听'),
    (
      icon: Icons.library_music_outlined,
      selected: Icons.library_music,
      label: '曲库'
    ),
    (
      icon: Icons.bookmark_border_rounded,
      selected: Icons.bookmark_rounded,
      label: '收藏'
    ),
    (
      icon: Icons.person_outline_rounded,
      selected: Icons.person_rounded,
      label: '我的'
    ),
  ];

  static final _pages = [
    const ListenScreen(),
    const LibraryScreen(),
    const CollectionsScreen(),
    const AccountScreen(),
  ];

  void _switchTo(int i) {
    if (i == _index) return;
    ref.read(appTabProvider.notifier).state = i;
  }

  /// 保持过渡容器挂载，以保留各页状态。
  Widget _page(int i) {
    return PersistentTabPage(
      key: ValueKey('tab-$i'),
      active: _index == i,
      child: FocusScope(
          node: _pageFocus[i], child: FocusTraversalGroup(child: _pages[i])),
    );
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        unawaited(ref.read(radioSourceProvider.notifier).ensureSelected());
      }
    });
    if (hasDesktopWindowControls) {
      windowManager.addListener(this);
      unawaited(_setupTray());
      if (_tray.platform == TargetPlatform.linux) {
        _trayMonitor = LinuxTrayMonitor()
          ..addListener(_trayAvailabilityChanged);
        unawaited(_trayMonitor!.start());
      }
      // 关窗 → 隐藏到托盘(后台继续放送);退出走托盘菜单
      windowManager.setPreventClose(true).catchError((_) {});
    }
  }

  Future<void> _setupTray() async {
    _trayReady = await _tray.start();
    if (!_trayReady) {
      _trayMonitor?.dispose();
      _trayMonitor = null;
    }
    _trayAvailabilityChanged();
  }

  void _trayAvailabilityChanged() {
    if (!mounted || _closing || _tray.isDisposed) return;
    final available = _trayReady &&
        (_tray.platform != TargetPlatform.linux ||
            (_trayMonitor?.value ?? false));
    ref.read(desktopTrayAvailableProvider.notifier).state = available;
    if (!available && _hiddenToTray) {
      _hiddenToTray = false;
      unawaited(_minimizeToTaskbar());
    }
  }

  Future<void> _minimizeToTaskbar() async {
    await restoreDesktopWindow();
    await windowManager.minimize();
  }

  Future<void> _hideOrMinimize() async {
    await _trayMonitor?.refresh();
    if (!mounted || _closing) return;
    if (ref.read(desktopTrayAvailableProvider)) {
      _hiddenToTray = true;
      await windowManager.hide();
      // 隐藏窗口期间，承载托盘图标的面板服务可能退出。隐藏后再检查一次。
      if (!ref.read(desktopTrayAvailableProvider)) {
        _hiddenToTray = false;
        await _minimizeToTaskbar();
      }
    } else {
      await _minimizeToTaskbar();
    }
  }

  /// 真正退出(托盘菜单 / 关闭询问选「退出程序」时)。
  void _reallyExit({bool rememberChoice = false}) {
    if (_closing) return;
    _closing = true;
    if (rememberChoice) {
      unawaited(_rememberExitChoiceAndQuit());
      return;
    }
    unawaited(_quit());
  }

  Future<void> _rememberExitChoiceAndQuit() async {
    try {
      // 尝试保存所选偏好，并限制等待时长，避免插件调用卡住退出流程。
      await ref
          .read(settingsProvider.notifier)
          .setCloseAction(CloseAction.exit)
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // 偏好写入失败时仍继续退出。
    } finally {
      await _quit();
    }
  }

  Future<void> _quit() => quitDesktopApplication(() async {
        _trayMonitor?.dispose();
        _trayMonitor = null;
        await ref.read(playbackProvider.notifier).stop();
        if (_tray.platform == TargetPlatform.linux) {
          await LinuxSpectrum.instance.dispose();
        }
        await disposeSystemMediaControls();
        await sharedRadioStream.dispose();
        await _tray.dispose();
      });

  @override
  void onWindowClose() async {
    if (_closing || _closeDialogOpen || _tray.isDisposed) return;
    // 关闭按钮:按用户偏好询问 / 直接退出 / 隐藏到托盘
    final action = ref.read(settingsProvider).closeAction;
    if (action == CloseAction.tray) {
      await _hideOrMinimize();
      return;
    }
    if (action == CloseAction.exit) {
      _reallyExit();
      return;
    }
    _closeDialogOpen = true;
    final picked = await _askCloseAction();
    _closeDialogOpen = false;
    if (!mounted || _closing) return;
    if (picked == null) return; // 取消 → 什么都不做
    final (choice, remember) = picked;
    if (choice == CloseAction.tray) {
      if (remember) {
        await ref.read(settingsProvider.notifier).setCloseAction(choice);
      }
      await _hideOrMinimize();
    } else {
      _reallyExit(rememberChoice: remember);
    }
  }

  /// 关闭确认框返回（所选操作，是否记住），取消时返回 null。
  Future<(CloseAction, bool)?> _askCloseAction() {
    var remember = false;
    final trayAvailable = ref.read(desktopTrayAvailableProvider);
    final isMacOS = _tray.platform == TargetPlatform.macOS;
    return showThmrDialog<(CloseAction, bool)>(
      animationStyle: ThmrMotion.style(context),
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('关闭 东方音乐电台 THMR?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isMacOS
                  ? trayAvailable
                      ? '隐藏到菜单栏后将继续放送，可从菜单栏图标或 Dock 恢复窗口。'
                      : '菜单栏图标暂不可用，将最小化到 Dock 并继续放送。'
                  : trayAvailable
                      ? '最小化到托盘将保持后台放送,随时从托盘恢复。'
                      : '当前桌面托盘不可用，将最小化到任务栏并继续放送。'),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    FocusOutline(
                        child: Checkbox(
                      value: remember,
                      onChanged: (v) =>
                          setDialogState(() => remember = v ?? false),
                    )),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('不再提醒,以后按此次选择执行'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(dialogContext).pop((CloseAction.tray, remember)),
              icon: const Icon(Icons.call_received_rounded, size: 16),
              label: Text(desktopTrayActionLabel(available: trayAvailable)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              // 直接发起退出，无需等待弹窗路由出栈。
              onPressed: () => _reallyExit(rememberChoice: remember),
              icon: const Icon(Icons.power_settings_new_rounded, size: 16),
              label: const Text('退出程序'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void onWindowFocus() {
    _hiddenToTray = false;
  }

  @override
  void dispose() {
    for (final node in _pageFocus) {
      node.dispose();
    }
    _trayMonitor?.dispose();
    if (hasDesktopWindowControls) {
      windowManager.removeListener(this);
      unawaited(_tray.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(appTabProvider);
    ref.listen(appTabProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(miniPlayerProvider)) {
          _pageFocus[next].requestFocus();
        }
      });
    });
    // 用户启用自动播放后，等频道状态和播放源就绪再尝试一次。这里仅读取自动播放所需状态，
    // 避免每秒重建主界面。
    final autoPlay = ref.watch(settingsProvider.select((s) => s.autoPlay));
    final stationReady =
        ref.watch(stationProvider.select((s) => s.status != null));
    final sourceReady =
        ref.watch(radioSourceProvider.select((source) => source.ready));
    final (pbPhase, pbPaused) =
        ref.watch(playbackProvider.select((s) => (s.phase, s.userPaused)));
    if (!_autoTried &&
        autoPlay &&
        stationReady &&
        sourceReady &&
        pbPhase == PlaybackPhase.idle &&
        !pbPaused) {
      final url = ref.read(streamUrlProvider);
      if (url != null) {
        _autoTried = true;
        Future.microtask(() => ref.read(playbackProvider.notifier).tune(url));
      }
    }
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _pages.length; i++) _page(i),
      ],
    );
    return LargeScreenSurface(
        child: Stack(children: [
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final dock = _dockBar(compact: !wide);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  backgroundColor:
                      Theme.of(context).thmr.solidPanel.withValues(alpha: 0.78),
                  selectedIndex: index,
                  onDestinationSelected: _switchTo,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 10),
                    child: Image.asset('assets/brand/logo.png', width: 44),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: NavigationRailFocusIcon(icon: d.icon),
                        selectedIcon: NavigationRailFocusIcon(icon: d.selected),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
              ],
              // 宽窄布局共用同一棵页面树，跨断点时保留搜索、滚动和进行中的请求。
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: stack),
                    if (wide) dock,
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dock,
                    _ThmrNavBar(
                      destinations: _destinations,
                      index: _index,
                      onChanged: _switchTo,
                    ),
                  ],
                ),
        );
      }),
    ]));
  }

  /// 非收听页显示底部播放器，由共用的尺寸过渡处理展开收起。
  Widget _dockBar({required bool compact}) {
    return ThmrAnimatedSize(
      alignment: Alignment.bottomCenter,
      child: _index == 0
          ? const SizedBox(width: double.infinity)
          : PlayerDockBar(
              compact: compact,
              onOpenPlayer: () => _switchTo(0),
            ),
    );
  }
}

/// 手机端底栏:胶囊包裹图标 + 独立文字层,选中层级清晰。
class _ThmrNavBar extends StatelessWidget {
  const _ThmrNavBar({
    required this.destinations,
    required this.index,
    required this.onChanged,
  });

  final List<({IconData icon, IconData selected, String label})> destinations;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: tokens.solidPanel,
        border: Border(top: BorderSide(color: tokens.panelBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: (48 + MediaQuery.textScalerOf(context).scale(11) * 1.1)
              .clamp(62.0, double.infinity),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  key: ValueKey('bottom-nav-item-$i'),
                  child: FocusOutline(
                      child: Material(
                    color: Colors.transparent,
                    child: Semantics(
                      selected: index == i,
                      button: true,
                      child: InkWell(
                        onTap: () => onChanged(i),
                        // 胶囊选中动画在各平台共用，已提供点击反馈，
                        // 因此关闭 Material 自带的水波纹和高亮。
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : ThmrMotion.duration,
                              curve: ThmrMotion.enterCurve,
                              padding: EdgeInsets.symmetric(
                                horizontal: index == i ? 18 : 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: index == i
                                    ? tokens.accentSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Icon(
                                index == i
                                    ? destinations[i].selected
                                    : destinations[i].icon,
                                size: 21,
                                color: index == i ? accent : tokens.mutedInk,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              destinations[i].label,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                color:
                                    index == i ? tokens.ink : tokens.mutedInk,
                                fontWeight: index == i
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
