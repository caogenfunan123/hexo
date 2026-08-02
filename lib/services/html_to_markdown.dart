/// HTML → Markdown 转换器
///
/// 用于从 CMS 拉取线上文章到编辑器时的格式转换。
/// 支持常见 HTML 标签的逆向转换，不依赖第三方库。
class HtmlToMarkdown {
  HtmlToMarkdown._();

  /// 将 HTML 字符串转换为 Markdown
  static String convert(String html) {
    if (html.isEmpty) return '';
    var result = html;

    // 0. 解码 HTML 实体
    result = _decodeEntities(result);

    // 1. 处理 Gutenberg 注释块（WordPress）
    result = result.replaceAll(RegExp(r'<!-- /?wp:\w+(\s+\{[^}]*\})?\s*-->'), '');
    result = result.replaceAll(RegExp(r'<!-- /?wp:\w+(\s+\{[^}]*\})?\s*/-->'), '');

    // 2. 处理 <br> 和 <br/>
    result = result.replaceAll(RegExp(r'<br\s*/?>'), '\n');

    // 3. 处理 <hr>
    result = result.replaceAll(RegExp(r'<hr\s*/?>'), '\n---\n');

    // 4. 处理 pre/code 块
    result = _convertCodeBlocks(result);

    // 5. 处理图片
    result = _convertImages(result);

    // 6. 处理链接
    result = _convertLinks(result);

    // 7. 处理标题
    result = _convertHeadings(result);

    // 8. 处理列表
    result = _convertLists(result);

    // 9. 处理引用
    result = _convertBlockquotes(result);

    // 10. 处理表格
    result = _convertTables(result);

    // 11. 处理行内格式
    result = _convertInlineFormat(result);

    // 12. 处理段落
    result = _convertParagraphs(result);

    // 13. 清理多余空白
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 14. 移除残留的 HTML 标签
    result = result.replaceAll(RegExp(r'<[^>]+>'), '');

    return result.trim();
  }

