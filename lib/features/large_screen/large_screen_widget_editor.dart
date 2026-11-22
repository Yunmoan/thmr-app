import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/large_screen_settings.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_menu.dart';
import '../../shared/widgets/thmr_slider.dart';
import 'large_screen_symbols.dart';
import 'large_screen_widgets.dart';

const _positions = ['上方靠左', '上方居中', '上方靠右', '下方靠左', '下方居中', '下方靠右'];
LargeScreenSymbol _symbol(LargeScreenWidgetKind kind) => switch (kind) {
      LargeScreenWidgetKind.clock => LargeScreenSymbol.clock,
      LargeScreenWidgetKind.date => LargeScreenSymbol.date,
      LargeScreenWidgetKind.text => LargeScreenSymbol.text,
    };

String _componentLabel(LargeScreenWidgetSettings item) =>
    item.kind == LargeScreenWidgetKind.text && item.text.trim().isNotEmpty
        ? item.text.replaceAll('\n', ' ')
        : item.label;

class LargeScreenWidgetEditor extends ConsumerStatefulWidget {
  const LargeScreenWidgetEditor({super.key});
  @override
  ConsumerState<LargeScreenWidgetEditor> createState() =>
      _LargeScreenWidgetEditorState();
}

class _LargeScreenWidgetEditorState
    extends ConsumerState<LargeScreenWidgetEditor> {
  late final _settings = ref.read(largeScreenSettingsProvider.notifier);
  String? _selectedId;
  int _serial = 0;
  Timer? _saveTimer;
  String _id() =>
      'component-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

  void _commit() {
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_settings.persist());
  }

  void _save(List<LargeScreenWidgetSettings> widgets, {bool deferred = false}) {
    _settings.preview(
        ref.read(largeScreenSettingsProvider).copyWith(widgets: widgets));
    _saveTimer?.cancel();
    if (deferred) {
      _saveTimer = Timer(const Duration(milliseconds: 400), _commit);
    } else {
      _commit();
    }
  }

  void _edit(LargeScreenWidgetSettings component, {bool deferred = false}) {
    final items = [...ref.read(largeScreenSettingsProvider).widgets];
    final index = items.indexWhere((w) => w.id == component.id);
    if (index < 0) return;
    items[index] = component;
    _save(items, deferred: deferred);
  }

  void _select(String id) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_saveTimer != null) _commit();
    setState(() => _selectedId = id);
  }

  void _add(LargeScreenWidgetKind kind) {
    final items = ref.read(largeScreenSettingsProvider).widgets;
    if (items.length >= 8) return;
    final id = _id();
    _select(id);
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
    _select(chosen.first.id);
    _save([...existing, ...chosen]);
  }

  void _move(String id, int delta) {
    final next = [...ref.read(largeScreenSettingsProvider).widgets];
    final index = next.indexWhere((w) => w.id == id);
    if (index < 0 || index + delta < 0 || index + delta >= next.length) return;
    next.insert(index + delta, next.removeAt(index));
    _save(next);
  }

  void _delete(String id) {
    final items = [...ref.read(largeScreenSettingsProvider).widgets];
    final index = items.indexWhere((w) => w.id == id);
    if (index < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    items.removeAt(index);
    setState(() => _selectedId =
        items.isEmpty ? null : items[index.clamp(0, items.length - 1)].id);
    _save(items);
  }

  @override
  void dispose() {
    if (_saveTimer != null) _commit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(largeScreenSettingsProvider.select((s) => s.widgets));
    final selected = items.where((w) => w.id == _selectedId).firstOrNull ??
        items.firstOrNull;
    final index = selected == null ? -1 : items.indexOf(selected);
    final needsMetadata = selected != null &&
        RegExp(r'\{(title|artist|channel)\}').hasMatch(selected.text);
    final station =
        needsMetadata ? ref.watch(stationProvider) : const StationUiState();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text('小组件 ${items.length}/8', style: theme.textTheme.titleSmall),
            ThmrMenuButton<LargeScreenWidgetKind>(
              tooltip: '添加小组件',
              enabled: items.length < 8,
              onSelected: _add,
              itemBuilder: (_) => [
                for (final kind in LargeScreenWidgetKind.values)
                  PopupMenuItem(
                      value: kind,
                      child: Row(children: [
                        LargeScreenGlyph(_symbol(kind), size: 18),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(switch (kind) {
                            LargeScreenWidgetKind.clock => '时间',
                            LargeScreenWidgetKind.date => '日期',
                            LargeScreenWidgetKind.text => '文本'
                          }),
                        ),
                      ]))
              ],
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add,
                        size: 18,
                        color: items.length < 8
                            ? theme.colorScheme.primary
                            : theme.disabledColor),
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
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Text('添加时间、日期或文本，按位置自动排版。', style: theme.textTheme.bodySmall)),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < items.length; i++)
            InputChip(
                key: ValueKey('select-${items[i].id}'),
                avatar: LargeScreenGlyph(_symbol(items[i].kind),
                    size: 16,
                    color: items[i].enabled
                        ? theme.thmr.ink
                        : theme.thmr.mutedInk),
                label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text('${i + 1} · ${_componentLabel(items[i])}',
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                tooltip:
                    '${items[i].label} · ${_positions[items[i].position.index]}',
                selected: items[i].id == selected?.id,
                onSelected: (_) => _select(items[i].id)),
        ]),
        const Divider(height: 28),
      ],
      if (selected != null)
        _ComponentEditor(
            key: ValueKey(selected.id),
            component: selected,
            preview: LargeScreenWidgetStrip(components: [
              selected.copyWith(
                  enabled: true, position: LargeScreenWidgetPosition.topCenter)
            ], station: station, atTop: true, singleColumn: true),
            onChanged: (value) => _edit(value),
            onDraft: (value) => _edit(value, deferred: true),
            onCommit: _commit,
            onDelete: () => _delete(selected.id),
            onDuplicate: items.length >= 8
                ? null
                : () {
                    final current =
                        ref.read(largeScreenSettingsProvider).widgets;
                    final latest =
                        current.firstWhere((w) => w.id == selected.id);
                    final copy = latest.copyWith(id: _id());
                    _select(copy.id);
                    _save([...current]..insert(index + 1, copy));
                  },
            onMoveUp: index == 0 ? null : () => _move(selected.id, -1),
            onMoveDown:
                index == items.length - 1 ? null : () => _move(selected.id, 1)),
    ]);
  }
}

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor({
    super.key,
    required this.component,
    required this.preview,
    required this.onChanged,
    required this.onDraft,
    required this.onCommit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
  });
  final LargeScreenWidgetSettings component;
  final Widget preview;
  final ValueChanged<LargeScreenWidgetSettings> onChanged, onDraft;
  final VoidCallback onCommit, onDelete;
  final VoidCallback? onDuplicate, onMoveUp, onMoveDown;
  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> {
  late final _text = TextEditingController(text: widget.component.text);
  late final _format = TextEditingController(text: widget.component.format);
  late final _color = TextEditingController(text: _hex(widget.component.color));
  // ExpansionTile stores a bool under its PageStorageKey. A nested input's
  // internal Scrollable must not read that value as its double scroll offset.
  final _textScroll = ScrollController(keepScrollOffset: false);
  final _formatScroll = ScrollController(keepScrollOffset: false);
  final _colorScroll = ScrollController(keepScrollOffset: false);
  String _hex(int color) =>
      (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void didUpdateWidget(covariant _ComponentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.component.text == widget.component.text &&
        oldWidget.component.format == widget.component.format &&
        oldWidget.component.color == widget.component.color) {
      return;
    }
    // EditableText owns selection and composing state. Synchronize external
    // presets after this build, never while its elements are being updated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void sync(TextEditingController controller, String value) {
        if (controller.text == value) return;
        final selection = controller.selection;
        controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(
                offset: selection.isValid
                    ? selection.extentOffset.clamp(0, value.length)
                    : value.length));
      }

      sync(_text, widget.component.text);
      sync(_format, widget.component.format);
      if (_color.text.toUpperCase().replaceAll('#', '') !=
          _hex(widget.component.color)) {
        sync(_color, _hex(widget.component.color));
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _format.dispose();
    _color.dispose();
    _textScroll.dispose();
    _formatScroll.dispose();
    _colorScroll.dispose();
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
    final hasFormat =
        item.kind != LargeScreenWidgetKind.text || item.text.contains('{time}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                  value: item.enabled,
                  onChanged: (v) =>
                      widget.onChanged(item.copyWith(enabled: v))),
              const Text('显示'),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
      SizedBox(height: 56, child: Center(child: widget.preview)),
      if (item.kind == LargeScreenWidgetKind.text) ...[
        _Field(
            label: '文本内容',
            child: TextField(
                key: ValueKey('component-text-${item.id}'),
                controller: _text,
                scrollController: _textScroll,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(hintText: '输入要显示的文字'),
                onChanged: (v) => widget.onDraft(item.copyWith(text: v)))),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final tag in const [
            ('曲名', '{title}'),
            ('社团', '{artist}'),
            ('频道', '{channel}'),
            ('时间', '{time}'),
            ('日期', '{date}'),
            ('星期', '{weekday}'),
          ])
            ActionChip(
                label: Text('插入${tag.$1}'), onPressed: () => _insert(tag.$2)),
        ]),
      ],
      if (hasFormat)
        choices(
            '常用格式',
            item.format,
            item.kind == LargeScreenWidgetKind.date
                ? const [
                    ('yyyy年M月d日 EEEE', '年月日与星期'),
                    ('yyyy-MM-dd', '年月日'),
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
      choices(
          '位置',
          item.position,
          [
            for (final pos in LargeScreenWidgetPosition.values)
              (pos, _positions[pos.index])
          ],
          (v) => widget.onChanged(item.copyWith(position: v))),
      _Field(
          label: '字号 ${item.fontSize.round()}',
          child: ThmrSlider(
              value: item.fontSize,
              min: 12,
              max: 96,
              divisions: 42,
              semanticsLabel: '字号',
              formatValue: (v) => '${v.round()}',
              onChanged: (v) => widget.onDraft(item.copyWith(fontSize: v)),
              onChangeEnd: (_) => widget.onCommit())),
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
                key: ValueKey('component-color-${item.id}'),
                controller: _color,
                scrollController: _colorScroll,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                  LengthLimitingTextInputFormatter(7)
                ],
                decoration:
                    const InputDecoration(prefixText: '#', hintText: 'RRGGBB'),
                onChanged: (v) {
                  final hex = v.replaceAll('#', '');
                  if (hex.length != 6) return;
                  final parsed = int.tryParse(hex, radix: 16);
                  if (parsed != null) {
                    widget.onDraft(item.copyWith(color: 0xFF000000 | parsed));
                  }
                })),
      const SizedBox(height: 16),
      ExpansionTile(
          key: PageStorageKey('component-advanced-${item.id}'),
          title: const Text('高级样式'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          expansionAnimationStyle: ThmrMotion.style(context),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            if (hasFormat)
              _Field(
                  label: '自定义格式',
                  child: TextField(
                      key: ValueKey('component-format-${item.id}'),
                      controller: _format,
                      scrollController: _formatScroll,
                      maxLength: 100,
                      decoration: InputDecoration(
                          helperText: item.kind == LargeScreenWidgetKind.date
                              ? 'yyyy 年 · MM 月 · dd 日 · EEEE 星期'
                              : 'HH 24小时 · h 12小时 · mm 分 · ss 秒 · a 上下午'),
                      onChanged: (v) =>
                          widget.onDraft(item.copyWith(format: v)))),
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
                '装饰',
                item.decoration,
                const [
                  (LargeScreenWidgetDecoration.none, '无'),
                  (LargeScreenWidgetDecoration.rule, '竖线'),
                  (LargeScreenWidgetDecoration.label, '底色')
                ],
                (v) => widget.onChanged(item.copyWith(decoration: v))),
            _Field(
                label: '字距 ${item.letterSpacing.round()}',
                child: ThmrSlider(
                    value: item.letterSpacing,
                    min: 0,
                    max: 12,
                    divisions: 12,
                    semanticsLabel: '字距',
                    formatValue: (v) => '${v.round()}',
                    onChanged: (v) =>
                        widget.onDraft(item.copyWith(letterSpacing: v)),
                    onChangeEnd: (_) => widget.onCommit())),
            _Field(
                label: '不透明度 ${(item.opacity * 100).round()}%',
                child: ThmrSlider(
                    value: item.opacity,
                    min: .3,
                    max: 1,
                    divisions: 14,
                    semanticsLabel: '不透明度',
                    formatValue: (v) => '${(v * 100).round()}%',
                    onChanged: (v) => widget.onDraft(item.copyWith(opacity: v)),
                    onChangeEnd: (_) => widget.onCommit())),
            choices(
                '最多行数',
                item.maxLines,
                const [(1, '1 行'), (2, '2 行'), (3, '3 行'), (4, '4 行')],
                (v) => widget.onChanged(item.copyWith(maxLines: v))),
          ]),
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        child,
      ]));
}
