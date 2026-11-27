import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/markdown/markdown_document.dart';

String _plain(List<MarkdownRun> runs) => runs.map((run) => run.text).join();

MarkdownHeading _heading(MarkdownBlock block) => block as MarkdownHeading;

MarkdownList _list(MarkdownBlock block) => block as MarkdownList;

void main() {
  group('块级语法', () {
    test('解析标题层级并去掉闭合井号', () {
      final blocks = parseMarkdown('# 一级标题\n\n### 三级标题 ###\n\n###### 六级');
      expect(blocks, hasLength(3));
      expect(_heading(blocks[0]).level, 1);
      expect(_plain(_heading(blocks[0]).runs), '一级标题');
      expect(_heading(blocks[1]).level, 3);
      expect(_plain(_heading(blocks[1]).runs), '三级标题');
      expect(_heading(blocks[2]).level, 6);
      expect(_plain(_heading(blocks[2]).runs), '六级');
    });

    test('段落保留换行，忽略空行', () {
      final blocks = parseMarkdown('第一行\n第二行\n\n\n新段落');
      expect(blocks, hasLength(2));
      final first = blocks[0] as MarkdownParagraph;
      expect(_plain(first.runs), '第一行\n第二行');
      expect(_plain((blocks[1] as MarkdownParagraph).runs), '新段落');
    });

    test('解析无序、有序和嵌套列表', () {
      final blocks = parseMarkdown('- 第一项\n- 第二项\n  - 嵌套项\n1. 有序项\n2) 另一项');
      expect(blocks, hasLength(1));
      final list = _list(blocks.single);
      expect(list.items, hasLength(5));
      expect(_plain(list.items[0].runs), '第一项');
      expect(list.items[0].ordered, isFalse);
      expect(list.items[0].depth, 0);
      expect(_plain(list.items[2].runs), '嵌套项');
      expect(list.items[2].depth, 1);
      expect(list.items[3].ordered, isTrue);
      expect(list.items[3].number, 1);
      expect(list.items[4].number, 2);
    });

    test('列表项续行并入上一项', () {
      final blocks = parseMarkdown('- 第一行\n  第二行\n- 下一项');
      final list = _list(blocks.single);
      expect(_plain(list.items[0].runs), '第一行\n第二行');
      expect(_plain(list.items[1].runs), '下一项');
    });

    test('空行之后的列表项仍属于同一个列表', () {
      final blocks = parseMarkdown('- 一\n\n- 二\n\n段落');
      expect(blocks, hasLength(2));
      expect(_list(blocks[0]).items, hasLength(2));
      expect(blocks[1], isA<MarkdownParagraph>());
    });

    test('解析引用与分隔线', () {
      final blocks = parseMarkdown('> 引用第一行\n> 引用第二行\n\n---\n\n***');
      expect(blocks, hasLength(3));
      final quote = blocks[0] as MarkdownQuote;
      expect(_plain(quote.runs), '引用第一行\n引用第二行');
      expect(blocks[1], isA<MarkdownRule>());
      expect(blocks[2], isA<MarkdownRule>());
    });

    test('解析围栏代码块并保留内容', () {
      final blocks =
          parseMarkdown('说明\n\n```dart\nfinal a = 1;\n\nprint(a);\n```\n\n结束');
      expect(blocks, hasLength(3));
      final code = blocks[1] as MarkdownCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'final a = 1;\n\nprint(a);');
      expect(blocks[2], isA<MarkdownParagraph>());
    });

    test('未闭合的围栏代码块持续到结尾', () {
      final blocks = parseMarkdown('```\n未闭合');
      final code = blocks.single as MarkdownCodeBlock;
      expect(code.code, '未闭合');
      expect(code.language, isNull);
    });

    test('空内容和纯空白返回空列表', () {
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('   \n\n\t\n'), isEmpty);
    });

    test('CRLF 换行按段落处理', () {
      final blocks = parseMarkdown('第一行\r\n\r\n第二行');
      expect(blocks, hasLength(2));
      expect(_plain((blocks[0] as MarkdownParagraph).runs), '第一行');
    });
  });

  group('行内语法', () {
    test('粗体、斜体与粗斜体', () {
      final runs = parseMarkdownInline(
          '**粗体** 与 *斜体* 与 ***粗斜体*** 与 __另一种粗体__ 与 _另一种斜体_');
      expect(_plain(runs), '粗体 与 斜体 与 粗斜体 与 另一种粗体 与 另一种斜体');
      expect(_plain(runs.where((run) => run.bold).toList()), '粗体粗斜体另一种粗体');
      expect(_plain(runs.where((run) => run.italic).toList()), '斜体粗斜体另一种斜体');
    });

    test('删除线与行内代码', () {
      final runs = parseMarkdownInline('~~旧内容~~ 和 `code` 和 ``a ` b``');
      expect(_plain(runs), '旧内容 和 code 和 a ` b');
      expect(runs.firstWhere((run) => run.text == '旧内容').strikethrough, isTrue);
      expect(runs.firstWhere((run) => run.text == 'code').code, isTrue);
      expect(runs.last.code, isTrue);
      expect(runs.last.text, 'a ` b');
    });

    test('强调可以嵌套', () {
      final runs = parseMarkdownInline('**粗体中的 *斜体* 文本** 与 *斜体中的 **粗体** 文本*');
      expect(_plain(runs), '粗体中的 斜体 文本 与 斜体中的 粗体 文本');
      final bold = runs.where((run) => run.bold).toList();
      expect(bold.any((run) => run.italic), isTrue);
      final italic = runs.where((run) => run.italic).toList();
      expect(italic.any((run) => run.bold), isTrue);
    });

    test('链接与自动链接只保留 http/https', () {
      final runs = parseMarkdownInline(
          '[发布页](https://example.com/a "标题") 和 <https://example.org/b>');
      expect(_plain(runs), '发布页 和 https://example.org/b');
      final links = runs.where((run) => run.href != null).toList();
      expect(links, hasLength(2));
      expect(links[0].href, Uri.parse('https://example.com/a'));
      expect(links[1].href, Uri.parse('https://example.org/b'));
      expect(links[0].text, '发布页');
    });

    test('拒绝不安全或无效的链接地址', () {
      for (final source in [
        '[点击](javascript:alert(1))',
        '[文件](file:///etc/passwd)',
        '[凭证](https://user:pass@example.com)',
        '[空]()',
        '[相对路径](/download)',
      ]) {
        final runs = parseMarkdownInline(source);
        expect(runs.any((run) => run.href != null), isFalse,
            reason: '不应接受 $source');
      }
    });

    test('图片只显示替代文本', () {
      final runs = parseMarkdownInline('![截图](https://example.com/a.png)');
      expect(_plain(runs), '截图');
      expect(runs.single.href, isNull);
    });

    test('下划线不破坏 snake_case', () {
      final runs = parseMarkdownInline('some_snake_case_name');
      expect(runs, hasLength(1));
      expect(runs.single.text, 'some_snake_case_name');
      expect(runs.single.italic, isFalse);
    });

    test('反斜杠转义不触发格式', () {
      final runs = parseMarkdownInline(r'\*不是斜体\* 和 \[不是链接\]');
      expect(_plain(runs), '*不是斜体* 和 [不是链接]');
      expect(runs.any((run) => run.italic || run.href != null), isFalse);
    });

    test('未闭合或空内容的分隔符按字面保留', () {
      expect(_plain(parseMarkdownInline('**没闭合')), '**没闭合');
      expect(_plain(parseMarkdownInline('** **')), '** **');
      expect(parseMarkdownInline('****').any((run) => run.bold), isFalse);
      expect(_plain(parseMarkdownInline('2 * 3 * 4')), '2 * 3 * 4');
    });

    test('行内代码内的标记不再解析', () {
      final runs = parseMarkdownInline('`**不是粗体**`');
      expect(runs.single.code, isTrue);
      expect(runs.single.text, '**不是粗体**');
      expect(runs.single.bold, isFalse);
    });

    test('相邻同格式片段合并', () {
      final runs = parseMarkdownInline('a**b****c**d');
      expect(runs, hasLength(3));
      expect(runs[0].text, 'a');
      expect(runs[1].text, 'bc');
      expect(runs[1].bold, isTrue);
      expect(runs[2].text, 'd');
    });
  });
}
