import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/large_screen_settings.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/focus_outline.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/thmr_slider.dart';
import 'large_screen_symbols.dart';
import 'large_screen_widget_editor.dart';
import 'large_screen_preview.dart';

class LargeScreenSettingsEntry extends StatelessWidget {
  const LargeScreenSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) => ThmrPanel(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const LargeScreenSettingsPage(),
        )),
        child: Row(children: [
          LargeScreenGlyph(LargeScreenSymbol.enter,
              color: Theme.of(context).thmr.mutedInk),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('大屏幕模式Beta 配置',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('布局、小组件与画面预览',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).thmr.mutedInk)),
              ])),
          Icon(Icons.chevron_right_rounded,
              color: Theme.of(context).thmr.mutedInk),
        ]),
      );
}

class LargeScreenSettingsPage extends StatefulWidget {
  const LargeScreenSettingsPage({super.key});
  @override
  State<LargeScreenSettingsPage> createState() =>
      _LargeScreenSettingsPageState();
}

class _LargeScreenSettingsPageState extends State<LargeScreenSettingsPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('大屏幕模式Beta 配置'), actions: [
        TextButton.icon(
            onPressed: () => LargeScreenPreview.open(context),
            icon: const Icon(Icons.preview_outlined, size: 18),
            label: const Text('预览')),
        const SizedBox(width: 12),
      ]),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: wide ? 5 : 1,
                  child: Column(children: [
                    TabBar(
                        controller: _tabs,
                        onTap: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        tabs: const [Tab(text: '布局与显示'), Tab(text: '小组件')]),
                    const SizedBox(height: 12),
                    Expanded(
                        child: AnimatedBuilder(
                            animation: _tabs,
                            builder: (_, __) =>
                                IndexedStack(index: _tabs.index, children: [
                                  for (var i = 0; i < 2; i++)
                                    TickerMode(
                                        enabled: _tabs.index == i,
                                        child: ExcludeFocus(
                                            excluding: _tabs.index != i,
                                            child: SingleChildScrollView(
                                                key: PageStorageKey(
                                                    'large-settings-tab-$i'),
                                                padding: const EdgeInsets.only(
                                                    bottom: 16),
                                                child: i == 0
                                                    ? const LargeScreenSettingsPanel(
                                                        includeWidgets: false)
                                                    : const ThmrPanel(
                                                        child:
                                                            LargeScreenWidgetEditor())))),
                                ]))),
                  ])),
              if (wide) ...[
                const SizedBox(width: 24),
                const Expanded(
                    flex: 6,
                    child: Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LargeScreenPreview())),
              ],
            ]));
      }));
}

