/// 轻量 Markdown 解析器。
///
/// 更新说明来自签名清单，排版只需要覆盖标题、列表、引用、代码、强调和链接等
/// 常用语法。这里实现一个无第三方依赖的子集解析器，避免完整的 CommonMark 实现
/// 带来的体积和不可控的排版差异。
///
/// 支持的块级语法：
/// - ATX 标题（`#` 到 `######`）与分隔线；
/// - 无序列表（`-`、`*`、`+`）、有序列表（`1.`、`1)`）及缩进嵌套；
/// - 围栏代码块（``` 或 ~~~）与引用（`>`）；
/// - 其余连续行组成段落，保留原有换行。
///
/// 支持的行内语法：`**粗体**`、`*斜体*`、`~~删除线~~`、`` `代码` ``、
/// `[文本](https://…)`、`<https://…>` 和反斜杠转义。
library;

/// 解析块级节点。空内容返回空列表。
List<MarkdownBlock> parseMarkdown(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) return const [];
  final lines = normalized.split('\n');
  final blocks = <MarkdownBlock>[];
  var index = 0;

  while (index < lines.length) {
    if (blocks.length >= _maxBlocks) break;
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    final fence = _fencePattern.firstMatch(line);
    if (fence != null && !_isInvalidFence(fence)) {
      final marker = fence.group(1)!;
      final language = fence.group(2)!.trim();
      final closing = RegExp('^ {0,3}${RegExp.escape(marker[0])}'
          '{${marker.length},}[ \t]*\$');
      final code = <String>[];
      index++;
      while (index < lines.length) {
        if (closing.hasMatch(lines[index])) {
          index++;
          break;
        }
        code.add(lines[index]);
        index++;
      }
      blocks.add(MarkdownCodeBlock(code.join('\n').trimRight(),
          language:
              language.isEmpty ? null : language.split(RegExp(r'\s+')).first));
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      // 标题后的闭合 # 需要与前文用空格分隔，按 CommonMark 的写法去掉。
      final content = (heading.group(2) ?? '')
          .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '')
          .trim();
      index++;
      if (content.isNotEmpty) {
        blocks.add(MarkdownHeading(
            heading.group(1)!.length, parseMarkdownInline(content)));
      }
      continue;
    }

    if (_rulePattern.hasMatch(line)) {
      blocks.add(const MarkdownRule());
      index++;
      continue;
    }

    if (_quotePattern.hasMatch(line)) {
      final quote = <String>[];
      while (index < lines.length) {
        final match = _quotePattern.firstMatch(lines[index]);
        if (match == null) break;
        final content = match.group(1)!.trim();
        if (content.isNotEmpty || quote.isNotEmpty) quote.add(content);
        index++;
      }
      final text = quote.join('\n').trim();
      if (text.isNotEmpty) blocks.add(MarkdownQuote(parseMarkdownInline(text)));
      continue;
    }

    if (_isListLine(line)) {
      final entries = <_ListEntry>[];
      while (index < lines.length) {
        final current = lines[index];
        if (current.trim().isEmpty) {
          // 空行后仍是列表项时继续，否则结束当前列表。
          var next = index + 1;
          while (next < lines.length && lines[next].trim().isEmpty) {
            next++;
          }
          index = next;
          if (next < lines.length && _isListLine(lines[next])) continue;
          break;
        }
        final unordered = _unorderedItemPattern.firstMatch(current);
        final ordered = _orderedItemPattern.firstMatch(current);
        final match = unordered ?? ordered;
        if (match == null) {
          // 列表项的续行：缩进内容并入上一项。
          if (entries.isNotEmpty &&
              _indentOf(current) > 0 &&
              !_startsBlock(current)) {
            entries.last.text.write('\n${current.trim()}');
            index++;
            continue;
          }
          break;
        }
        entries.add(_ListEntry(
          depth: _listDepth(match.group(1)!.length),
          ordered: ordered != null,
          number: ordered == null ? null : int.tryParse(ordered.group(2)!),
          text: match.group(3)!,
        ));
        index++;
      }
      if (entries.isNotEmpty) {
        blocks.add(MarkdownList([
          for (final entry in entries)
            MarkdownListItem(
              runs: parseMarkdownInline(entry.text.toString()),
              depth: entry.depth,
              ordered: entry.ordered,
              number: entry.number,
            ),
        ]));
      }
      continue;
    }

    final paragraph = <String>[];
    while (index < lines.length) {
      final current = lines[index];
      if (current.trim().isEmpty ||
          (paragraph.isNotEmpty && _startsBlock(current))) {
        break;
      }
      paragraph.add(current.trim());
      index++;
    }
    if (paragraph.isNotEmpty) {
      blocks.add(MarkdownParagraph(parseMarkdownInline(paragraph.join('\n'))));
    }
  }
  return List.unmodifiable(blocks);
}

