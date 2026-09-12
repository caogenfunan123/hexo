// 发布 / 保存 / 定时发布扩展（desktop_shell.dart 的 part，与主类同 library，可访问私有成员）。
// 由 desktop_shell.dart 拆分而来（修复1），方法体保持零变更；
// setState 经宿主 _applyState 包装调用。
part of '../desktop_shell.dart';

extension DesktopShellPublishExt on DesktopShellState {
  Article _collect({bool draft = true}) {
    final cover = _doc.coverCtrl.text.trim();
    final title = _doc.titleCtrl.text.trim();
    return _doc.currentArticle.copyWith(
      title: title.isEmpty ? '未命名' : title,
      content: _doc.contentCtrl.text,
      tags: _doc.tagsCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      categories: _doc.categoriesCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      cover: cover.isEmpty ? null : cover,
      updatedAt: DateTime.now(),
      isDraft: draft,
      published: draft ? false : true,
      repoId: _editorRepo?.id ?? _doc.currentArticle.repoId,
      articleType: _doc.articleType,
      templateId: _doc.selectedTemplateId,
    );
  }

  String _generateSlug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'untitled' : slug;
  }

  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0)
      drafts[i] = a;
    else
      drafts.insert(0, a);
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await storage.saveDrafts(drafts);
    await storage.exportDraftMarkdown(a);
    if (mounted) _applyState(() {});
  }

  Future<void> _saveLocal() async {
    if (_savingLocal) return;
    _savingLocal = true;
    try {
      final a = _collect(draft: true);
      _doc.setCurrentArticle(a);
      _editor.setEditorStatus('本地已保存');
      await _saveDraft(a);
      if (siteManager.isDynamicSite) {
        final adapter = siteManager.currentAdapter;
        if (adapter != null) {
          final post = BlogPost(
            title: a.title,
            contentMd: a.content,
            status: 'draft',
            slug: _generateSlug(a.title),
            tags: a.tags,
            categories: a.categories,
            date: DateTime.now(),
            siteId: adapter.config.id,
            siteType: adapter.config.type,
          );
          await cmsDraftService.saveDraft(post);
        }
      }
      _lastSavedContent = a.content;
      _lastSavedTitle = a.title;
      _lastSavedContentMap[a.id] = a.content;
      _lastSavedTitleMap[a.id] = a.title;
      _doc.markSaved();
      // 创建版本快照
      versionSnapshotService.createSnapshot(a.id, a.title, a.content);
      logService.add('保存草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
      if (mounted) _showToast('草稿已保存到本地');
    } finally {
      _savingLocal = false;
    }
  }

  Future<void> _saveMdBackup() async {
    try {
      final a = _collect(draft: false);
      final rootDir = await storage.root;
      final dir = Directory('${rootDir.path}/hexo_backups');
      if (!await dir.exists()) await dir.create(recursive: true);
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(a.toMarkdownWithFrontMatter());
      if (mounted) _showToast('MD 备份已保存到 hexo_backups/$fileName');
    } catch (e) {
      if (mounted) _showToast('MD 备份保存失败: $e');
    }
  }

  Future<void> _handlePublish() async {
    // 先检查同步冲突
    if (siteManager.isDynamicSite) {
      final canProceed = await _checkAndResolveConflicts();
      if (!canProceed) {
        _showToast('存在同步冲突，请先解决冲突后再发布');
        return;
      }
    }

    final publishTarget = siteManager.isDynamicSite
        ? siteManager.currentBlogType.displayName
        : (_resolvedRepo?.fullName ?? 'GitHub');
    final dynamicSiteCount = siteManager.dynamicSites.length;
    bool saveMdBackup = false;

    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text('确认发布', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '即将发布到: $publishTarget',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '标题: ${_doc.titleCtrl.text.isNotEmpty ? _doc.titleCtrl.text : "(无标题)"}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: saveMdBackup,
                onChanged: (v) =>
                    setDialogState(() => saveMdBackup = v ?? false),
                title: const Text(
                  '同时保存一份 MD 备份到本地目录',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  '备份到文档目录的 hexo_backups/ 文件夹',
                  style: TextStyle(fontSize: 11),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('取消'),
            ),
            if (siteManager.isDynamicSite && dynamicSiteCount > 1)
              TextButton.icon(
                icon: const Icon(Icons.cloud_done_outlined, size: 18),
                label: Text('发布到全部站点 ($dynamicSiteCount)'),
                onPressed: () => Navigator.pop(ctx, 2),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('确认发布'),
              onPressed: () => Navigator.pop(ctx, 1),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null || confirmed == 0 || !mounted) return;
    if (saveMdBackup) await _saveMdBackup();

    // 一键发布到全部动态 CMS 站点
    if (confirmed == 2) {
      await _publishToAllCmsSites();
      return;
    }

    // FrontMatter 校验
    final article = _collect(draft: false);
    final validation = frontMatterService.validate(article);
    if (!validation.isValid) {
      final missing = validation.missingFields.join('、');
      final warnings = validation.warnings.join('\n');
      final continuePublish = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('发布前校验', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '缺少必填字段: $missing',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  warnings,
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
              const SizedBox(height: 12),
              const Text('是否继续发布？', style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续发布'),
            ),
          ],
        ),
      );
      if (continuePublish != true || !mounted) return;
    }

    // 增强发布预检测：空内容、图片链接、语法检查
    final preCheckWarnings = <String>[];
    // 空内容检查
    if (article.content.trim().isEmpty) {
      preCheckWarnings.add('⚠ 文章内容为空');
    }
    // 图片链接检查
    final imgRegex = RegExp(r'!\[.*?\]\((https?://[^\s)]+)\)');
    final imgMatches = imgRegex.allMatches(article.content).toList();
    if (imgMatches.isNotEmpty) {
      preCheckWarnings.add('ℹ 文章包含 ${imgMatches.length} 个外部图片链接，建议检查图片是否可访问');
    }
    // 空标题检查
    if (article.title.isEmpty || article.title == '未命名') {
      preCheckWarnings.add('⚠ 文章标题为空或未命名');
    }
    // 内容过短检查
    if (article.content.trim().length < 20 &&
        article.content.trim().isNotEmpty) {
      preCheckWarnings.add('⚠ 文章内容过短（<20字符），建议补充内容');
    }

    if (preCheckWarnings.isNotEmpty) {
      final continuePublish2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.fact_check_outlined, color: Colors.blue, size: 22),
              SizedBox(width: 8),
              Text('发布预检测', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...preCheckWarnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(w, style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('是否继续发布？', style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续发布'),
            ),
          ],
        ),
      );
      if (continuePublish2 != true || !mounted) return;
    }

    if (siteManager.isDynamicSite) {
      await _publishToCms();
      return;
    }

    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      _showToast('请先配置仓库与 Token');
      return;
    }
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在发布...');
    try {
      final a = _collect(draft: false);
      final pub = await github.publishArticleWithMirrors(
        repo,
        a,
        templates: templates,
      );
      // 发布期间用户可能继续编辑，此时不得用发布快照覆盖编辑器内容
      final userEdited = _doc.contentCtrl.text != a.content ||
          _doc.titleCtrl.text != a.title;
      if (userEdited) {
        _doc.updateCurrentArticleMeta(pub);
        _editor.setEditorStatus('已发布');
      } else {
        _doc.setCurrentArticle(pub);
        _editor.setEditorStatus('已发布');
        _doc.markSaved();
      }
      _lastSavedContent = pub.content;
      _lastSavedTitle = pub.title;
      _lastSavedContentMap[pub.id] = pub.content;
      _lastSavedTitleMap[pub.id] = pub.title;
      // 发布期间若继续编辑，落盘当前内容而非发布旧快照，避免覆盖用户新改动
      await _saveDraft(
        userEdited
            ? _collect(draft: false)
            : pub.copyWith(isDraft: false, published: true),
      );
      await _refreshRemote();
      // 触发全部部署钩子（Cloudflare / Vercel / Netlify 等）
      if (settings.deployHooks.isNotEmpty) {
        final ok = await GitHubService.triggerDeployHooks(settings.deployHooks);
        logService.add(
          '部署钩子',
          ok == settings.deployHooks.length
              ? '已触发 ${ok} 个重新部署'
              : '部署钩子部分失败（${ok}/${settings.deployHooks.length}）',
          success: ok == settings.deployHooks.length,
        );
      }
      logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
      if (mounted) _showToast('已发布到 ${repo.fullName}');
    } catch (e) {
      _editor.setEditorStatus('发布失败');
      logService.add('发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  Future<void> _publishToCms() async {
    final adapter = siteManager.currentAdapter;
    if (adapter == null) {
      _showToast('当前站点未配置动态 CMS 适配器，请先添加 CMS 站点');
      return;
    }
    final a = _collect(draft: false);
    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在发布到 ${adapter.config.type.displayName}...');
    try {
      final remoteId = _doc.currentArticle.remoteSha != null
          ? int.tryParse(_doc.currentArticle.remoteSha!)
          : null;
      final post = BlogPost(
        id: remoteId,
        title: a.title,
        contentMd: a.content,
        status: 'publish',
        slug: _generateSlug(a.title),
        tags: a.tags,
        categories: a.categories,
        date: DateTime.now(),
        siteId: adapter.config.id,
        siteType: adapter.config.type,
      );
      final result = remoteId != null
          ? await adapter.updatePost(post)
          : await adapter.createPost(post);
      final pub = a.copyWith(
        isDraft: false,
        published: true,
        remotePath: result.link,
        remoteSha: result.id?.toString(),
      );
      // 发布期间用户可能继续编辑，此时不得用发布快照覆盖编辑器内容
      final userEdited = _doc.contentCtrl.text != a.content ||
          _doc.titleCtrl.text != a.title;
      if (userEdited) {
        _doc.updateCurrentArticleMeta(pub);
      } else {
        _doc.setCurrentArticle(pub);
        _doc.markSaved();
      }
      _editor.setEditorStatus('已发布到 ${adapter.config.type.displayName}');
      _lastSavedContent = a.content;
      _lastSavedTitle = a.title;
      _lastSavedContentMap[a.id] = a.content;
      _lastSavedTitleMap[a.id] = a.title;
      // 发布期间若继续编辑，落盘当前内容而非发布旧快照，避免覆盖用户新改动
      await _saveDraft(userEdited ? _collect(draft: false) : pub);
      await cmsDraftService.saveDraft(result);
      if (result.id != null) {
        syncService.setMapping(
          SyncMapping(
            localArticleId: pub.id,
            remotePostId: result.id!,
            siteId: adapter.config.id,
            lastSyncAt: DateTime.now(),
            localModifiedAt: pub.updatedAt,
            remoteModifiedAt: result.modifiedDate,
          ),
        );
      }
      logService.add(
        'CMS发布成功',
        '已发布到 ${adapter.config.type.displayName}: ${result.title}',
      );
      if (mounted)
        _showToast(
          '已发布到 ${adapter.config.type.displayName}: ${result.link ?? result.title}',
        );
    } catch (e) {
      _editor.setEditorStatus('发布失败');
      logService.add('CMS发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) _editor.setEditorBusy(false);
    }
  }

  Future<void> _publishToAllCmsSites() async {
    final adapters = _allCmsAdapters;
    if (adapters.isEmpty) {
      _showToast('没有已保存的动态 CMS 站点，请先在「设置」中添加');
      return;
    }

    final a = _collect(draft: false);
    if (a.title.trim().isEmpty) {
      _showToast('请先填写文章标题');
      return;
    }
    final slug = _generateSlug(a.title);

    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在发布到 ${adapters.length} 个站点...');

    int success = 0;
    final details = <String, String>{};
    try {
      for (final adapter in adapters) {
        final siteName = adapter.config.name;
        _editor.setEditorStatus('正在发布到 $siteName...');
        try {
          // 该站点已有远程映射 → 更新；否则新建
          final existing = syncService.findByLocalId(adapter.config.id, a.id);
          final post = BlogPost(
            id: existing?.remotePostId,
            title: a.title,
            contentMd: a.content,
            status: 'publish',
            slug: slug,
            tags: a.tags,
            categories: a.categories,
            date: DateTime.now(),
            siteId: adapter.config.id,
            siteType: adapter.config.type,
          );
          final result = existing != null
              ? await adapter.updatePost(post)
              : await adapter.createPost(post);
          success++;
          details[siteName] = '成功 (ID: ${result.id})';
          await cmsDraftService.saveDraft(result);
          if (result.id != null) {
            syncService.setMapping(
              SyncMapping(
                localArticleId: a.id,
                remotePostId: result.id!,
                siteId: adapter.config.id,
                lastSyncAt: DateTime.now(),
                localModifiedAt: a.updatedAt,
                remoteModifiedAt: result.modifiedDate,
              ),
            );
          }
        } catch (e) {
          final msg = e is BlogRepositoryException ? e.message : '$e';
          details[siteName] = '失败: $msg';
          logService.add('多站点发布失败', '$siteName: $msg', success: false);
        }
      }
    } finally {
      if (mounted) {
        _editor.setEditorBusy(false);
        _editor.setEditorStatus('多站点发布完成: 成功 $success/${adapters.length}');
      }
    }

    logService.add('多站点发布', '《${a.title}》成功 $success/${adapters.length} 个站点');
    if (mounted) {
      _showToast('多站点发布完成: 成功 $success/${adapters.length} 个站点');
      final lines = details.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('发布结果 ($success/${adapters.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(lines, style: const TextStyle(fontSize: 13)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  void _repairPublishPaths() {
    final siteUrl = activeRepo?.siteUrl ?? '';
    if (siteUrl.isEmpty) {
      if (mounted) _showToast('请先配置站点 URL');
      return;
    }

    final baseUrl = siteUrl.endsWith('/')
        ? siteUrl.substring(0, siteUrl.length - 1)
        : siteUrl;
    final text = _doc.contentCtrl.text;
    int fixedCount = 0;

    // 匹配图片语法
    final imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    final replaced = text.replaceAllMapped(imagePattern, (m) {
      final alt = m.group(1) ?? '';
      var url = m.group(2) ?? '';

      // 如果已经是绝对 URL，跳过
      if (url.startsWith('http://') ||
          url.startsWith('https://') ||
          url.startsWith('//')) {
        return m.group(0)!;
      }

      // 处理相对路径
      var cleaned = url
          .replaceAll(RegExp(r'^\./'), '')
          .replaceAll(RegExp(r'^(\.\./)+'), '');
      if (!cleaned.startsWith('/')) cleaned = '/$cleaned';
      fixedCount++;
      return '![$alt]($baseUrl$cleaned)';
    });

    if (fixedCount > 0) {
      _doc.contentCtrl.text = replaced;
      _onContentChanged();
      if (mounted) _showToast('已修复 $fixedCount 个图片路径');
    } else {
      if (mounted) _showToast('未发现需要修复的本地路径');
    }
  }

  Future<void> _batchPublish(List<String> articleIds) async {
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      if (mounted) _showToast('请先配置仓库与 Token');
      return;
    }

    _editor.setEditorBusy(true);
    _editor.setEditorStatus('正在批量发布...');
    int published = 0;
    int failed = 0;

    try {
      for (final id in articleIds) {
        final article = drafts.firstWhere(
          (a) => a.id == id,
          orElse: () => Article(
            id: '',
            title: '',
            content: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            isDraft: true,
          ),
        );
        if (article.id.isEmpty) continue;

        final pubArticle = article.copyWith(isDraft: false, published: true);
        try {
          final pub = await github.publishArticleWithMirrors(
            repo,
            pubArticle,
            templates: templates,
          );
          final idx = drafts.indexWhere((a) => a.id == id);
          if (idx >= 0)
            drafts[idx] = pub.copyWith(isDraft: false, published: true);
          published++;
        } catch (e) {
          debugPrint('Shell: site config load failed: $e');
        }
      }
      await storage.saveDrafts(drafts);
      // 批量发布后触发全部部署钩子
      if (published > 0 && settings.deployHooks.isNotEmpty) {
        final ok = await GitHubService.triggerDeployHooks(settings.deployHooks);
        logService.add(
          '部署钩子',
          ok == settings.deployHooks.length
              ? '批量发布后已触发 ${ok} 个重新部署'
              : '部署钩子部分失败（${ok}/${settings.deployHooks.length}）',
          success: ok == settings.deployHooks.length,
        );
      }
      if (mounted) {
        _editor.setEditorBusy(false);
        _editor.setEditorStatus(null);
        _showToast('批量发布完成: $published 成功, $failed 失败');
      }
    } catch (e) {
      if (mounted) {
        _editor.setEditorBusy(false);
        _editor.setEditorStatus(null);
        _showToast('批量发布出错: $e');
      }
    }
  }

  void _showPublishChangeLog(String remoteContentParam) async {
    final localContent = _doc.contentCtrl.text;
    var remoteContent = remoteContentParam;

    // 如果未提供远程内容，尝试从当前发布目标获取
    if (remoteContent.isEmpty && siteManager.isDynamicSite) {
      try {
        final adapter = siteManager.currentAdapter;
        if (adapter != null) {
          final mapping = syncService.findByLocalId(
            siteManager.currentAdapter?.config.id ?? '',
            _doc.currentArticle.id,
          );
          if (mapping != null) {
            final remotePost = await adapter.getPostById(mapping.remotePostId);
            if (remotePost != null) {
              remoteContent = remotePost.contentMd;
            }
          }
        }
      } catch (e) {
        debugPrint('Shell: publish changelog failed: $e');
      }
    }

    if (remoteContent.isEmpty) {
      _showToast('未找到已发布的线上版本，无法对比变更');
      return;
    }

    if (remoteContent == localContent) {
      _showToast('内容无变化，无需发布');
      return;
    }
    final diffLines = _computeDiff(remoteContent, localContent);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.change_circle_outlined, size: 22),
            SizedBox(width: 8),
            Text('发布变更日志', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 800,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('新增内容', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('删除内容', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  Text(
                    '共 ${diffLines.where((l) => l.type != _DiffType.equal).length} 处变更',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: diffLines.length,
                  itemBuilder: (_, i) {
                    final line = diffLines[i];
                    Color bgColor;
                    Color textColor;
                    final prefix = line.type == _DiffType.added
                        ? '+'
                        : line.type == _DiffType.removed
                        ? '-'
                        : ' ';
                    switch (line.type) {
                      case _DiffType.added:
                        bgColor = Colors.green.withOpacity(0.08);
                        textColor = Colors.green.shade700;
                        break;
                      case _DiffType.removed:
                        bgColor = Colors.red.withOpacity(0.08);
                        textColor = Colors.red.shade600;
                        break;
                      default:
                        bgColor = Colors.transparent;
                        textColor = Colors.grey.shade500;
                    }
                    return Container(
                      color: bgColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prefix,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            line.text.isEmpty ? ' ' : line.text,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
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
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: const Text('确认发布'),
            onPressed: () {
              Navigator.pop(ctx);
              _executePublish();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _schedulePublish() async {
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();

    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.schedule_send, size: 22),
                SizedBox(width: 8),
                Text('定时发布', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '设置发布时间，到时自动发布到当前站点',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          decoration: const InputDecoration(
                            labelText: '日期',
                            hintText: '2026-08-03',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: timeCtrl,
                          decoration: const InputDecoration(
                            labelText: '时间',
                            hintText: '20:00',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_scheduledPublishTime != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已有定时发布: ${_scheduledPublishTime!.toString().substring(0, 16)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _scheduledPublishTimer?.cancel();
                              _scheduledPublishTimer = null;
                              _scheduledPublishTime = null;
                              setDialogState(() {});
                              _showToast('已取消定时发布');
                            },
                            child: const Text(
                              '取消',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.schedule, size: 16),
                label: const Text('设置定时发布'),
                onPressed: () {
                  final dateStr = dateCtrl.text.trim();
                  final timeStr = timeCtrl.text.trim();
                  if (dateStr.isEmpty || timeStr.isEmpty) {
                    _showToast('请填写日期和时间');
                    return;
                  }
                  final scheduledTime = DateTime.tryParse(
                    '${dateStr}T${timeStr}:00',
                  );
                  if (scheduledTime == null) {
                    _showToast('日期时间格式无效');
                    return;
                  }
                  if (scheduledTime.isBefore(DateTime.now())) {
                    _showToast('发布时间不能早于当前时间');
                    return;
                  }
                  final delay = scheduledTime.difference(DateTime.now());
                  _scheduledPublishTimer?.cancel();
                  _scheduledPublishTimer = Timer(delay, () {
                    _scheduledPublishTime = null;
                    _scheduledPublishTimer = null;
                    if (mounted) {
                      _showToast('定时发布开始执行...');
                      _executePublish();
                    }
                  });
                  _scheduledPublishTime = scheduledTime;
                  Navigator.pop(ctx);
                  _showToast(
                    '已设置定时发布: ${scheduledTime.toString().substring(0, 16)}',
                  );
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      dateCtrl.dispose();
      timeCtrl.dispose();
    }
  }

  Future<void> _executePublish() async {
    if (siteManager.isDynamicSite) {
      await _publishToCms();
    } else {
      final repo = _resolvedRepo;
      if (repo == null || repo.token.isEmpty) {
        _showToast('请先配置仓库与 Token');
        return;
      }
      _editor.setEditorBusy(true);
      _editor.setEditorStatus('正在发布...');
      try {
        final a = _collect(draft: false);
        final pub = await github.upsertArticle(repo, a, templates: templates);
        // 发布期间用户可能继续编辑，此时不得用发布快照覆盖编辑器内容
        final userEdited = _doc.contentCtrl.text != a.content ||
            _doc.titleCtrl.text != a.title;
        if (userEdited) {
          _doc.updateCurrentArticleMeta(pub);
        } else {
          _doc.setCurrentArticle(pub);
          _doc.markSaved();
        }
        _editor.setEditorStatus('已发布');
        _lastSavedContent = pub.content;
        _lastSavedTitle = pub.title;
        _lastSavedContentMap[pub.id] = pub.content;
        _lastSavedTitleMap[pub.id] = pub.title;
        // 发布期间若继续编辑，落盘当前内容而非发布旧快照，避免覆盖用户新改动
        await _saveDraft(
          userEdited
              ? _collect(draft: false)
              : pub.copyWith(isDraft: false, published: true),
        );
        await _refreshRemote();
        logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
        if (mounted) _showToast('已发布到 ${repo.fullName}');
      } catch (e) {
        _editor.setEditorStatus('发布失败');
        logService.add('发布失败', '$e', success: false);
        if (mounted) _showToast('发布失败: $e');
      } finally {
        if (mounted) _editor.setEditorBusy(false);
      }
    }
  }

  Future<void> _saveAsToLocal() async {
    try {
      final title = _doc.titleCtrl.text.isNotEmpty
          ? _doc.titleCtrl.text
          : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '另存为 Markdown 文件',
        fileName: '$safeTitle.md',
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (result == null) return;
      final file = File(result);
      final a = _collect(draft: true);
      await file.writeAsString(a.toMarkdownWithFrontMatter());
      _addRecentFile(result, safeTitle);
      if (mounted) _showToast('已保存到: $result');
    } catch (e) {
      if (mounted) _showToast('保存失败: $e');
    }
  }
}
