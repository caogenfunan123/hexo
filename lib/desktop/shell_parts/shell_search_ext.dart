// 查找替换 / 全局搜索扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellSearchExt on DesktopShellState {
  Future<void> _showFindReplace() async {
    final findCtrl = TextEditingController();
    final replaceCtrl = TextEditingController();
    bool caseSensitive = false;
    bool useRegex = false;

    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('查找和替换'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: findCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '查找',
                        hintText: '输入要查找的文本...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: replaceCtrl,
                      decoration: const InputDecoration(
                        labelText: '替换',
                        hintText: '输入替换文本...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: caseSensitive,
                          onChanged: (v) =>
                              setDialogState(() => caseSensitive = v ?? false),
                        ),
                        GestureDetector(
                          onTap: () => setDialogState(
                            () => caseSensitive = !caseSensitive,
                          ),
                          child: const Text(
                            '区分大小写',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Checkbox(
                          value: useRegex,
                          onChanged: (v) =>
                              setDialogState(() => useRegex = v ?? false),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setDialogState(() => useRegex = !useRegex),
                          child: const Text(
                            '正则表达式',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final findText = findCtrl.text;
                    if (findText.isEmpty) return;
                    _findNext(
                      findText,
                      caseSensitive: caseSensitive,
                      useRegex: useRegex,
                    );
                  },
                  child: const Text('查找下一个'),
                ),
                TextButton(
                  onPressed: () {
                    final findText = findCtrl.text;
                    final replaceText = replaceCtrl.text;
                    if (findText.isEmpty) return;
                    _replaceCurrent(
                      findText,
                      replaceText,
                      caseSensitive: caseSensitive,
                      useRegex: useRegex,
                    );
                  },
                  child: const Text('替换'),
                ),
                FilledButton(
                  onPressed: () {
                    final findText = findCtrl.text;
                    final replaceText = replaceCtrl.text;
                    if (findText.isEmpty) return;
                    final count = _replaceAll(
                      findText,
                      replaceText,
                      caseSensitive: caseSensitive,
                      useRegex: useRegex,
                    );
                    if (mounted) _showToast('已替换 $count 处');
                  },
                  child: const Text('全部替换'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
      );
    } finally {
      findCtrl.dispose();
      replaceCtrl.dispose();
    }
  }

  int _findNext(
    String findText, {
    bool caseSensitive = false,
    bool useRegex = false,
  }) {
    final text = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    int startOffset = sel.isValid ? sel.end : 0;

    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(
          findText,
          caseSensitive: caseSensitive,
          multiLine: true,
        );
      } else {
        pattern = RegExp(
          RegExp.escape(findText),
          caseSensitive: caseSensitive,
        );
      }

      Match? match;
      final matches = pattern.allMatches(text);
      for (final m in matches) {
        if (m.start >= (startOffset > 0 ? startOffset : 0)) {
          match = m;
          break;
        }
      }
      if (match != null) {
        _doc.contentCtrl.selection = TextSelection(
          baseOffset: match.start,
          extentOffset: match.end,
        );
        _doc.contentFocus.requestFocus();
        if (mounted) {
          _doc.contentCtrl.value = _doc.contentCtrl.value.copyWith(
            selection: TextSelection(
              baseOffset: match.start,
              extentOffset: match.end,
            ),
          );
        }
        return match.start;
      } else {
        // 从头开始搜索
        final match2 = pattern.firstMatch(text);
        if (match2 != null) {
          _doc.contentCtrl.selection = TextSelection(
            baseOffset: match2.start,
            extentOffset: match2.end,
          );
          _doc.contentFocus.requestFocus();
          if (mounted) {
            _doc.contentCtrl.value = _doc.contentCtrl.value.copyWith(
              selection: TextSelection(
                baseOffset: match2.start,
                extentOffset: match2.end,
              ),
            );
          }
          return match2.start;
        }
        if (mounted) _showToast('未找到匹配项');
      }
    } catch (e) {
      if (mounted) _showToast('搜索出错: $e');
    }
    return -1;
  }

  void _replaceCurrent(
    String findText,
    String replaceText, {
    bool caseSensitive = false,
    bool useRegex = false,
  }) {
    final text = _doc.contentCtrl.text;
    final sel = _doc.contentCtrl.selection;
    if (!sel.isValid || sel.start == sel.end) {
      _findNext(findText, caseSensitive: caseSensitive, useRegex: useRegex);
      return;
    }

    final selected = text.substring(sel.start, sel.end);
    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(findText, caseSensitive: caseSensitive);
      } else {
        pattern = RegExp(
          RegExp.escape(findText),
          caseSensitive: caseSensitive,
        );
      }

      if (pattern.hasMatch(selected)) {
        final replaced = selected.replaceAll(pattern, replaceText);
        _doc.contentCtrl.value = TextEditingValue(
          text: text.replaceRange(sel.start, sel.end, replaced),
          selection: TextSelection.collapsed(
            offset: sel.start + replaced.length,
          ),
        );
        _doc.contentFocus.requestFocus();
        _onContentChanged();
      } else {
        _findNext(findText, caseSensitive: caseSensitive, useRegex: useRegex);
      }
    } catch (e) {
      if (mounted) _showToast('替换出错: $e');
    }
  }

  int _replaceAll(
    String findText,
    String replaceText, {
    bool caseSensitive = false,
    bool useRegex = false,
  }) {
    final text = _doc.contentCtrl.text;
    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(
          findText,
          caseSensitive: caseSensitive,
          multiLine: true,
        );
      } else {
        pattern = RegExp(
          RegExp.escape(findText),
          caseSensitive: caseSensitive,
        );
      }

      int count = 0;
      final replaced = text.replaceAllMapped(pattern, (m) {
        count++;
        return replaceText;
      });
      _doc.contentCtrl.text = replaced;
      _doc.contentCtrl.selection = TextSelection.collapsed(offset: 0);
      _onContentChanged();
      return count;
    } catch (e) {
      if (mounted) _showToast('替换出错: $e');
      return 0;
    }
  }

  Future<void> _openGlobalSearch() async {
    final searchCtrl = TextEditingController();
    String query = '';
    String filterStatus = 'all'; // all, draft, published
    List<
      ({
        String articleId,
        String title,
        String snippet,
        String matchLine,
        bool isDraft,
        DateTime createdAt,
      })
    >
    results = [];

    void doSearch() {
      final q = query.toLowerCase();
      if (q.length < 2) {
        results = [];
        return;
      }
      results = [];
      for (final draft in drafts) {
        // 状态筛选
        if (filterStatus == 'draft' && draft.published) continue;
        if (filterStatus == 'published' && !draft.published) continue;

        final titleMatch = draft.title.toLowerCase().contains(q);
        final contentIdx = draft.content.toLowerCase().indexOf(q);
        if (titleMatch || contentIdx >= 0) {
          String snippet = '';
          String matchLine = '';
          if (contentIdx >= 0) {
            final start = contentIdx > 50 ? contentIdx - 50 : 0;
            final end = (contentIdx + q.length + 100) < draft.content.length
                ? contentIdx + q.length + 100
                : draft.content.length;
            snippet = draft.content.substring(start, end);
            matchLine = '...${snippet.replaceAll('\n', ' ')}...';
          }
          results.add((
            articleId: draft.id,
            title: draft.title.isEmpty ? '(无标题)' : draft.title,
            snippet: snippet,
            matchLine: matchLine,
            isDraft: !draft.published,
            createdAt: draft.createdAt,
          ));
        }
      }
    }

    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.manage_search, size: 22),
                SizedBox(width: 8),
                Text('全局搜索', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 620,
              height: 480,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '搜索文章标题或正文...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      setDialogState(() {
                                        query = '';
                                        results = [];
                                      });
                                    },
                                  )
                                : null,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setDialogState(() {
                              query = v;
                              doSearch();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 状态筛选器
                      DropdownButton<String>(
                        value: filterStatus,
                        isDense: true,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('全部', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('草稿', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 'published',
                            child: Text('已发布', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                        onChanged: (v) {
                          setDialogState(() {
                            filterStatus = v ?? 'all';
                            doSearch();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (results.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${results.length} 个结果',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (query.length < 2 && query.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '请输入至少2个字符进行搜索',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else if (query.isNotEmpty && results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '未找到匹配结果',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final r = results[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              r.isDraft
                                  ? Icons.drafts_outlined
                                  : Icons.article_outlined,
                              size: 18,
                              color: r.isDraft ? Colors.orange : Colors.green,
                            ),
                            title: Text(
                              r.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: r.matchLine.isNotEmpty
                                ? Text(
                                    r.matchLine,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            trailing: Text(
                              r.isDraft ? '草稿' : '已发布',
                              style: TextStyle(
                                fontSize: 10,
                                color: r.isDraft ? Colors.orange : Colors.green,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              final article = drafts.firstWhere(
                                (a) => a.id == r.articleId,
                                orElse: () => _doc.currentArticle,
                              );
                              _openExistingArticle(article);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } finally {
      searchCtrl.dispose();
    }
  }
}
