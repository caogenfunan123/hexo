// 文本编辑 / 插入扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellTextExt on DesktopShellState {
  void _autoSelectTemplate() {
    if (_editorRepo == null) return;
    final isPage = _doc.articleType == ArticleType.page;
    // 当前选中模板与文章类型不匹配时先清除，
    // 避免 Dropdown value 不在过滤后 items 中触发断言崩溃
    final cur = _doc.selectedTemplateId;
    if (cur != null && cur.isNotEmpty) {
      TemplateItem? t;
      for (final x in templates) {
        if (x.id == cur) {
          t = x;
          break;
        }
      }
      if (t != null && t.isPost == isPage) {
        // 类型匹配，无需重选
        return;
      }
      if (t != null) _doc.setSelectedTemplateId(null);
    }
    final id = isPage
        ? TemplateResolver.resolvePageTemplateId(_editorRepo!, templates)
        : TemplateResolver.resolvePostTemplateId(_editorRepo!, templates);
    if (id != null) _doc.setSelectedTemplateId(id);
  }

  Future<void> _retryUploadImage() async {
    if (_editor.failedImageBytes == null) return;
    final bytes = _editor.failedImageBytes!;
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在重试上传...');
    try {
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _editor.setFailedImageBytes(null);
      _editor.setEditorStatus('图片已插入');
    } catch (e) {
      _editor.setEditorStatus('重试上传失败');
      if (mounted) _showToast('重试上传失败: $e');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  void _insertText(String t) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, t),
      selection: TextSelection.collapsed(offset: s + t.length),
    );
    _doc.contentFocus.requestFocus();
    // 程序化写入同样触发内容变更管线（预览/字数/自动保存）
    _onContentChanged();
  }

  void _insertCodeBlock() {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? txt.substring(sel.start, sel.end)
        : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, fence),
      selection: TextSelection.collapsed(offset: s + 4),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  Future<void> _insertImage() async {
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在选择图片...');
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) {
        _editor.setEditorStatus('已取消');
        return;
      }
      _editor.setFailedImageBytes(bytes);
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      _editor.setEditorStatus('正在上传图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _editor.setFailedImageBytes(null);
      _editor.setEditorStatus('图片已插入');
    } catch (e) {
      _insertText('\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)\n');
      _editor.setEditorStatus('上传失败（可点击重试）');
      if (mounted) _showToast('上传失败，点击文中标记可重试');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  Future<String?> _handleDroppedImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      _editor.setEditorStatus('正在上传拖拽图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _editor.setEditorStatus('图片已插入');
      return imageService.markdownImage(url);
    } catch (e) {
      _editor.setEditorStatus('拖拽图片上传失败');
      if (mounted) _showToast('拖拽图片上传失败: $e');
      return '\n> ⚠️ 拖拽图片上传失败\n';
    }
  }

  Future<void> _batchInsertImages() async {
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在选择图片...');
    try {
      final bytesList = await imageService.pickMultipleImageBytes();
      if (bytesList == null || bytesList.isEmpty) {
        _editor.setEditorStatus('已取消');
        return;
      }
      final total = bytesList.length;
      _editor.setEditorStatus('正在预处理 $total 张图片...');
      final preResult = await imageService.preprocessImages(
        bytesList,
        settings,
        onProgress: (current, total, beforeKB, afterKB) {
          if (mounted)
            _editor.setEditorStatus(
              '预处理 $current/$total: ${beforeKB}KB → ${afterKB}KB',
            );
        },
      );
      int uploaded = 0;
      int failed = 0;
      final buf = StringBuffer();
      for (var i = 0; i < total; i++) {
        _editor.setEditorStatus('正在上传图片 ${i + 1}/$total...');
        try {
          final url = await imageService.uploadToImageBed(
            preResult.images[i],
            settings,
            skipCompress: true,
          );
          buf.writeln(imageService.markdownImage(url));
          uploaded++;
        } catch (e) {
          debugPrint('Shell: batch upload image failed: $e');
          // 缓存失败图片字节供工具栏重试按钮使用，写入标准重试标记
          _editor.setFailedImageBytes(preResult.images[i]);
          buf.writeln('\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)');
          failed++;
        }
      }
      _insertText('\n\n${buf.toString()}');
      if (failed > 0) {
        _editor.setEditorStatus('完成: $uploaded/$total 张上传成功，$failed 张失败可重试');
        if (mounted) _showToast('有 $failed 张图片上传失败，可点击编辑器工具栏重试');
      } else {
        _editor.setEditorStatus('完成: $uploaded/$total 张上传成功');
      }
    } catch (e) {
      _editor.setEditorStatus('批量上传失败');
      if (mounted) _showToast('批量上传失败: $e');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  void _insertToc() {
    final text = _doc.contentCtrl.text;
    final lines = text.split('\n');
    final tocBuf = StringBuffer();
    tocBuf.writeln('<!-- TOC -->');
    tocBuf.writeln();

    final headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
    for (final line in lines) {
      final match = headingPattern.firstMatch(line.trim());
      if (match != null) {
        final level = match.group(1)!.length;
        final title = match.group(2)!.trim();
        final anchor = title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '')
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'-+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
        final indent = '  ' * (level - 1);
        tocBuf.writeln('$indent- [$title](#$anchor)');
      }
    }

    tocBuf.writeln();
    tocBuf.writeln('<!-- /TOC -->');

    final toc = tocBuf.toString();

    // 检查是否有 [toc] 占位符
    final tocPlaceholder = RegExp(r'\[toc\]', caseSensitive: false);
    final placeholderMatch = tocPlaceholder.firstMatch(text);
    if (placeholderMatch != null) {
      _doc.contentCtrl.value = TextEditingValue(
        text: text.replaceRange(
          placeholderMatch.start,
          placeholderMatch.end,
          toc,
        ),
        selection: TextSelection.collapsed(
          offset: placeholderMatch.start + toc.length,
        ),
      );
    } else {
      // 插入到光标位置
      final sel = _doc.contentCtrl.selection;
      final pos = sel.isValid ? sel.start : text.length;
      _doc.contentCtrl.value = TextEditingValue(
        text: text.replaceRange(pos, pos, '\n$toc\n'),
        selection: TextSelection.collapsed(offset: pos + toc.length + 2),
      );
    }
    _doc.contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('TOC 已生成');
  }

  void _toggleImagePathMode() {
    final siteUrl = activeRepo?.siteUrl ?? '';
    if (siteUrl.isEmpty) {
      if (mounted) _showToast('请先配置站点 URL');
      return;
    }

    final text = _doc.contentCtrl.text;
    // 规范化 siteUrl（去掉末尾斜杠）
    final baseUrl = siteUrl.endsWith('/')
        ? siteUrl.substring(0, siteUrl.length - 1)
        : siteUrl;
    final imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

    if (!_editor.useRelativeImagePath) {
      // 转换为相对路径：https://site.com/images/photo.png → images/photo.png
      final replaced = text.replaceAllMapped(imagePattern, (m) {
        final alt = m.group(1) ?? '';
        var url = m.group(2) ?? '';
        if (url.startsWith(baseUrl)) {
          url = url.substring(baseUrl.length);
          if (url.startsWith('/')) url = url.substring(1);
        }
        return '![$alt]($url)';
      });
      _doc.contentCtrl.text = replaced;
      if (mounted) {
        _editor.setImagePathMode(true);
        _showToast('已切换为相对路径模式');
      }
    } else {
      // 转换为绝对路径：images/photo.png → https://site.com/images/photo.png
      final replaced = text.replaceAllMapped(imagePattern, (m) {
        final alt = m.group(1) ?? '';
        var url = m.group(2) ?? '';
        // 只转换相对路径或本地路径
        if (!url.startsWith('http://') &&
            !url.startsWith('https://') &&
            !url.startsWith('//')) {
          // 处理 ./ ../ 等相对路径
          url = url.replaceAll(RegExp(r'^\./'), '');
          url = url.replaceAll(RegExp(r'^(\.\./)+'), '');
          if (!url.startsWith('/')) url = '/$url';
          return '![$alt]($baseUrl$url)';
        }
        return m.group(0)!;
      });
      _doc.contentCtrl.text = replaced;
      if (mounted) {
        _editor.setImagePathMode(false);
        _showToast('已切换为绝对路径模式');
      }
    }
    _onContentChanged();
  }

  void _insertTable() {
    const table =
        '| 列1 | 列2 | 列3 |\n'
        '| --- | --- | --- |\n'
        '| 内容 | 内容 | 内容 |\n'
        '| 内容 | 内容 | 内容 |\n'
        '| 内容 | 内容 | 内容 |\n';
    _insertText('\n$table\n');
    if (mounted) _showToast('表格已插入');
  }

  void _addTableRow() {
    final text = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;

    // 找到光标所在行
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final lineEnd = after.indexOf('\n');
    final currentLine = lineEnd >= 0
        ? text.substring(lineStart, pos + lineEnd)
        : text.substring(lineStart);

    // 检测是否在表格中
    if (!currentLine.trimLeft().startsWith('|')) {
      if (mounted) _showToast('光标不在表格中');
      return;
    }

    // 分析表格列数
    final cols = '|'.allMatches(currentLine).length - 1;
    if (cols <= 0) {
      if (mounted) _showToast('未检测到有效表格');
      return;
    }

    // 构建新行
    final newRow = '| ${List.filled(cols, '内容').join(' | ')} |\n';

    // 找到当前行结束位置
    final rowEnd = lineEnd >= 0 ? lineStart + lineEnd : text.length;
    // 找到下一行开始
    final nextLineStart = rowEnd < text.length ? rowEnd + 1 : text.length;

    _doc.contentCtrl.value = TextEditingValue(
      text: text.replaceRange(nextLineStart, nextLineStart, newRow),
      selection: TextSelection.collapsed(offset: nextLineStart + newRow.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('已添加表格行');
  }

  void _addTableCol() {
    final text = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;

    // 找到光标所在行
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final lineEnd = after.indexOf('\n');
    final actualLineEnd = lineEnd >= 0 ? pos + lineEnd : text.length;
    final currentLine = text.substring(lineStart, actualLineEnd);

    if (!currentLine.trimLeft().startsWith('|')) {
      if (mounted) _showToast('光标不在表格中');
      return;
    }

    // 找到表格块起始
    int tableStart = lineStart;
    while (tableStart > 0) {
      final prevLineEnd = tableStart - 1;
      final prevLineStart = text.lastIndexOf('\n', prevLineEnd - 1) + 1;
      final prevLine = text.substring(prevLineStart, prevLineEnd);
      if (!prevLine.trimLeft().startsWith('|')) break;
      tableStart = prevLineStart;
    }

    // 找到表格块结束
    int tableEnd = actualLineEnd;
    while (tableEnd < text.length) {
      final nextLineStart = tableEnd + 1;
      final nextLineEnd = text.indexOf('\n', nextLineStart);
      final nextLine = nextLineEnd >= 0
          ? text.substring(nextLineStart, nextLineEnd)
          : text.substring(nextLineStart);
      if (!nextLine.trimLeft().startsWith('|')) break;
      tableEnd = nextLineEnd >= 0 ? nextLineEnd : text.length;
    }

    // 提取表格所有行
    final tableText = tableEnd < text.length
        ? text.substring(tableStart, tableEnd)
        : text.substring(tableStart);
    final tableLines = tableText.split('\n');
    final buf = StringBuffer();
    for (int i = 0; i < tableLines.length; i++) {
      final line = tableLines[i].trimRight();
      if (line.trimLeft().startsWith('|')) {
        // 判断是否是分隔行（如 |---|---| 或 |:---:|:---:|）
        if (RegExp(r'^\|[\s\-:]*-[\s\-:]*\|').hasMatch(line.trimLeft())) {
          buf.writeln('${line} --- |');
        } else {
          buf.writeln('$line 内容 |');
        }
      } else {
        buf.writeln(line);
      }
    }

    final newTable = buf.toString();
    final end = tableEnd < text.length ? tableEnd + 1 : text.length;
    _doc.contentCtrl.value = TextEditingValue(
      text: text.replaceRange(
        tableStart,
        end > text.length ? text.length : end,
        newTable,
      ),
      selection: TextSelection.collapsed(offset: tableStart + newTable.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('已添加表格列');
  }

  void _formatDocument() {
    try {
      _doc.contentCtrl.text = MarkdownFormatter.formatDocument(
        _doc.contentCtrl.text,
      );
      _onContentChanged();
      if (mounted) _showToast('文档格式化完成');
    } catch (e) {
      if (mounted) _showToast('格式化出错: $e');
    }
  }

  Future<void> _pasteImageFromClipboard() async {
    try {
      // 1) 检查剪贴板是否为图片 URL
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) {
        final text = data!.text!.trim();
        if (text.startsWith('http') &&
            RegExp(
              r'\.(png|jpg|jpeg|gif|webp|svg)(\?.*)?$',
              caseSensitive: false,
            ).hasMatch(text)) {
          _insertText(imageService.markdownImage(text));
          _showToast('图片链接已插入');
          return;
        }
      }

      // 2) 尝试获取剪贴板图片字节（桌面平台支持）
      Uint8List? imgBytes;
      try {
        final imgData = await Clipboard.getData('image/png');
        if (imgData != null && imgData.text != null) {
          imgBytes = Uint8List.fromList(imgData.text!.codeUnits);
        }
      } catch (e) {
        debugPrint('Shell: clipboard image read failed: $e');
      }

      if (imgBytes != null &&
          imgBytes.isNotEmpty &&
          _editorRepo != null &&
          _workspaceFolder != null) {
        _editor.setEditorBusy(true);
        _editor.setEditorStatus('正在保存剪贴板图片...');
        try {
          // 自动压缩图片
          final compressed = await imageService.compressIfNeeded(
            imgBytes,
            settings,
          );

          // 生成文件名：时间戳.png
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = '$timestamp.png';

          // 保存到本地项目
          final relativePath = await imageService.saveImageLocally(
            compressed,
            projectDir: _workspaceFolder!,
            subDir: 'images',
            fileName: fileName,
          );

          // 插入相对路径
          _insertText(
            imageService.markdownImage('/$relativePath', alt: 'image'),
          );
          _showToast('图片已保存到本地: $relativePath');
        } catch (e) {
          _showToast('图片保存失败: $e');
        } finally {
          if (mounted) _editor.setEditorBusy(false);
        }
        return;
      } else if (imgBytes != null && imgBytes.isNotEmpty) {
        // 没有本地项目，仍使用图床上传
        _editor.setEditorBusy(true);
        _editor.setEditorStatus('正在上传剪贴板图片...');
        try {
          final url = await imageService.uploadToImageBed(imgBytes, settings);
          _insertText(imageService.markdownImage(url));
          _showToast('图片已粘贴并上传');
        } catch (e) {
          _showToast('图片上传失败: $e');
        } finally {
          if (mounted) _editor.setEditorBusy(false);
        }
        return;
      }

      // 3) 兜底：打开文件选择器选图片
      _showToast('剪贴板无图片，请选择图片文件');
      _insertImage();
    } catch (e) {
      _showToast('粘贴图片失败: $e');
    }
  }

  void _wrap(String l, String r, {String p = ''}) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = p.isEmpty ? '' : p;
      final ins = '$l$body$r';
      final s = sel.isValid ? sel.start : txt.length;
      _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, s, ins),
        selection: TextSelection.collapsed(offset: s + l.length + body.length),
      );
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    final sel2 = txt.substring(sel.start, sel.end);
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(sel.start, sel.end, '$l$sel2$r'),
      selection: TextSelection.collapsed(
        offset: sel.start + l.length + sel2.length,
      ),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final txt = _doc.contentCtrl.text;
    final s = _doc.contentCtrl.selection.isValid
        ? _doc.contentCtrl.selection.start
        : txt.length;
    final lineStart = txt.lastIndexOf('\n', s - 1) + 1;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: s + prefix.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertList(String marker) {
    final sel = _doc.contentCtrl.selection;
    if (sel.isValid && sel.start != sel.end) {
      final selected = _doc.contentCtrl.text.substring(sel.start, sel.end);
      final lines = selected
          .split('\n')
          .map((l) => l.isEmpty ? l : '$marker$l')
          .join('\n');
      final txt = _doc.contentCtrl.text;
      _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(sel.start, sel.end, lines),
        selection: TextSelection.collapsed(offset: sel.start + lines.length),
      );
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    _insertText('\n$marker');
  }

  void _wrapSelection(String prefix, String suffix) {
    _wrap(prefix, suffix);
  }

  void _prefixLine(String prefix) {
    final txt = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    final lineStart = sel.isValid
        ? txt.lastIndexOf('\n', sel.start - 1) + 1
        : 0;
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: lineStart + prefix.length),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertLink() {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? txt.substring(sel.start, sel.end)
        : '链接文本';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    final md = '[$selected](url)';
    _doc.contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, md),
      selection: TextSelection(
        baseOffset: s + md.length - 4,
        extentOffset: s + md.length - 1,
      ),
    );
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }
}
