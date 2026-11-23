import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/settings_provider.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/focus_outline.dart';
import '../../shared/widgets/thmr_panel.dart';

/// 在同一个响应式面板展示应用信息、项目链接和贡献者。
class AboutPanel extends ConsumerStatefulWidget {
  const AboutPanel({super.key, this.version});

  final String? version;

  @override
  ConsumerState<AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends ConsumerState<AboutPanel> {
  int _versionTaps = 0;
  Timer? _resetTaps;
  bool _saving = false;

  void _tapVersion() {
    _resetTaps?.cancel();
    if (++_versionTaps == 7) {
      _versionTaps = 0;
      unawaited(_setDeveloperMode(true));
    } else {
      _resetTaps = Timer(const Duration(seconds: 2), () => _versionTaps = 0);
    }
  }

  Future<void> _setDeveloperMode(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (enabled) {
        final confirmed = await showThmrDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('启用开发者模式？'),
            content: const Text('启用后窗口顶部会显示黄灰斜纹。你可以在「关于」中关闭。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('启用'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      await ref.read(settingsProvider.notifier).setDeveloperMode(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showThmrSnackBar(
          context,
          const SnackBar(content: Text('无法保存开发者模式设置，请重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _resetTaps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final enabled = ref.watch(settingsProvider.select((s) => s.developerMode));
    final showSwitch =
        enabled || ref.read(settingsProvider.notifier).debugBuild;
    return ThmrPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child:
                    Image.asset('assets/brand/logo.png', width: 48, height: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('东方音乐电台 THMR',
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: tokens.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Touhou Music Radio · 跨平台客户端',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: tokens.mutedInk)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FocusOutline(
            child: Material(
              color: tokens.accentSoft,
              shape: StadiumBorder(side: BorderSide(color: tokens.panelBorder)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: !showSwitch && !_saving && widget.version != null
                    ? _tapVersion
                    : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text('客户端 · v${widget.version ?? '…'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: tokens.ink, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '在博丽大结界守护的幻想乡，24 小时免费放送全球同人佳作。'
            '从神社风铃到红魔馆夜曲，跨越现世与异界，聆听符卡与弹幕交织的旋律。',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: tokens.ink, height: 1.55),
          ),
          const SizedBox(height: 18),
          Divider(color: tokens.panelBorder, height: 1),
          const SizedBox(height: 16),
          const _ProjectCommunity(),
          const SizedBox(height: 18),
          Divider(color: tokens.panelBorder, height: 1),
          if (showSwitch) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开发者模式'),
              subtitle: Text(
                '如果您是开发者，或者需要进行功能调试，可打开此选项。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.mutedInk, height: 1.45),
              ),
              value: enabled,
              onChanged: _saving ? null : _setDeveloperMode,
            ),
            const SizedBox(height: 8),
            Divider(color: tokens.panelBorder, height: 1),
          ],
          const SizedBox(height: 14),
          Text('版权与服务',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: tokens.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '播放内容版权归原作者所有，本网站为个人兴趣搭建与非商业使用。若有侵权，请联系 yunmoan@zyghit.cn。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.mutedInk, height: 1.55),
          ),
          const SizedBox(height: 5),
          Text(
            '基础设施由 ZGIT Network Experimental IaaS 提供，CDN 服务由 TencentCloud EdgeOne 提供。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.mutedInk, height: 1.55),
          ),
        ],
      ),
    );
  }
}

// 贡献者按下列顺序显示，新增条目的步骤见 README.md。
const _contributors = ['AoralsFout', 'lbw14514', 'kimi-tsuki'];

class _ProjectCommunity extends StatelessWidget {
  const _ProjectCommunity();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('项目与社区',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: tokens.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('认识创作者，与同好一起参与 THMR。',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedInk)),
        const SizedBox(height: 16),
        _LinkGrid(children: [
          const _AboutLink(
            icon: Icon(Icons.person_outline_rounded),
            label: '作者 · @Yunmoan',
            name: '云默安',
            url: 'https://github.com/Yunmoan',
          ),
          const _AboutLink(
            icon: Icon(Icons.forum_outlined),
            label: 'THMR 官方交流群',
            name: '1094578162',
            url: 'https://qm.qq.com/q/pKXxsx4m52',
          ),
          _AboutLink(
            icon: SvgPicture.asset(
              'assets/icons/github.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(tokens.ink, BlendMode.srcIn),
            ),
            label: '项目源码',
            name: 'GitHub',
            url: 'https://github.com/Yunmoan/thmr-app',
          ),
        ]),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('贡献者',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: tokens.ink, fontWeight: FontWeight.w700)),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text('${_contributors.length} 位',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: tokens.ink)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('感谢每一份让 THMR 变得更好的贡献。',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedInk)),
        const SizedBox(height: 12),
        _LinkGrid(children: [
          for (final login in _contributors)
            _AboutLink(
              icon: const Icon(Icons.favorite_border_rounded),
              label: 'GitHub',
              name: login,
              url: 'https://github.com/$login',
            ),
        ]),
      ],
    );
  }
}

/// 窄视口或大字体会挤压链接卡片时，提前调整排列方式。
class _LinkGrid extends StatelessWidget {
  const _LinkGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final minWidth = MediaQuery.textScalerOf(context).scale(240);
      final columns = ((constraints.maxWidth + 12) / (minWidth + 12))
          .floor()
          .clamp(1, children.length);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    });
  }
}

Future<void> _openExternalUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // 有些平台可能未配置外部链接处理程序。
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.label,
    required this.name,
    required this.url,
  });

  final Widget icon;
  final String label;
  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    return Semantics(
      link: true,
      child: ThmrPanel(
        onTap: () => _openExternalUrl(url),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ExcludeSemantics(
              child: IconTheme(
                data: IconThemeData(size: 22, color: tokens.ink),
                child: icon,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: tokens.mutedInk)),
                  Text(name,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: tokens.ink, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: Icon(Icons.open_in_new_rounded,
                  size: 16, color: tokens.mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}
