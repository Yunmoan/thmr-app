import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
              child: Text('客户端 · Alpha v${version ?? '…'}',
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
          Text('项目与社区',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: tokens.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 660 ? 3 : 1;
            final cardWidth =
                (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: const _AboutLink(
                    icon: Icons.person_outline_rounded,
                    label: '作者',
                    name: '云默安',
                    url: 'https://github.com/Yunmoan',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const _AboutLink(
                    icon: Icons.favorite_border_rounded,
                    label: '特别鸣谢',
                    name: 'AoralsFout',
                    url: 'https://github.com/AoralsFout',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const _AboutLink(
                    icon: Icons.forum_outlined,
                    label: 'THMR 官方交流群',
                    name: '1094578162',
                    url: 'https://qm.qq.com/q/pKXxsx4m52',
                  ),
                ),
              ],
            );
          }),
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

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.label,
    required this.name,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String name;
  final String url;

  Future<void> _open() async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // External URL handlers are optional on some platforms.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    return Semantics(
      link: true,
      child: Material(
        color: tokens.panelSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: tokens.panelBorder),
        ),
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 19, color: tokens.ink),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: tokens.mutedInk)),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.ink, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new_rounded,
                    size: 15, color: tokens.mutedInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
