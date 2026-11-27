import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import 'markdown_document.dart';

/// 轻量 Markdown 文本组件，用于更新说明等受信任的短文本。
///
/// 只渲染 [parseMarkdown] 支持的语法。链接仅接受 http/https 地址，
/// 是否可点击由 [onLinkTap] 决定，组件本身不直接打开外部页面。
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.style,
    this.onLinkTap,
    this.emptyText = '暂无内容',
  });

  /// Markdown 源文本。
  final String data;

  /// 正文基准样式，标题、列表等在此基础上派生。
  final TextStyle? style;

  /// 点击安全链接时回调；为空时链接只保留样式。
  final ValueChanged<Uri>? onLinkTap;

  /// [data] 为空时显示的占位文本。
  final String emptyText;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  late List<MarkdownBlock> _blocks = parseMarkdown(widget.data);

  @override
  void didUpdateWidget(covariant MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _blocks = parseMarkdown(widget.data);
    }
  }

  TextStyle _baseStyle(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.style ??
        theme.textTheme.bodyMedium?.copyWith(height: 1.6) ??
        const TextStyle(fontSize: 14, height: 1.6);
    return base.copyWith(color: base.color ?? theme.thmr.ink);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = _baseStyle(context);
    if (_blocks.isEmpty) {
      return Text(
        widget.emptyText,
        style: base.copyWith(color: theme.thmr.mutedInk),
      );
    }
    return SelectionArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          for (var i = 0; i < _blocks.length; i++)
            Padding(
              // 标题前留出比正文更大的间隔，非首个标题才需要。
              padding: EdgeInsets.only(
                  top: i > 0 && _blocks[i] is MarkdownHeading ? 4 : 0),
              child: _buildBlock(context, _blocks[i], base),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(
      BuildContext context, MarkdownBlock block, TextStyle base) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    switch (block) {
      case MarkdownHeading():
        return Semantics(
          header: true,
          child: _MarkdownRichText(
            runs: block.runs,
            style: base.copyWith(
              fontSize: _headingSize(block.level),
              fontWeight: FontWeight.w700,
              height: 1.35,
              // 四级及以下标题作为小节标签，用弱化颜色与正文区分层级。
              color: block.level >= 4 ? tokens.mutedInk : tokens.ink,
            ),
            onLinkTap: widget.onLinkTap,
          ),
        );
      case MarkdownParagraph():
        return _MarkdownRichText(
          runs: block.runs,
          style: base,
          onLinkTap: widget.onLinkTap,
        );
      case MarkdownQuote():
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: .45),
                width: 3,
              ),
            ),
          ),
          child: _MarkdownRichText(
            runs: block.runs,
            style: base.copyWith(color: tokens.mutedInk),
            onLinkTap: widget.onLinkTap,
          ),
        );
      case MarkdownList():
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            for (final item in block.items) _buildListItem(item, base, theme),
          ],
        );
      case MarkdownCodeBlock():
        return _CodeBlock(code: block.code, base: base);
      case MarkdownRule():
        return Divider(height: 1, color: tokens.panelBorder);
    }
  }

  Widget _buildListItem(
    MarkdownListItem item,
    TextStyle base,
    ThemeData theme,
  ) {
    final marker = item.ordered ? '${item.number ?? 1}.' : '•';
    return Padding(
      padding: EdgeInsets.only(left: 18.0 * item.depth),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 列表符号与正文使用同一行高，避免首行错位。
          Padding(
            padding: EdgeInsets.only(right: item.ordered ? 8 : 7),
            child: ExcludeSemantics(
              child: Text(
                marker,
                style: base.copyWith(color: theme.thmr.mutedInk),
              ),
            ),
          ),
          Expanded(
            child: _MarkdownRichText(
              runs: item.runs,
              style: base,
              onLinkTap: widget.onLinkTap,
            ),
          ),
        ],
      ),
    );
  }
}

double _headingSize(int level) => switch (level) {
      1 => 20.0,
      2 => 17.0,
      3 => 15.0,
      4 => 14.0,
      5 => 13.0,
      _ => 12.5,
    };

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.base});

  final String code;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final style = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'],
      fontSize: (base.fontSize ?? 14.0) - 1.5,
      height: 1.5,
      color: tokens.ink,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.fieldBg,
        border: Border.all(color: tokens.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(code, style: style),
      ),
    );
  }
}

/// 把行内片段渲染为可选择的富文本，并按需为链接创建手势识别器。
class _MarkdownRichText extends StatefulWidget {
  const _MarkdownRichText({
    required this.runs,
    required this.style,
    this.onLinkTap,
  });

  final List<MarkdownRun> runs;
  final TextStyle style;
  final ValueChanged<Uri>? onLinkTap;

  @override
  State<_MarkdownRichText> createState() => _MarkdownRichTextState();
}

class _MarkdownRichTextState extends State<_MarkdownRichText> {
  final Map<int, TapGestureRecognizer> _recognizers = {};

  @override
  void didUpdateWidget(covariant _MarkdownRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 片段列表不可变，重新解析后需要按新片段重建识别器。
    if (!identical(oldWidget.runs, widget.runs)) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _recognizerFor(int index, Uri href) =>
      _recognizers.putIfAbsent(
        index,
        () =>
            TapGestureRecognizer()..onTap = () => widget.onLinkTap?.call(href),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[
      for (var i = 0; i < widget.runs.length; i++)
        _spanFor(theme, i, widget.runs[i]),
    ];
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }

  InlineSpan _spanFor(ThemeData theme, int index, MarkdownRun run) {
    final href = run.href;
    final recognizer = href != null && widget.onLinkTap != null
        ? _recognizerFor(index, href)
        : null;
    return TextSpan(
      text: run.text,
      style: _runStyle(run, widget.style, theme),
      recognizer: recognizer,
    );
  }
}

TextStyle _runStyle(MarkdownRun run, TextStyle base, ThemeData theme) {
  final tokens = theme.thmr;
  var style = base;
  if (run.code) {
    style = style.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'],
      fontSize: (style.fontSize ?? 14.0) - 1,
      backgroundColor: tokens.panelSoft,
    );
  }
  if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
  if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
  final decorations = <TextDecoration>[
    if (run.strikethrough) TextDecoration.lineThrough,
    if (run.isLink) TextDecoration.underline,
  ];
  if (decorations.isNotEmpty) {
    style = style.copyWith(
      decoration: TextDecoration.combine(decorations),
      decorationColor: run.isLink
          ? theme.colorScheme.primary.withValues(alpha: .7)
          : style.color,
    );
  }
  if (run.isLink) {
    style = style.copyWith(color: theme.colorScheme.primary);
  }
  return style;
}