/// 解析行内标记，返回按格式切分的文本片段。
List<MarkdownRun> parseMarkdownInline(String source) {
  final runs = <MarkdownRun>[];
  _scanInline(source, runs);
  return List.unmodifiable(runs);
}

/// 行内文本片段及其格式。
class MarkdownRun {
  const MarkdownRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  /// 只保留 http/https 链接；不安全的地址在解析时被丢弃。
  final Uri? href;

  bool get isLink => href != null;

  @override
  bool operator ==(Object other) =>
      other is MarkdownRun &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strikethrough == strikethrough &&
      other.code == code &&
      other.href == href;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, strikethrough, code, href);

  @override
  String toString() => 'MarkdownRun("$text", bold: $bold, italic: $italic, '
      'strikethrough: $strikethrough, code: $code, href: $href)';
}

/// 块级节点。
sealed class MarkdownBlock {
  const MarkdownBlock();
}

final class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(this.level, this.runs);

  /// 1 到 6，越小的级别字号越大。
  final int level;
  final List<MarkdownRun> runs;
}

final class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.runs);
  final List<MarkdownRun> runs;
}

final class MarkdownQuote extends MarkdownBlock {
  const MarkdownQuote(this.runs);
  final List<MarkdownRun> runs;
}

/// 一组连续列表项，按缩进区分层级。
final class MarkdownList extends MarkdownBlock {
  const MarkdownList(this.items);
  final List<MarkdownListItem> items;
}

final class MarkdownListItem {
  const MarkdownListItem({
    required this.runs,
    this.depth = 0,
    this.ordered = false,
    this.number,
  });

  final List<MarkdownRun> runs;
  final int depth;
  final bool ordered;
  final int? number;
}

final class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock(this.code, {this.language});
  final String code;
  final String? language;
}

final class MarkdownRule extends MarkdownBlock {
  const MarkdownRule();
}

const _maxBlocks = 400;
const _maxInlineDepth = 8;
const _escapable = r'\`*_{}[]()#+-.!>~|';

final _headingPattern = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*))?$');
final _fencePattern = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*(.*)$');
final _rulePattern =
    RegExp(r'^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$');
final _quotePattern = RegExp(r'^ {0,3}>[ \t]?(.*)$');
final _unorderedItemPattern = RegExp(r'^( *)([-*+])[ \t]+(\S.*)$');
final _orderedItemPattern = RegExp(r'^( *)(\d{1,9})[.)][ \t]+(\S.*)$');
final _wordCharacter = RegExp(r'[A-Za-z0-9]');
final _breakCharacter = RegExp(r'\s');

class _ListEntry {
  _ListEntry({
    required this.depth,
    required this.ordered,
    required this.number,
    required String text,
  }) {
    this.text.write(text);
  }

  final int depth;
  final bool ordered;
  final int? number;
  final StringBuffer text = StringBuffer();
}

class _LinkMatch {
  const _LinkMatch(this.label, this.destination, this.end);
  final String label;
  final String destination;
  final int end;
}

class _EmphasisMatch {
  const _EmphasisMatch(
    this.content,
    this.end, {
    this.strong = false,
    this.emphasized = false,
    this.strikethrough = false,
  });

  final String content;
  final int end;
  final bool strong;
  final bool emphasized;
  final bool strikethrough;
}

bool _isInvalidFence(RegExpMatch match) =>
    match.group(1)!.startsWith('`') && match.group(2)!.contains('`');

bool _isListLine(String line) =>
    _unorderedItemPattern.hasMatch(line) || _orderedItemPattern.hasMatch(line);

bool _startsBlock(String line) =>
    _fencePattern.hasMatch(line) ||
    _headingPattern.hasMatch(line) ||
    _rulePattern.hasMatch(line) ||
    _quotePattern.hasMatch(line) ||
    _isListLine(line);

int _indentOf(String line) {
  var indent = 0;
  while (
      indent < line.length && (line[indent] == ' ' || line[indent] == '\t')) {
    indent += line[indent] == '\t' ? 2 : 1;
  }
  return indent;
}

