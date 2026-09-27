import 'dart:async' show unawaited;
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/playback_controller.dart';
import '../../core/platform/windows_process_exit.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/station_provider.dart';
import '../../shared/widgets/player_dock_bar.dart';
import '../account/account_screen.dart';
import '../../core/theme/thmr_theme.dart';
import '../collections/collections_screen.dart';
import '../library/library_screen.dart';
import '../listen/listen_screen.dart';

/// 应用主壳:窄屏底部导航,宽屏(≥980px)左侧导航栏。
/// Offstage 保留各页状态;切换时对新激活页做轻量滑入过渡。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WindowListener, TrayListener {
  int _index = 0;
  bool _autoTried = false;
  bool _closing = false;
  bool get _isWindows => !kIsWeb && Platform.isWindows;

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
    setState(() {
      _index = i;
    });
  }

  /// Keep the transition wrapper mounted so each page retains its state.
  Widget _page(int i) {
    return _TabPage(
      key: ValueKey('tab-$i'),
      active: _index == i,
      child: _pages[i],
    );
  }

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _setupTray();
      // 关窗 → 隐藏到托盘(后台继续放送);退出走托盘菜单
      windowManager.setPreventClose(true).catchError((_) {});
    }
  }

  Future<void> _setupTray() async {
    try {
      // tray_manager (Windows) requires an .ico file on disk.
      final data = await rootBundle.load('assets/icons/thmr_tray.ico');
      final trayFile = File('${Directory.systemTemp.path}/thmr_tray.ico');
      await trayFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await trayManager.setIcon(trayFile.path);
      await trayManager.setToolTip('东方音乐电台 THMR');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(
            label: '显示主窗口',
            onClick: (_) async {
              await windowManager.show();
              await windowManager.focus();
            }),
        MenuItem.separator(),
        MenuItem(label: '退出', onClick: (_) => _reallyExit()),
      ]));
    } catch (_) {}
  }

  /// 真正退出(托盘菜单 / 关闭询问选「退出程序」时)。
  void _reallyExit({bool rememberChoice = false}) {
    if (_closing) return;
    _closing = true;
    if (rememberChoice) {
      unawaited(_rememberExitChoiceAndQuit());
      return;
    }
    terminateWindowsProcess();
  }

  Future<void> _rememberExitChoiceAndQuit() async {
    try {
      // Persist the selected preference, but never let a plugin call hold the
      // window open indefinitely while the user is trying to quit.
      await ref
          .read(settingsProvider.notifier)
          .setCloseAction(CloseAction.exit)
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Exiting takes priority if preferences cannot be written.
    } finally {
      terminateWindowsProcess();
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    // 关闭按钮:按用户偏好询问 / 直接退出 / 隐藏到托盘
    final action = ref.read(settingsProvider).closeAction;
    if (action == CloseAction.tray) {
      await windowManager.hide();
      return;
    }
    if (action == CloseAction.exit) {
      _reallyExit();
      return;
    }
    final picked = await _askCloseAction();
    if (picked == null) return; // 取消 → 什么都不做
    final (choice, remember) = picked;
    if (choice == CloseAction.tray) {
      if (remember) {
        await ref.read(settingsProvider.notifier).setCloseAction(choice);
      }
      await windowManager.hide();
    } else {
      _reallyExit(rememberChoice: remember);
    }
  }

  /// 关闭询问:返回 (选择, 是否记住);null = 取消。
  Future<(CloseAction, bool)?> _askCloseAction() {
    var remember = false;
    return showDialog<(CloseAction, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('关闭 东方音乐电台 THMR?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('最小化到托盘将保持后台放送,随时从托盘恢复。'),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Checkbox(
                      value: remember,
                      onChanged: (v) =>
                          setDialogState(() => remember = v ?? false),
                    ),
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
              label: const Text('最小化到托盘'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              // Exit directly, without waiting for the dialog route to pop.
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
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void dispose() {
    if (_isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-connect once, when station state is ready and user opted in.
    // 窄订阅:主壳只关心「是否可自动连播」,不随秒级播放 tick 重建。
    final settings = ref.watch(settingsProvider);
    final stationReady =
        ref.watch(stationProvider.select((s) => s.status != null));
    final (pbPhase, pbPaused) =
        ref.watch(playbackProvider.select((s) => (s.phase, s.userPaused)));
    if (!_autoTried &&
        settings.autoPlay &&
        stationReady &&
        pbPhase == PlaybackPhase.idle &&
        !pbPaused) {
      _autoTried = true;
      final url = ref.read(streamUrlProvider);
      if (url != null) {
        Future.microtask(() => ref.read(playbackProvider.notifier).tune(url));
      }
    }
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _pages.length; i++) _page(i),
      ],
    );
    return Stack(children: [
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final dock = _dockBar(compact: !wide);
        if (wide) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor:
                      Theme.of(context).thmr.solidPanel.withValues(alpha: 0.78),
                  selectedIndex: _index,
                  onDestinationSelected: _switchTo,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 10),
                    child: Image.asset('assets/brand/logo.png', width: 44),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: stack),
                      dock,
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: stack,
          bottomNavigationBar: Column(
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
    ]);
  }

  /// 底部常驻播放条:非收听页时出现(AnimatedSize 平滑展开)。
  Widget _dockBar({required bool compact}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
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

/// A persistent tab surface with a short entrance animation.
class _TabPage extends StatefulWidget {
  const _TabPage({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.active ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.forward();
  }

  @override
  void didUpdateWidget(covariant _TabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? widget.child
        : FadeTransition(
            opacity: _c.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: SlideTransition(
              position: _c.drive(Tween<Offset>(
                begin: const Offset(0, 0.014),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic))),
              child: widget.child,
            ),
          );
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(
        enabled: widget.active,
        child: animation,
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
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onChanged(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
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
                              color: index == i ? tokens.ink : tokens.mutedInk,
                              fontWeight: index == i
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