  /// 解码常见 HTML 实体
  static String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8212;', '—')
        .replaceAll('&#8216;', '\'')
        .replaceAll('&#8217;', '\'')
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&#8230;', '...');
  }

  /// 转换代码块
  static String _convertCodeBlocks(String html) {
    // <pre><code>...</code></pre> 或 <pre class="wp-block-code"><code>...</code></pre>
    final preRegex = RegExp(
      r'<pre[^>]*><code[^>]*>(.*?)</code></pre>',
      dotAll: true,
    );
    return html.replaceAllMapped(preRegex, (m) {
      var code = m.group(1) ?? '';
      code = _decodeEntities(code);
      code = code.trimRight();
      return '\n```\n$code\n```\n';
    });
  }

  /// 转换图片
  static String _convertImages(String html) {
    // <img src="..." alt="..." />
    final imgRegex = RegExp(
      r'<img[^>]+src="([^"]+)"[^>]*?(?:alt="([^"]*)")?[^>]*/?>',
      dotAll: true,
    );
    return html.replaceAllMapped(imgRegex, (m) {
      final src = m.group(1) ?? '';
      final alt = m.group(2) ?? '';
      return '![$alt]($src)';
    });
  }

  /// 转换链接
  static String _convertLinks(String html) {
    // <a href="...">text</a>
    final linkRegex = RegExp(
      r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    return html.replaceAllMapped(linkRegex, (m) {
      final href = m.group(1) ?? '';
      final text = m.group(2) ?? '';
      return '[$text]($href)';
    });
  }

  /// 转换标题
  static String _convertHeadings(String html) {
    var result = html;
    for (var level = 6; level >= 1; level--) {
      final prefix = '#' * level;
      // 带 class 的标题（如 Gutenberg）
      final classRegex = RegExp(
        '<h$level[^>]*>(.*?)</h$level>',
        dotAll: true,
      );
      result = result.replaceAllMapped(classRegex, (m) {
        final text = (m.group(1) ?? '').trim();
        return '\n$prefix $text\n';
      });
    }
    return result;
  }

  /// 转换列表
  static String _convertLists(String html) {
    var result = html;

    // <ul><li>...</li></ul>
    final ulRegex = RegExp(r'<ul[^>]*>(.*?)</ul>', dotAll: true);
    result = result.replaceAllMapped(ulRegex, (m) {
      final content = m.group(1) ?? '';
      final items = _extractListItems(content);
      return '\n${items.map((e) => '- $e').join('\n')}\n';
    });

    // <ol><li>...</li></ol>
    final olRegex = RegExp(r'<ol[^>]*>(.*?)</ol>', dotAll: true);
    result = result.replaceAllMapped(olRegex, (m) {
      final content = m.group(1) ?? '';
      final items = _extractListItems(content);
      final buf = StringBuffer();
      for (var i = 0; i < items.length; i++) {
        buf.writeln('${i + 1}. ${items[i]}');
      }
      return '\n${buf.toString()}';
    });

    return result;
  }

  static List<String> _extractListItems(String html) {
    final items = <String>[];
    final liRegex = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true);
    for (final m in liRegex.allMatches(html)) {
      var text = (m.group(1) ?? '').trim();
      // 递归处理嵌套内容
      text = text.replaceAll(RegExp(r'<[^>]+>'), '');
      items.add(_decodeEntities(text));
    }
    return items;
  }

  /// 转换引用块
  static String _convertBlockquotes(String html) {
    final bqRegex = RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', dotAll: true);
    return html.replaceAllMapped(bqRegex, (m) {
      final content = (m.group(1) ?? '').trim();
      // 去除内部 <p> 标签
      final text = content
          .replaceAll(RegExp(r'</?p[^>]*>'), '')
          .replaceAll(RegExp(r'<[^>]+>'), '');
      final lines = text.split('\n');
      return '\n${lines.map((l) => '> $l').join('\n')}\n';
    });
  }

  /// 转换表格
  static String _convertTables(String html) {
    final tableRegex = RegExp(r'<table[^>]*>(.*?)</table>', dotAll: true);
    return html.replaceAllMapped(tableRegex, (m) {
      final content = m.group(1) ?? '';
      final buf = StringBuffer();
      final rows = <List<String>>[];

      // 提取所有行
      final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
      for (final tr in trRegex.allMatches(content)) {
        final rowContent = tr.group(1) ?? '';
        final cells = <String>[];
        final cellRegex = RegExp(r'<(?:th|td)[^>]*>(.*?)</(?:th|td)>', dotAll: true);
        for (final cell in cellRegex.allMatches(rowContent)) {
          cells.add((cell.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim());
        }
        if (cells.isNotEmpty) rows.add(cells);
      }

      if (rows.isEmpty) return '';

      // 输出表头
      buf.write('| ${rows.first.join(' | ')} |\n');
      // 输出分隔行
      buf.write('| ${rows.first.map((_) => '---').join(' | ')} |\n');
      // 输出数据行
      for (var i = 1; i < rows.length; i++) {
        buf.write('| ${rows[i].join(' | ')} |\n');
      }

      return '\n${buf.toString()}';
    });
  }

  /// 转换行内格式
  static String _convertInlineFormat(String html) {
    var result = html;

    // <strong> / <b>
    result = result.replaceAllMapped(
      RegExp(r'<(?:strong|b)>(.*?)</(?:strong|b)>', dotAll: true),
      (m) => '**${m.group(1)}**',
    );

    // <em> / <i>
    result = result.replaceAllMapped(
      RegExp(r'<(?:em|i)>(.*?)</(?:em|i)>', dotAll: true),
      (m) => '*${m.group(1)}*',
    );

    // <code>（非 pre 内的）
    result = result.replaceAllMapped(
      RegExp(r'<code[^>]*>(.*?)</code>', dotAll: true),
      (m) => '`${m.group(1)}`',
    );

    // <del> / <s> / <strike>
    result = result.replaceAllMapped(
      RegExp(r'<(?:del|s|strike)>(.*?)</(?:del|s|strike)>', dotAll: true),
      (m) => '~~${m.group(1)}~~',
    );

    return result;
  }

  /// 转换段落
  static String _convertParagraphs(String html) {
    // <p>...</p> → 双换行分隔
    final pRegex = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
    return html.replaceAllMapped(pRegex, (m) {
      final text = (m.group(1) ?? '').trim();
      if (text.isEmpty) return '';
      return '\n$text\n';
    });
  }

  /// 从 Gutenberg HTML 内容中提取 Markdown
  /// WordPress 特定处理
  static String fromGutenberg(String html) {
    if (html.isEmpty) return '';
    // 先处理 Gutenberg 的 block 注释
    var cleaned = html.replaceAll(RegExp(r'<!--\s*/?wp:(\w|-)+(\s+\{[^}]*\})?\s*/?-->'), '\n');
    return convert(cleaned);
  }
}