import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/state/auth_provider.dart';
import '../../core/state/settings_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../core/update/app_update.dart';
import '../../shared/widgets/thmr_panel.dart';
import 'about_panel.dart';
import 'login_screen.dart';
import 'update_panel.dart';

/// 「我的」:账号(WebView 登录 M2 接入)+ 偏好设置 + 关于。
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// Keep the login flow on this screen: the signed-out card is replaced as
  /// soon as authentication succeeds, while this context remains mounted.
  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (token == null || token.isEmpty) return;
    try {
      await ref.read(authProvider.notifier).signInWithToken(token);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登录成功,欢迎回到幻想乡')));
      final user = ref.read(authProvider).user;
      if (user?.needsNickname == true) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('设置昵称'),
            content: const Text('首次登录需要设置一个昵称(2–64 字符)。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (context.mounted && ref.read(authProvider).user != null) {
          await _editNickname(context, ref, '');
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登录状态校验失败,请重试')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    final miniSize = ref.watch(miniPlayerSizeProvider);
    final tokens = Theme.of(context).thmr;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          Text('我的',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          // 账号卡
          ThmrPanel(
            child: auth.signedIn
                ? _SignedInBody(auth: auth)
                : _SignedOutBody(onLogin: () => _login(context, ref)),
          ),
          const SizedBox(height: 18),
          // 外观
          const SectionHeader(title: '外观'),
          ThmrPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.contrast_rounded, size: 20, color: tokens.mutedInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('主题',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600, color: tokens.ink)),
                ),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 17),
                        label: Text('浅色')),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 17),
                        label: Text('深色')),
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.settings_suggest_outlined, size: 17),
                        label: Text('跟随')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      ref.read(settingsProvider.notifier).setThemeMode(s.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ThmrPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('角色主题',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: tokens.ink)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in AccentTheme.values)
                      ChoiceChip(
                        selected: settings.accentTheme == t,
                        onSelected: (_) => ref
                            .read(settingsProvider.notifier)
                            .setAccentTheme(t),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _accentDot(t),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(_accentLabel(t)),
                          ],
                        ),
                      ),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        size: 20, color: tokens.mutedInk),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('自动播放',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: tokens.ink)),
                          Text('启动后自动连接放送(移动端可能需手动点击)',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: tokens.mutedInk)),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.autoPlay,
                      onChanged: (v) =>
                          ref.read(settingsProvider.notifier).setAutoPlay(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!kIsWeb && Platform.isWindows) ...[
            const SizedBox(height: 14),
            ThmrPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniSizeAndEdgeSettings(
                    settings: settings,
                    size: miniSize,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.wallpaper_rounded,
                          size: 20, color: tokens.mutedInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('迷你播放器人物立绘',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: tokens.ink)),
                            Text('跟随当前主题，淡化显示在内容后方',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: tokens.mutedInk)),
                          ],
                        ),
                      ),
                      Switch(
                        value: settings.miniShowIllustration,
                        onChanged: (value) => ref
                            .read(settingsProvider.notifier)
                            .setMiniShowIllustration(value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ThmrPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.logout_rounded, size: 20, color: tokens.mutedInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('关闭按钮',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: tokens.ink)),
                        Text('点击窗口关闭键时的行为',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: tokens.mutedInk)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final a in CloseAction.values)
                              ChoiceChip(
                                label: Text(switch (a) {
                                  CloseAction.ask => '每次询问',
                                  CloseAction.exit => '退出程序',
                                  CloseAction.tray => '最小化到托盘',
                                }),
                                selected: settings.closeAction == a,
                                onSelected: (_) => ref
                                    .read(settingsProvider.notifier)
                                    .setCloseAction(a),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!kIsWeb && Platform.isAndroid) ...[
            const SizedBox(height: 14),
            ThmrPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.battery_saver_rounded,
                      size: 20, color: tokens.mutedInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('保持后台连续放送',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.ink)),
                        const SizedBox(height: 3),
                        Text(
                          '建议将本应用的电池策略设为「无限制」:系统设置 → 应用 → 东方音乐电台 → 电池 → 无限制,否则熄屏后放送可能被系统中断。',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: tokens.mutedInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const SectionHeader(title: '关于'),
          AboutPanel(
              version: ref.watch(clientVersionProvider).valueOrNull?.label),
          const UpdatePanel(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _MiniSizeAndEdgeSettings extends ConsumerWidget {
  const _MiniSizeAndEdgeSettings({required this.settings, required this.size});

  final AppSettings settings;
  final MiniPlayerSizePreset size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final heading = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: tokens.ink,
        );
    final caption = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: tokens.mutedInk);
    final sizeDescription = switch (size) {
      MiniPlayerSizePreset.small => '小号 320×96',
      MiniPlayerSizePreset.medium => '中号 344×112',
      MiniPlayerSizePreset.large => '大号 384×132',
    };
    final edgeDescription = switch (settings.miniEdgeHideMode) {
      MiniEdgeHideMode.compact => '顶边保留封面、歌名和作者',
      MiniEdgeHideMode.tab => '悬停或点击小条展开',
      MiniEdgeHideMode.hidden => '原位置悬停唤出',
    };
    final sizeChoice = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('窗口尺寸', style: heading),
        const SizedBox(height: 8),
        SegmentedButton<MiniPlayerSizePreset>(
          segments: const [
            ButtonSegment(value: MiniPlayerSizePreset.small, label: Text('小')),
            ButtonSegment(value: MiniPlayerSizePreset.medium, label: Text('中')),
            ButtonSegment(value: MiniPlayerSizePreset.large, label: Text('大')),
          ],
          selected: {size},
          onSelectionChanged: (sizes) =>
              ref.read(miniPlayerSizeProvider.notifier).setSize(sizes.first),
        ),
        const SizedBox(height: 6),
        Text('$sizeDescription · 下次进入生效', style: caption),
      ],
    );
    final edgeChoice = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('吸边方式', style: heading),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final mode in MiniEdgeHideMode.values) ...[
              if (mode != MiniEdgeHideMode.compact) const SizedBox(width: 8),
              Expanded(
                child: _MiniEdgeChoice(
                  mode: mode,
                  selected: settings.miniEdgeHideMode == mode,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setMiniEdgeHideMode(mode),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text('$edgeDescription · 顶边优先', style: caption),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 650) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sizeChoice,
            const Divider(height: 22),
            edgeChoice,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 245, child: sizeChoice),
          const SizedBox(width: 18),
          Expanded(child: edgeChoice),
        ],
      );
    });
  }
}

