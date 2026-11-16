import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/large_screen_settings.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import 'large_screen_symbols.dart';
import 'large_screen_widgets.dart';

const _positions = ['上方靠左', '上方居中', '上方靠右', '下方靠左', '下方居中', '下方靠右'];
LargeScreenSymbol _symbol(LargeScreenWidgetKind kind) => switch (kind) {
      LargeScreenWidgetKind.clock => LargeScreenSymbol.clock,
      LargeScreenWidgetKind.date => LargeScreenSymbol.date,
      LargeScreenWidgetKind.text => LargeScreenSymbol.text,
    };

class LargeScreenWidgetEditor extends ConsumerStatefulWidget {
  const LargeScreenWidgetEditor({super.key});
  @override
  ConsumerState<LargeScreenWidgetEditor> createState() =>
      _LargeScreenWidgetEditorState();
}

class _LargeScreenWidgetEditorState
    extends ConsumerState<LargeScreenWidgetEditor> {
  String? _lastAdded;
  int _serial = 0;
  String _id() =>
      'component-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  void _save(List<LargeScreenWidgetSettings> widgets) => ref
      .read(largeScreenSettingsProvider.notifier)
      .update(ref.read(largeScreenSettingsProvider).copyWith(widgets: widgets));

  void _add(LargeScreenWidgetKind kind) {
    final items = ref.read(largeScreenSettingsProvider).widgets;
    if (items.length >= 8) return;
    final id = _id();
    setState(() => _lastAdded = id);
    _save([
      ...items,
      LargeScreenWidgetSettings(
          id: id,
          kind: kind,
          position: kind == LargeScreenWidgetKind.text
              ? LargeScreenWidgetPosition.bottomCenter
              : kind == LargeScreenWidgetKind.date
                  ? LargeScreenWidgetPosition.topLeft
                  : LargeScreenWidgetPosition.topRight,
          text: kind == LargeScreenWidgetKind.text ? '东方音乐电台' : '',
          format:
              kind == LargeScreenWidgetKind.date ? 'yyyy年M月d日 EEEE' : 'HH:mm',
          fontSize: kind == LargeScreenWidgetKind.clock ? 32 : 22)
    ]);
  }

  void _preset(String value) {
    final clock =
        LargeScreenWidgetSettings(id: _id(), fontSize: 36, format: 'HH:mm');
    final date = LargeScreenWidgetSettings(
        id: _id(),
        kind: LargeScreenWidgetKind.date,
        position: LargeScreenWidgetPosition.topLeft,
        format: 'M月d日 EEEE',
        fontSize: 20,
        tone: LargeScreenWidgetTone.muted);
    final text = LargeScreenWidgetSettings(
        id: _id(),
        kind: LargeScreenWidgetKind.text,
        position: LargeScreenWidgetPosition.bottomCenter,
        text: '东方音乐交流会',
        fontSize: 24,
        letterSpacing: 2);
    final chosen = switch (value) {
      'clock' => [clock, date],
      'event' => [clock, date, text],
      _ => [
          text.copyWith(
              text: '{title} · {artist}',
              fontSize: 20,
              tone: LargeScreenWidgetTone.muted)
        ],
    };
    final existing = ref.read(largeScreenSettingsProvider).widgets;
    if (existing.length + chosen.length > 8) return;
    setState(() => _lastAdded = chosen.first.id);
    _save([...existing, ...chosen]);
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(largeScreenSettingsProvider.select((s) => s.widgets));
    final needsMetadata = items
        .any((w) => RegExp(r'\{(title|artist|channel)\}').hasMatch(w.text));
    final station =
        needsMetadata ? ref.watch(stationProvider) : const StationUiState();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text('小组件', style: Theme.of(context).textTheme.titleSmall),
            PopupMenuButton<LargeScreenWidgetKind>(
              tooltip: '添加小组件',
              enabled: items.length < 8,
              popUpAnimationStyle: ThmrMotion.style(context),
              onSelected: _add,
              itemBuilder: (_) => [
                for (final kind in LargeScreenWidgetKind.values)
                  PopupMenuItem(
                      value: kind,
                      child: Row(children: [
                        LargeScreenGlyph(_symbol(kind), size: 18),
                        const SizedBox(width: 10),
                        Text(switch (kind) {
                          LargeScreenWidgetKind.clock => '时间',
                          LargeScreenWidgetKind.date => '日期',
                          LargeScreenWidgetKind.text => '文本'
                        }),
                      ]))
              ],
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add,
                        size: 18,
                        color: items.length < 8
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor),
                    const SizedBox(width: 6),
                    const Text('添加小组件'),
                  ])),
            ),
          ]),
      Wrap(spacing: 8, children: [
        TextButton(
            onPressed: items.length > 6 ? null : () => _preset('clock'),
            child: const Text('添加时钟日期')),
        TextButton(
            onPressed: items.length > 5 ? null : () => _preset('event'),
            child: const Text('添加活动组件')),
        TextButton(
            onPressed: items.length >= 8 ? null : () => _preset('track'),
            child: const Text('添加曲目字幕')),
      ]),
      if (items.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('添加时间、日期或文本，按位置自动排版。',
                style: Theme.of(context).textTheme.bodySmall)),
      for (var i = 0; i < items.length; i++)
        _ComponentEditor(
            key: ValueKey(items[i].id),
            component: items[i],
            initiallyExpanded: items[i].id == _lastAdded,
            preview: LargeScreenWidgetStrip(components: [
              items[i].copyWith(
                  enabled: true, position: LargeScreenWidgetPosition.topCenter)
            ], station: station, atTop: true),
            onChanged: (value) => _save([...items]..[i] = value),
            onDelete: () => _save([...items]..removeAt(i)),
            onDuplicate: items.length >= 8
                ? null
                : () {
                    final copy = items[i].copyWith(id: _id());
                    setState(() => _lastAdded = copy.id);
                    _save([...items]..insert(i + 1, copy));
                  },
            onMoveUp: i == 0
                ? null
                : () {
                    final next = [...items];
                    final item = next.removeAt(i);
                    next.insert(i - 1, item);
                    _save(next);
                  },
            onMoveDown: i == items.length - 1
                ? null
                : () {
                    final next = [...items];
                    final item = next.removeAt(i);
                    next.insert(i + 1, item);
                    _save(next);
                  }),
    ]);
  }
}

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor(
      {super.key,
      required this.component,
      required this.preview,
      required this.initiallyExpanded,
      required this.onChanged,
      required this.onDelete,
      required this.onDuplicate,
      required this.onMoveUp,
      required this.onMoveDown});
  final LargeScreenWidgetSettings component;
  final Widget preview;
  final bool initiallyExpanded;
  final ValueChanged<LargeScreenWidgetSettings> onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate, onMoveUp, onMoveDown;
  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> {
  late final _text = TextEditingController(text: widget.component.text);
  late final _format = TextEditingController(text: widget.component.format);
  late final _color = TextEditingController(text: _hex(widget.component.color));
  String _hex(int color) =>
      (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  @override
  void didUpdateWidget(covariant _ComponentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.component.text != widget.component.text &&
        _text.text != widget.component.text) {
      _text.text = widget.component.text;
    }
    if (oldWidget.component.format != widget.component.format &&
        _format.text != widget.component.format) {
      _format.text = widget.component.format;
    }
    if (oldWidget.component.color != widget.component.color &&
        _color.text.toUpperCase().replaceAll('#', '') !=
            _hex(widget.component.color)) {
      _color.text = _hex(widget.component.color);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _format.dispose();
    _color.dispose();
    super.dispose();
  }

  void _insert(String tag) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    final result = _text.text.replaceRange(start, end, tag);
    if (result.length > 500) return;
    _text.value = TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: start + tag.length));
    widget.onChanged(widget.component.copyWith(text: result));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.component;
    final theme = Theme.of(context);
    Widget choices<T>(String label, T selected, List<(T, String)> options,
            ValueChanged<T> changed) =>
        _Field(
            label: label,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final option in options)
                ChoiceChip(
                    label: Text(option.$2),
                    selected: selected == option.$1,
                    onSelected: (_) => changed(option.$1)),
            ]));
    return DecoratedBox(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.thmr.panelBorder))),
        child: ExpansionTile(
          key: PageStorageKey(item.id),
          initiallyExpanded: widget.initiallyExpanded,
          expansionAnimationStyle: ThmrMotion.style(context),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: LargeScreenGlyph(_symbol(item.kind)),
          title: Text(item.label),
          subtitle: Text(_positions[item.position.index],
              style: theme.textTheme.labelSmall),
          children: [
            SizedBox(height: 96, child: Center(child: widget.preview)),
            Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                        value: item.enabled,
                        onChanged: (v) =>
                            widget.onChanged(item.copyWith(enabled: v))),
                    const Text('显示')
                  ]),
                  IconButton(
                      tooltip: '上移小组件',
                      onPressed: widget.onMoveUp,
                      icon: const Icon(Icons.arrow_upward, size: 18)),
                  IconButton(
                      tooltip: '下移小组件',
                      onPressed: widget.onMoveDown,
                      icon: const Icon(Icons.arrow_downward, size: 18)),
                  IconButton(
                      tooltip: '复制小组件',
                      onPressed: widget.onDuplicate,
                      icon: const Icon(Icons.copy, size: 18)),
                  IconButton(
                      tooltip: '删除小组件',
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18)),
                ]),
            choices(
                '位置',
                item.position,
                [
                  for (final pos in LargeScreenWidgetPosition.values)
                    (pos, _positions[pos.index])
                ],
                (v) => widget.onChanged(item.copyWith(position: v))),
            if (item.kind == LargeScreenWidgetKind.text) ...[
              _Field(
                  label: '文本内容',
                  child: TextField(
                      controller: _text,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(hintText: '输入要显示的文字'),
                      onChanged: (v) =>
                          widget.onChanged(item.copyWith(text: v)))),
              Wrap(spacing: 6, children: [
                for (final tag in const [
                  ('曲名', '{title}'),
                  ('社团', '{artist}'),
                  ('频道', '{channel}'),
                  ('时间', '{time}'),
                  ('日期', '{date}'),
                  ('星期', '{weekday}'),
                ])
                  ActionChip(
                      label: Text('插入${tag.$1}'),
                      onPressed: () => _insert(tag.$2))
              ]),
            ],
            if (item.kind != LargeScreenWidgetKind.text ||
                item.text.contains('{time}')) ...[
              choices(
                  '常用格式',
                  item.format,
                  item.kind == LargeScreenWidgetKind.date
                      ? const [
                          ('yyyy年M月d日 EEEE', '年月日与星期'),
                          ('yyyy-MM-dd', '2026-11-16'),
                          ('M月d日 EEEE', '月日与星期'),
                          ('EEEE', '星期')
                        ]
                      : const [
                          ('HH:mm', '24 小时'),
                          ('HH:mm:ss', '显示秒'),
                          ('h:mm a', '12 小时'),
                          ('HH时mm分', '中文时间')
                        ],
                  (v) => widget.onChanged(item.copyWith(format: v))),
              _Field(
                  label: '自定义格式',
                  child: TextField(
                      controller: _format,
                      maxLength: 100,
                      decoration: InputDecoration(
                          helperText: item.kind == LargeScreenWidgetKind.date
                              ? 'yyyy 年 · MM 月 · dd 日 · EEEE 星期'
                              : 'HH 24小时 · h 12小时 · mm 分 · ss 秒 · a 上下午'),
                      onChanged: (v) =>
                          widget.onChanged(item.copyWith(format: v)))),
            ],
            if (item.needsClock)
              choices(
                  '时区',
                  item.timezone,
                  const [
                    (LargeScreenWidgetTimezone.local, '系统时间'),
                    (LargeScreenWidgetTimezone.beijing, '北京时间'),
                    (LargeScreenWidgetTimezone.utc, 'UTC')
                  ],
                  (v) => widget.onChanged(item.copyWith(timezone: v))),
            _Field(
                label: '字号 ${item.fontSize.round()}',
                child: Slider(
                    value: item.fontSize,
                    min: 12,
                    max: 96,
                    divisions: 42,
                    label: '${item.fontSize.round()}',
                    onChanged: (v) =>
                        widget.onChanged(item.copyWith(fontSize: v)))),
            choices(
                '字体',
                item.font,
                const [
                  (LargeScreenWidgetFont.inherit, '跟随应用'),
                  (LargeScreenWidgetFont.sans, '无衬线'),
                  (LargeScreenWidgetFont.mono, '等宽')
                ],
                (v) => widget.onChanged(item.copyWith(font: v))),
            choices(
                '字重',
                item.weight,
                const [(400, '常规'), (600, '中等'), (800, '粗体')],
                (v) => widget.onChanged(item.copyWith(weight: v))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('斜体'),
                value: item.italic,
                onChanged: (v) => widget.onChanged(item.copyWith(italic: v))),
            choices(
                '颜色',
                item.tone,
                const [
                  (LargeScreenWidgetTone.ink, '正文色'),
                  (LargeScreenWidgetTone.muted, '次要色'),
                  (LargeScreenWidgetTone.accent, '主题色'),
                  (LargeScreenWidgetTone.custom, '自定义')
                ],
                (v) => widget.onChanged(item.copyWith(tone: v))),
            if (item.tone == LargeScreenWidgetTone.custom)
              _Field(
                  label: '自定义颜色',
                  child: TextField(
                      controller: _color,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp('[0-9a-fA-F#]')),
                        LengthLimitingTextInputFormatter(7)
                      ],
                      decoration: const InputDecoration(
                          prefixText: '#', hintText: 'RRGGBB'),
                      onChanged: (v) {
                        final hex = v.replaceAll('#', '');
                        if (hex.length == 6) {
                          final parsed = int.tryParse(hex, radix: 16);
                          if (parsed != null) {
                            widget.onChanged(
                                item.copyWith(color: parsed | 0xFF000000));
                          }
                        }
                      })),
            choices(
                '样式',
                item.decoration,
                const [
                  (LargeScreenWidgetDecoration.none, '纯文字'),
                  (LargeScreenWidgetDecoration.rule, '竖线'),
                  (LargeScreenWidgetDecoration.label, '标签')
                ],
                (v) => widget.onChanged(item.copyWith(decoration: v))),
            _Field(
                label: '字距 ${item.letterSpacing.round()}',
                child: Slider(
                    value: item.letterSpacing,
                    min: 0,
                    max: 12,
                    divisions: 12,
                    onChanged: (v) =>
                        widget.onChanged(item.copyWith(letterSpacing: v)))),
            _Field(
                label: '不透明度 ${(item.opacity * 100).round()}%',
                child: Slider(
                    value: item.opacity,
                    min: .3,
                    max: 1,
                    divisions: 14,
                    onChanged: (v) =>
                        widget.onChanged(item.copyWith(opacity: v)))),
            choices(
                '最多行数',
                item.maxLines,
                const [(1, '1 行'), (2, '2 行'), (3, '3 行'), (4, '4 行')],
                (v) => widget.onChanged(item.copyWith(maxLines: v))),
          ],
        ));
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ]));
}
