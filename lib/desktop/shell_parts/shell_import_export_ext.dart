// 导入 / 导出扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellImportExportExt on DesktopShellState {
  Future<void> _importHtmlFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      final file = File(filePath);
      final html = await file.readAsString();
      final markdown = HtmlToMarkdown.convert(html);
      final fileName = result.files.first.name.replaceAll(
        RegExp(r'\.html?$', caseSensitive: false),
        '',
      );
      final article = Article(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: fileName,
        content: markdown,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
      );
      _openExistingArticle(article);
      _showToast('已导入 HTML: $fileName');
    } catch (e) {
      _showToast('导入失败: $e');
    }
  }

  Future<void> _importDocxFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;

      // DOCX 是 ZIP 格式，提取 document.xml 并转换
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // 简单处理：读取 DOCX 中的文本
      // 实际实现需要解压 ZIP 并解析 XML
      final fileName = result.files.first.name.replaceAll('.docx', '');
      final markdown = await _extractDocxText(bytes);

      final article = Article(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: fileName,
        content: markdown,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
      );
      _openExistingArticle(article);
      _showToast('已导入 DOCX: $fileName');
    } catch (e) {
      _showToast('DOCX 导入失败: $e\n请确保文件格式正确');
    }
  }

  Future<String> _extractDocxText(Uint8List bytes) async {
    try {
      // 使用 archive 库正确解压 ZIP/DOCX 文件
      final archive = ZipDecoder().decodeBytes(bytes);

      // 查找 document.xml 文件
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        return '*无法在 DOCX 中找到 document.xml*';
      }

      final xmlContent = utf8.decode(documentFile.content as List<int>);

      // 提取 <w:t> 标签中的文本
      final textRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
      final matches = textRegex.allMatches(xmlContent);
      final paragraphs = <String>[];
      String currentParagraph = '';

      // 同时检测段落边界
      final paraRegex = RegExp(r'<w:p[ >]');
      final paraEndRegex = RegExp(r'</w:p>');
      final allParaStarts = paraRegex
          .allMatches(xmlContent)
          .map((m) => m.start)
          .toList();
      final allParaEnds = paraEndRegex
          .allMatches(xmlContent)
          .map((m) => m.end)
          .toList();

      for (final match in matches) {
        final t = match.group(1) ?? '';
        currentParagraph += t;

        // 检查当前 match 之后是否有段落结束标记
        final matchEnd = match.end;
        final nextParaEnd = allParaEnds.firstWhere(
          (e) => e > matchEnd,
          orElse: () => -1,
        );
        final nextParaStart = allParaStarts.firstWhere(
          (s) => s > matchEnd,
          orElse: () => -1,
        );

        // 如果在下一个段落开始之前有段落结束，则当前段落结束
        if (nextParaEnd > 0 &&
            (nextParaStart < 0 || nextParaEnd < nextParaStart)) {
          if (currentParagraph.trim().isNotEmpty) {
            paragraphs.add(currentParagraph.trim());
          }
          currentParagraph = '';
        }
      }

      // 添加最后一个段落
      if (currentParagraph.trim().isNotEmpty) {
        paragraphs.add(currentParagraph.trim());
      }

      return paragraphs.isEmpty ? '*DOCX 文件内容为空*' : paragraphs.join('\n\n');
    } catch (e) {
      return '*无法解析 DOCX 文件内容: $e\n请尝试使用 HTML 格式导入*';
    }
  }

  String _safeTitle(String title) {
    return title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _mdToHtml(String markdown, String title) {
    var body = md.markdownToHtml(markdown.isEmpty ? '*暂无内容*' : markdown);
    // 清洗正文：剥离 script/style 标签、事件处理器属性与危险 URL，防存储型 XSS
    body = _sanitizeHtml(body);
    // 包装为完整的 HTML 模板
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeHtml(title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      max-width: 800px;
      margin: 40px auto;
      padding: 0 20px;
      line-height: 1.8;
      font-size: 16px;
      color: #333;
    }
    h1 { font-size: 2em; margin-top: 0.5em; }
    h2 { font-size: 1.5em; margin-top: 1em; }
    h3 { font-size: 1.2em; margin-top: 0.8em; }
    pre { background: #f5f5f5; padding: 16px; border-radius: 6px; overflow-x: auto; }
    code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
    pre code { background: none; padding: 0; }
    blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 16px; color: #666; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
    th { background: #f5f5f5; }
  </style>
</head>
<body>
$body
</body>
</html>''';
  }

  String _sanitizeHtml(String html) {
    var result = html.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<iframe[^>]*>[\s\S]*?</iframe>', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<object[^>]*>[\s\S]*?</object>', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<embed[^>]*>[\s\S]*?</embed>', caseSensitive: false),
      '',
    );
    // 事件处理器属性
    result = result.replaceAll(
      RegExp(
        r'''\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
        caseSensitive: false,
      ),
      '',
    );
    // javascript: / data: 危险 URL（属性值形式）
    result = result.replaceAllMapped(
      RegExp(
        r'''\s+(href|src)\s*=\s*("[^"]*"|'[^']*')''',
        caseSensitive: false,
      ),
      (match) {
        final quote = match.group(2) ?? '';
        if (quote.isNotEmpty) {
          final inner = quote.length >= 2
              ? quote.substring(1, quote.length - 1)
              : quote;
          if (RegExp(
            r'^(javascript|vbscript|data):',
            caseSensitive: false,
          ).hasMatch(inner.trim())) {
            return '';
          }
        }
        return match.group(0)!;
      },
    );
    // 无引号形式的危险 URL
    result = result.replaceAllMapped(
      RegExp(r'''\s+(href|src)\s*=\s*[^\s>]+''', caseSensitive: false),
      (match) {
        final rest = match.group(0)!;
        if (RegExp(
          r'=\s*(javascript|vbscript|data):',
          caseSensitive: false,
        ).hasMatch(rest)) {
          return '';
        }
        return rest;
      },
    );
    return result;
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<void> _exportHtml() async {
    try {
      final title = _doc.titleCtrl.text.isNotEmpty
          ? _doc.titleCtrl.text
          : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 HTML 文件',
        fileName: '$safeTitle.html',
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      if (result == null) return;
      final html = _mdToHtml(_doc.contentCtrl.text, title);
      final file = File(result);
      await file.writeAsString(html);
      if (mounted) _showToast('HTML 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('HTML 导出失败: $e');
    }
  }

  Future<void> _exportPdf() async {
    try {
      final title = _doc.titleCtrl.text.isNotEmpty
          ? _doc.titleCtrl.text
          : 'untitled';
      final safeTitle = _safeTitle(title);
      final html = _mdToHtml(_doc.contentCtrl.text, title);

      try {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出 PDF 文件',
          fileName: '$safeTitle.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result == null) return;

        // 使用 Printing 包将 HTML 直接转换为 PDF 字节
        // ignore: deprecated_member_use
        final pdfBytes = await Printing.convertHtml(
          format: PdfPageFormat.a4,
          html: html,
        );
        final file = File(result);
        await file.writeAsBytes(pdfBytes);
        if (mounted) _showToast('PDF 已导出到: $result');
      } catch (e) {
        debugPrint('Shell: settings load failed: $e');
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出 PDF 文件（回退 HTML）',
          fileName: '$safeTitle.html',
          type: FileType.custom,
          allowedExtensions: ['html'],
        );
        if (result == null) return;
        final file = File(result);
        await file.writeAsString(html);
        if (mounted) _showToast('PDF 导出回退为 HTML: $result');
      }
    } catch (e) {
      if (mounted) _showToast('PDF 导出失败: $e');
    }
  }

  Future<void> _exportDocx() async {
    try {
      final title = _doc.titleCtrl.text.isNotEmpty
          ? _doc.titleCtrl.text
          : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 DOCX 文件',
        fileName: '$safeTitle.docx',
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result == null) return;

      final htmlContent = _mdToHtml(_doc.contentCtrl.text, title);

      // 构建基本的 Office Open XML 结构
      final docxBytes = _buildDocxZip(title, htmlContent);
      final file = File(result);
      await file.writeAsBytes(docxBytes);
      if (mounted) _showToast('DOCX 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('DOCX 导出失败: $e');
    }
  }

  Uint8List _buildDocxZip(String title, String htmlContent) {
    final escapedTitle = _escapeXml(title);
    final escapedHtml = _escapeXmlBody(htmlContent);

    // [Content_Types].xml
    const contentTypes =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    // _rels/.rels
    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    // word/_rels/document.xml.rels
    const wordRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

    // word/document.xml - 将 HTML 内容转换为基本的 OOXML 段落
    final documentXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Title"/>
      </w:pPr>
      <w:r>
        <w:rPr/>
        <w:t>$escapedTitle</w:t>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:rPr/>
        <w:t xml:space="preserve">$escapedHtml</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

    // 构建 ZIP 文件
    final entries = <String, List<int>>{
      '[Content_Types].xml': utf8.encode(contentTypes),
      '_rels/.rels': utf8.encode(rels),
      'word/_rels/document.xml.rels': utf8.encode(wordRels),
      'word/document.xml': utf8.encode(documentXml),
    };

    return _createZip(entries);
  }

  Future<void> _exportEpub() async {
    try {
      final title = _doc.titleCtrl.text.isNotEmpty
          ? _doc.titleCtrl.text
          : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 EPUB 文件',
        fileName: '$safeTitle.epub',
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (result == null) return;

      final epubBytes = _buildEpubZip(title);
      final file = File(result);
      await file.writeAsBytes(epubBytes);
      if (mounted) _showToast('EPUB 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('EPUB 导出失败: $e');
    }
  }

  Uint8List _buildEpubZip(String title) {
    final escapedTitle = _escapeXml(title);
    final fullHtml = _mdToHtml(_doc.contentCtrl.text, title);
    // 提取 body 中的内容（去掉外层 HTML 模板）
    final bodyMatch = RegExp(
      r'<body>\n?(.*)\n?</body>',
      dotAll: true,
    ).firstMatch(fullHtml);
    final htmlContent = bodyMatch?.group(1) ?? fullHtml;
    final now = DateTime.now().toUtc().toIso8601String();
    final uuid = DateTime.now().millisecondsSinceEpoch.toRadixString(16);

    // mimetype 文件（必须无压缩，且是 ZIP 的第一个条目）
    const mimetype = 'application/epub+zip';

    // META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

    // OEBPS/content.opf
    final contentOpf =
        '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:uuid:$uuid</dc:identifier>
    <dc:title>$escapedTitle</dc:title>
    <dc:creator>Hexo Editor</dc:creator>
    <dc:language>zh-CN</dc:language>
    <dc:date>$now</dc:date>
    <meta property="dcterms:modified">$now</meta>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>''';

    // OEBPS/toc.ncx
    final tocNcx =
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:$uuid"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>$escapedTitle</text>
  </docTitle>
  <navMap>
    <navPoint id="navpoint-1" playOrder="1">
      <navLabel>
        <text>$escapedTitle</text>
      </navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''';

    // OEBPS/chapter1.xhtml
    final chapterXhtml =
        '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>$escapedTitle</title>
  <style>
    body { font-family: serif; max-width: 100%; margin: 0; padding: 1em; line-height: 1.8; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.2em; }
    pre { background: #f5f5f5; padding: 1em; white-space: pre-wrap; }
    code { font-family: monospace; }
    blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 1em; color: #666; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; }
  </style>
</head>
<body>
<h1>$escapedTitle</h1>
$htmlContent
</body>
</html>''';

    // 构建 ZIP（mimetype 必须是第一个且不压缩）
    final entries = <String, List<int>>{
      'mimetype': utf8.encode(mimetype),
      'META-INF/container.xml': utf8.encode(containerXml),
      'OEBPS/content.opf': utf8.encode(contentOpf),
      'OEBPS/toc.ncx': utf8.encode(tocNcx),
      'OEBPS/chapter1.xhtml': utf8.encode(chapterXhtml),
    };

    return _createZip(entries);
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _escapeXmlBody(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  Uint8List _createZip(Map<String, List<int>> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      final file = ArchiveFile(entry.key, entry.value.length, entry.value);
      archive.addFile(file);
    }
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }
}