class _MiniEdgeChoice extends StatelessWidget {
  const _MiniEdgeChoice({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final MiniEdgeHideMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final accent = Theme.of(context).colorScheme.primary;
    final (label, caption, svg) = switch (mode) {
      MiniEdgeHideMode.compact => (
          '二段式摘要',
          '顶边显示封面、歌名和作者；侧边显示小条',
          'assets/icons/mini_edge_compact.svg',
        ),
      MiniEdgeHideMode.tab => (
          '显示小条',
          '悬停或点击即可展开',
          'assets/icons/mini_edge_tab.svg',
        ),
      MiniEdgeHideMode.hidden => (
          '完全隐藏',
          '原位置悬停唤出，也可从托盘恢复',
          'assets/icons/mini_edge_hidden.svg',
        ),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label，$caption',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : tokens.panelSoft,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? accent : tokens.panelBorder,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                svg,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  selected ? accent : tokens.mutedInk,
                  BlendMode.srcIn,
                ),
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: tokens.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedOutBody extends ConsumerWidget {
  const _SignedOutBody({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final tokens = Theme.of(context).thmr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: tokens.accentSoft,
              child: Icon(Icons.person_outline_rounded,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('未登录',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text('使用 Natayark 账号登录后可收藏、投票',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.mutedInk)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: auth.loggingIn ? null : onLogin,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('使用 Natayark 账号登录'),
          ),
        ),
      ],
    );
  }
}

Color _accentDot(AccentTheme t) => switch (t) {
      AccentTheme.reimu => const Color(0xFFC65A69),
      AccentTheme.marisa => const Color(0xFFD9A43C),
      AccentTheme.cirno => const Color(0xFF4E9FD4),
    };

String _accentLabel(AccentTheme t) => switch (t) {
      AccentTheme.reimu => '灵梦 · 绯红',
      AccentTheme.marisa => '魔理沙 · 星尘',
      AccentTheme.cirno => '琪露诺 · 冰蓝',
    };

/// Nickname editor dialog shared by settings & first-login gate.
Future<void> _editNickname(
    BuildContext context, WidgetRef ref, String current) async {
  final controller = TextEditingController(text: current);
  var ok = false;
  while (true) {
    if (!context.mounted) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('设置昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: Theme.of(context).thmr.ink),
          decoration:
              const InputDecoration(labelText: '昵称(2–64 字符)', counterText: ''),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (submitted != true) return;
    final name = controller.text.trim();
    if (name.length < 2) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称至少 2 个字符')));
      continue;
    }
    try {
      await ref.read(authProvider.notifier).setNickname(name);
      ok = true;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败,昵称可能包含违规内容')));
      continue;
    }
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称已更新')));
    }
    return;
  }
}

class _SignedInBody extends ConsumerWidget {
  const _SignedInBody({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = auth.user!;
    final tokens = Theme.of(context).thmr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: tokens.accentSoft,
              child: Text(
                user.displayName.characters.first.toUpperCase(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text('@${user.username} · ${user.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.mutedInk)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _editNickname(context, ref, user.nickname),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('改昵称'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定要退出当前账号吗?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('退出')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('退出登录'),
            ),
          ],
        ),
      ],
    );
  }
}