int _listDepth(int indent) {
  if (indent >= 6) return 3;
  if (indent >= 4) return 2;
  if (indent >= 2) return 1;
  return 0;
}

void _scanInline(
  String source,
  List<MarkdownRun> out, {
  bool bold = false,
  bool italic = false,
  bool strike = false,
  Uri? href,
  int depth = 0,
}) {
  // 限制嵌套层级，避免异常输入触发过深的递归。
  if (depth > _maxInlineDepth) {
    _addRun(
        out,
        MarkdownRun(source,
            bold: bold, italic: italic, strikethrough: strike, href: href));
    return;
  }
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    _addRun(
        out,
        MarkdownRun(buffer.toString(),
            bold: bold, italic: italic, strikethrough: strike, href: href));
    buffer.clear();
  }

  var index = 0;
  while (index < source.length) {
    final char = source[index];

    // 反斜杠转义。
    if (char == '\\' &&
        index + 1 < source.length &&
        _escapable.contains(source[index + 1])) {
      buffer.write(source[index + 1]);
      index += 2;
      continue;
    }

    // 行内代码优先于强调，内部不再解析。
    if (char == '`') {
      final ticks = _runLength(source, index, '`');
      final end = _findCodeSpanEnd(source, index + ticks, ticks);
      if (end >= 0) {
        flush();
        _addRun(
            out,
            MarkdownRun(_codeSpanText(source.substring(index + ticks, end)),
                code: true,
                bold: bold,
                italic: italic,
                strikethrough: strike,
                href: href));
        index = end + ticks;
        continue;
      }
      buffer.write(source.substring(index, index + ticks));
      index += ticks;
      continue;
    }

    // 图片不加载网络资源，只显示替代文本。
    if (char == '!' && index + 1 < source.length && source[index + 1] == '[') {
      final link = _readLink(source, index + 1);
      if (link != null) {
        flush();
        _scanInline(link.label, out,
            bold: bold,
            italic: italic,
            strike: strike,
            href: href,
            depth: depth + 1);
        index = link.end;
        continue;
      }
      buffer.write(char);
      index++;
      continue;
    }

    if (char == '[') {
      final link = _readLink(source, index);
      if (link != null) {
        flush();
        final target = _safeLink(link.destination);
        _scanInline(link.label, out,
            bold: bold,
            italic: italic,
            strike: strike,
            // 不安全的链接地址被丢弃，标签按普通文本渲染。
            href: target,
            depth: depth + 1);
        index = link.end;
        continue;
      }
      buffer.write(char);
      index++;
      continue;
    }

    if (char == '<') {
      final end = source.indexOf('>', index + 1);
      final target =
          end > index + 1 ? _safeLink(source.substring(index + 1, end)) : null;
      if (target != null) {
        flush();
        _addRun(
            out,
            MarkdownRun(source.substring(index + 1, end),
                bold: bold,
                italic: italic,
                strikethrough: strike,
                href: target));
        index = end + 1;
        continue;
      }
    }

    if (char == '*' || char == '_' || char == '~') {
      final emphasis = _matchEmphasis(source, index, char);
      if (emphasis != null) {
        flush();
        _scanInline(emphasis.content, out,
            bold: bold || emphasis.strong,
            italic: italic || emphasis.emphasized,
            strike: strike || emphasis.strikethrough,
            href: href,
            depth: depth + 1);
        index = emphasis.end;
        continue;
      }
      final length = _runLength(source, index, char);
      buffer.write(source.substring(index, index + length));
      index += length;
      continue;
    }

    buffer.write(char);
    index++;
  }
  flush();
}

void _addRun(List<MarkdownRun> runs, MarkdownRun run) {
  if (run.text.isEmpty) return;
  if (runs.isNotEmpty) {
    final last = runs.last;
    if (last.bold == run.bold &&
        last.italic == run.italic &&
        last.strikethrough == run.strikethrough &&
        last.code == run.code &&
        last.href == run.href) {
      runs[runs.length - 1] = MarkdownRun(last.text + run.text,
          bold: run.bold,
          italic: run.italic,
          strikethrough: run.strikethrough,
          code: run.code,
          href: run.href);
      return;
    }
  }
  runs.add(run);
}

int _runLength(String source, int start, String char) {
  var end = start;
  while (end < source.length && source[end] == char) {
    end++;
  }
  return end - start;
}

