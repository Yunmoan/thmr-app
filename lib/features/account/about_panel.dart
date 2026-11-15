import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/focus_outline.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';

/// The app identity, project links and attribution in one responsive panel.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key, this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tokens.panelBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text('客户端 · v${version ?? '…'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.ink, fontWeight: FontWeight.w700)),
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

// Snapshot of https://api.github.com/repos/Yunmoan/thmr-app/contributors
// verified on 2026-11-08. The author is credited separately above the list.
const _contributors = ['AoralsFout', 'lbw14514'];

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

/// Reflow before either a narrow viewport or large text crowds the link cards.
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
    // External URL handlers are optional on some platforms.
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
      child: Material(
        color: tokens.panelSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: tokens.panelBorder),
        ),
        child: FocusOutline(
            radius: 10,
            child: InkWell(
              onTap: () => _openExternalUrl(url),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
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
                                  color: tokens.ink,
                                  fontWeight: FontWeight.w700)),
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
            )),
      ),
    );
  }
}