class LargeScreenSettingsPanel extends ConsumerWidget {
  const LargeScreenSettingsPanel({super.key, this.includeWidgets = true});
  final bool includeWidgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(largeScreenSettingsProvider);
    void save(LargeScreenSettings next) =>
        ref.read(largeScreenSettingsProvider.notifier).update(next);
    return ThmrPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('布局', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 560 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final option in const [
              (LargeScreenLayout.adaptive, LargeScreenSymbol.adaptive, '自动'),
              (LargeScreenLayout.coverLeft, LargeScreenSymbol.left, '封面在左'),
              (LargeScreenLayout.coverRight, LargeScreenSymbol.right, '封面在右'),
              (LargeScreenLayout.centered, LargeScreenSymbol.centered, '上下居中'),
            ])
              SizedBox(
                width: width,
                child: _DiagramChoice(
                  label: option.$3,
                  symbol: option.$2,
                  selected: settings.layout == option.$1,
                  onTap: () => save(settings.copyWith(layout: option.$1)),
                ),
              ),
          ]);
        }),
        _SettingRow(
          title: '画面范围',
          description: '铺满可用空间，或限制内容尺寸并居中',
          child: _Choices<LargeScreenFraming>(
              value: settings.framing,
              options: const [
                (LargeScreenFraming.fill, '铺满窗口'),
                (LargeScreenFraming.fit, '居中适应')
              ],
              onChanged: (v) => save(settings.copyWith(framing: v))),
        ),
        _SettingRow(
          title: '封面显示',
          description: '完整保留图片，或裁切铺满封面区域',
          child: _Choices<LargeScreenCoverFit>(
              value: settings.coverFit,
              options: const [
                (LargeScreenCoverFit.contain, '完整显示'),
                (LargeScreenCoverFit.cover, '裁切铺满')
              ],
              onChanged: (v) => save(settings.copyWith(coverFit: v))),
        ),
        _SettingRow(
          title: '播放队列',
          child: _Choices<LargeScreenQueue>(
              value: settings.queue,
              options: const [
                (LargeScreenQueue.hidden, '隐藏'),
                (LargeScreenQueue.next, '下一首'),
                (LargeScreenQueue.strip, '横向排列'),
                (LargeScreenQueue.list, '列表')
              ],
              onChanged: (v) => save(settings.copyWith(queue: v))),
        ),
        if (settings.queue == LargeScreenQueue.strip)
          _SettingRow(
            title: '横向队列曲目数',
            child: _Choices<int>(
                value: settings.queueCount,
                options: const [(3, '3 首'), (5, '5 首'), (8, '8 首')],
                onChanged: (v) => save(settings.copyWith(queueCount: v))),
          ),
        if (settings.queue != LargeScreenQueue.hidden)
          _SettingSwitch(
              title: '队列封面',
              value: settings.showQueueCovers,
              onChanged: (v) => save(settings.copyWith(showQueueCovers: v))),
        _SettingRow(
          title: '曲目信息字号',
          child: _Choices<double>(
              value: settings.textScale,
              options: const [
                (0.9, '较小'),
                (1.0, '标准'),
                (1.15, '较大'),
                (1.3, '大号')
              ],
              onChanged: (v) => save(settings.copyWith(textScale: v))),
        ),
        _SettingRow(
          title: '大屏主题',
          child: _Choices<ThemeMode>(
              value: settings.themeMode,
              options: const [
                (ThemeMode.system, '跟随应用'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色')
              ],
              onChanged: (v) => save(settings.copyWith(themeMode: v))),
        ),
        _SettingSwitch(
            title: '卡片式布局',
            value: settings.cardLayout,
            description: '为播放区与队列显示纸面板背景',
            onChanged: (v) => save(settings.copyWith(cardLayout: v))),
        _SettingSwitch(
            title: '背景立绘',
            value: settings.showIllustration,
            description: '使用当前角色主题的背景',
            onChanged: (v) => save(settings.copyWith(showIllustration: v))),
        if (settings.showIllustration)
          _SettingRow(
              title: '立绘位置',
              child: _Choices<LargeScreenIllustrationPosition>(
                  value: settings.illustrationPosition,
                  options: const [
                    (LargeScreenIllustrationPosition.left, '左下角'),
                    (LargeScreenIllustrationPosition.right, '右下角')
                  ],
                  onChanged: (v) =>
                      save(settings.copyWith(illustrationPosition: v)))),
        _SettingSwitch(
            title: '直播进度',
            value: settings.showProgress,
            onChanged: (v) => save(settings.copyWith(showProgress: v))),
        _SettingSwitch(
            title: '播放控制栏',
            value: settings.showControls,
            onChanged: (v) => save(settings.copyWith(showControls: v))),
        _SettingSwitch(
            title: '自动收起控制栏',
            value: settings.autoHideControls,
            description: '闲置 4 秒后隐藏，移动鼠标或操作按键时恢复',
            onChanged: (v) => save(settings.copyWith(autoHideControls: v))),
        _SettingSwitch(
            title: '打开时进入全屏',
            value: settings.startFullScreen,
            description: '也可在大屏右上角单独切换全屏',
            onChanged: (v) => save(settings.copyWith(startFullScreen: v))),
        if (settings.showIllustration)
          _SettingRow(
              title: '立绘不透明度',
              child: SizedBox(
                  width: 300,
                  child: ThmrSlider(
                      value: settings.illustrationOpacity,
                      min: .1,
                      max: 1,
                      divisions: 9,
                      semanticsLabel: '立绘不透明度',
                      formatValue: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          save(settings.copyWith(illustrationOpacity: v))))),
        _SettingRow(
            title: '画面边距',
            child: _Choices<double>(
                value: settings.contentMargin,
                options: const [(16, '紧凑'), (32, '标准'), (48, '宽松'), (64, '留白')],
                onChanged: (v) => save(settings.copyWith(contentMargin: v)))),
        if (includeWidgets) ...[
          const Divider(height: 32),
          const LargeScreenWidgetEditor(),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => save(includeWidgets
                ? const LargeScreenSettings()
                : LargeScreenSettings(widgets: settings.widgets)),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(includeWidgets ? '恢复默认' : '恢复默认布局'),
          ),
        ),
      ]),
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices(
      {required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final option in options)
          FocusOutline(
            radius: 999,
            focusBounds: true,
            child: ChoiceChip(
              selected: value == option.$1,
              label: Text(option.$2),
              onSelected: (_) => onChanged(option.$1),
            ),
          ),
      ]);
}

class _DiagramChoice extends StatelessWidget {
  const _DiagramChoice(
      {required this.label,
      required this.symbol,
      required this.selected,
      required this.onTap});
  final String label;
  final LargeScreenSymbol symbol;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final color =
        selected ? Theme.of(context).colorScheme.primary : tokens.mutedInk;
    return FocusOutline(
        child: Material(
      color: selected ? tokens.accentSoft : tokens.fieldBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? color : tokens.panelBorder)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: ExcludeSemantics(
              child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LargeScreenGlyph(symbol, size: 36, color: color),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: color)),
            ]),
          )),
        ),
      ),
    ));
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(
      {required this.title, required this.child, this.description});
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      if (description != null)
        Text(description!,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.thmr.mutedInk)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 28),
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 650 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 8),
                child,
              ]);
        }
        return Row(children: [
          Expanded(child: label),
          const SizedBox(width: 20),
          Flexible(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: child))
        ]);
      }),
    ]);
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch(
      {required this.title,
      required this.value,
      required this.onChanged,
      this.description});
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (description != null)
                  Text(description!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Theme.of(context).thmr.mutedInk)),
              ])),
          const SizedBox(width: 12),
          FocusOutline(
              child: Semantics(
                  label: title,
                  child: Switch(value: value, onChanged: onChanged))),
        ]),
      );
}