int _findCodeSpanEnd(String source, int start, int ticks) {
  var index = start;
  while (index < source.length) {
    final found = source.indexOf('`', index);
    if (found < 0) return -1;
    final length = _runLength(source, found, '`');
    if (length == ticks) return found;
    index = found + length;
  }
  return -1;
}

String _codeSpanText(String code) {
  final text = code.replaceAll('\n', ' ');
  if (text.length >= 2 &&
      text.startsWith(' ') &&
      text.endsWith(' ') &&
      text.trim().isNotEmpty) {
    return text.substring(1, text.length - 1);
  }
  return text;
}

_LinkMatch? _readLink(String source, int opening) {
  var depth = 0;
  var index = opening;
  while (index < source.length) {
    final char = source[index];
    if (char == '\\') {
      index += 2;
      continue;
    }
    if (char == '[') depth++;
    if (char == ']') {
      depth--;
      if (depth == 0) break;
    }
    index++;
  }
  if (index >= source.length) return null;
  final label = source.substring(opening + 1, index);
  if (label.trim().isEmpty) return null;

  var cursor = index + 1;
  if (cursor >= source.length || source[cursor] != '(') return null;
  var parens = 1;
  var inAngle = false;
  cursor++;
  while (cursor < source.length) {
    final char = source[cursor];
    if (char == '\\') {
      cursor += 2;
      continue;
    }
    if (char == '<') inAngle = true;
    if (char == '>') inAngle = false;
    if (!inAngle && char == '(') parens++;
    if (!inAngle && char == ')') {
      parens--;
      if (parens == 0) break;
    }
    cursor++;
  }
  if (cursor >= source.length) return null;
  final destination = source.substring(index + 2, cursor).trim();
  if (destination.isEmpty) return null;
  return _LinkMatch(label, destination, cursor + 1);
}

Uri? _safeLink(String destination) {
  var raw = destination.trim();
  if (raw.startsWith('<')) {
    final end = raw.indexOf('>');
    if (end > 1) raw = raw.substring(1, end).trim();
  } else {
    // 去掉链接标题，例如 `https://example.com "标题"`。
    final space = raw.indexOf(_breakCharacter);
    if (space > 0) raw = raw.substring(0, space);
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri;
}

_EmphasisMatch? _matchEmphasis(String source, int index, String marker) {
  final length = _runLength(source, index, marker);
  final int delimiter;
  var strong = false;
  var emphasized = false;
  var strikethrough = false;
  if (marker == '~') {
    if (length < 2) return null;
    delimiter = 2;
    strikethrough = true;
  } else if (length >= 3) {
    delimiter = 3;
    strong = true;
    emphasized = true;
  } else if (length == 2) {
    delimiter = 2;
    strong = true;
  } else {
    delimiter = 1;
    emphasized = true;
  }

  final contentStart = index + delimiter;
  if (contentStart >= source.length) return null;
  final first = source[contentStart];
  if (first.trim().isEmpty) return null;
  if (marker == '_' &&
      index > 0 &&
      _wordCharacter.hasMatch(source[index - 1])) {
    return null;
  }

  final close = _findClosingDelimiter(source, contentStart, marker, delimiter);
  if (close < 0) return null;
  final content = source.substring(contentStart, close);
  if (content.trim().isEmpty) return null;
  return _EmphasisMatch(content, close + delimiter,
      strong: strong, emphasized: emphasized, strikethrough: strikethrough);
}

int _findClosingDelimiter(
    String source, int start, String marker, int delimiter) {
  var index = start;
  while (index < source.length) {
    final char = source[index];
    if (char == '\\') {
      index += 2;
      continue;
    }
    // 跳过行内代码，避免代码内容里的符号提前闭合强调。
    if (char == '`') {
      final ticks = _runLength(source, index, '`');
      final end = _findCodeSpanEnd(source, index + ticks, ticks);
      index = end >= 0 ? end + ticks : index + ticks;
      continue;
    }
    if (char != marker) {
      index++;
      continue;
    }
    final run = _runLength(source, index, marker);
    final validRun = delimiter == 1 ? run == 1 : run >= delimiter;
    final before = source[index - 1];
    final after = index + run;
    final validFlank = before.trim().isNotEmpty &&
        (marker != '_' ||
            after >= source.length ||
            !_wordCharacter.hasMatch(source[after]));
    if (validRun && validFlank) return index;
    index += run;
  }
  return -1;
}
