import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class _UploadFile {
  final String name;
  final String path;
  final int size;
  final String relPath;
  const _UploadFile({
    required this.name,
    required this.path,
    required this.size,
    required this.relPath,
  });
}

enum _FileStatus { pending, uploading, success, failed }

/// 上传方式：
/// - [auto]：自动依次尝试 Git Data 批量 → Contents 逐文件 → git CLI，全部失败才报错
/// - [gitdata]：仅 Git Data API 批量提交（一次 commit 上传全部文件）
/// - [contents]：仅 Contents API 逐文件提交（兼容性最好）
/// - [gitcli]：仅 git CLI（桌面端本地 clone + commit + push）
enum _UploadMethod { auto, gitdata, contents, gitcli }

extension _UploadMethodX on _UploadMethod {
  String get label {
    switch (this) {
      case _UploadMethod.auto:
        return '自动（推荐）';
      case _UploadMethod.gitdata:
        return 'Git Data 批量';
      case _UploadMethod.contents:
        return 'Contents 逐文件';
      case _UploadMethod.gitcli:
        return 'git CLI';
    }
  }
}

class _UploadEntry {
  final _UploadFile file;
  _FileStatus status;
  String message;
  _UploadEntry(this.file)
      : status = _FileStatus.pending,
        message = '';
}

/// 一个待上传文件：仓库相对路径 + 内容 + 对应条目
typedef _BatchFile = ({String path, List<int> bytes, _UploadEntry entry});

/// 批量上传页：填写仓库地址 + 令牌，选择文件/文件夹后一键上传到 GitHub。
///
/// 支持三种仓库地址格式：
/// - {@code https://github.com/owner/repo}（或 .git 结尾）
/// - {@code owner/repo}
/// 上传基于 GitHub Contents API（PUT /contents/{path}，base64 编码，
/// 文件已存在时自动带 sha 覆盖），逐文件推进并展示进度与状态。
class FolderUploadScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final GitHubService github;
  final RepoConfig? activeRepo;

  const FolderUploadScreen({
    super.key,
    required this.repos,
    required this.github,
    required this.activeRepo,
  });

  @override
  State<FolderUploadScreen> createState() => _FolderUploadScreenState();
}

class _FolderUploadScreenState extends State<FolderUploadScreen> {
  final _repoUrlCtrl = TextEditingController();
  final _branchCtrl = TextEditingController(text: 'main');
  final _tokenCtrl = TextEditingController();
  final _targetPathCtrl = TextEditingController(text: 'source/_posts');
  final _commitMsgCtrl = TextEditingController(text: 'upload: batch files');
  List<_UploadEntry> _entries = [];
  bool _busy = false;
  bool _tokenVerified = false;
  bool _tokenChecking = false;
  bool _showToken = false;
  _UploadMethod _method = _UploadMethod.auto;
  String _status = '';
  int _uploaded = 0;
  int _failed = 0;

  @override
  void initState() {
    super.initState();
    // 优先用当前激活仓库预填地址与令牌，省去手动输入
    final active = widget.activeRepo ??
        (widget.repos.isNotEmpty ? widget.repos.first : null);
    if (active != null && active.provider == GitProviderType.github) {
      _repoUrlCtrl.text = active.fullName;
      _branchCtrl.text = active.branch;
      if (active.token.isNotEmpty) _tokenCtrl.text = active.token;
    }
  }

  @override
  void dispose() {
    _repoUrlCtrl.dispose();
    _branchCtrl.dispose();
    _tokenCtrl.dispose();
    _targetPathCtrl.dispose();
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  // ── 仓库地址解析 ──

  /// 从仓库地址解析 owner/repo，支持 URL 或 owner/repo 格式。
  /// 返回 null 表示格式不合法。
  (String owner, String repo)? _parseRepo() {
    var s = _repoUrlCtrl.text.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'\.git$'), '');
    if (s.startsWith('https://') || s.startsWith('http://')) {
      try {
        final uri = Uri.parse(s);
        final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
        if (segs.length >= 2) return (segs[segs.length - 2], segs.last);
      } catch (_) {
        return null;
      }
    }
    final parts = s.split('/');
    if (parts.length >= 2) return (parts[parts.length - 2], parts.last);
    return null;
  }

  // ── 令牌校验 ──

  Future<void> _verifyToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      _showToast('请先填写 GitHub 令牌');
      return;
    }
    setState(() {
      _tokenChecking = true;
      _tokenVerified = false;
    });
    final ok = await widget.github.verifyToken(token);
    if (!mounted) return;
    setState(() {
      _tokenChecking = false;
      _tokenVerified = ok;
    });
    _showToast(ok ? '令牌有效' : '令牌无效，请检查后重试');
  }

  // ── 文件选择 ──

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'md', 'txt', 'html', 'json', 'yaml', 'yml', 'xml', 'csv',
        'js', 'css', 'jpg', 'jpeg', 'png', 'gif', 'svg', 'webp', 'pdf',
      ],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _entries = result.files
            .map((f) => _UploadEntry(_UploadFile(
                  name: f.name,
                  path: f.path ?? '',
                  size: f.size,
                  relPath: f.name,
                )))
            .toList();
        _uploaded = 0;
        _failed = 0;
        _status = '';
      });
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final dir = Directory(result);
      final files = <_UploadFile>[];
      void scan(Directory d) {
        for (final entity in d.listSync()) {
          if (entity is File) {
            final relPath = entity.path.substring(result.length + 1);
            files.add(_UploadFile(
              name: entity.path.split(Platform.pathSeparator).last,
              path: entity.path,
              size: entity.lengthSync(),
              relPath: relPath,
            ));
          }
        }
      }

      scan(dir);
      setState(() {
        _entries = files.map((f) => _UploadEntry(f)).toList();
        _uploaded = 0;
        _failed = 0;
        _status = '';
      });
    }
  }

  // ── 上传 ──

  Future<void> _uploadAll() async {
    final token = _tokenCtrl.text.trim();
    final parsed = _parseRepo();
    if (token.isEmpty) {
      _showToast('请填写 GitHub 令牌');
      return;
    }
    if (parsed == null) {
      _showToast('仓库地址格式不正确（如 owner/repo）');
      return;
    }
    final (owner, repo) = parsed;
    final branch = _branchCtrl.text.trim().isEmpty
        ? 'main'
        : _branchCtrl.text.trim();
    if (_entries.isEmpty) {
      _showToast('请先选择文件');
      return;
    }

    setState(() {
      _busy = true;
      _uploaded = 0;
      _failed = 0;
      _status = '正在上传...';
      for (final e in _entries) {
        e.status = _FileStatus.pending;
        e.message = '';
      }
    });

    final basePath = _targetPathCtrl.text.replaceAll(RegExp(r'/+$'), '');
    final msg = _commitMsgCtrl.text.trim();

    // 预读全部文件内容；读不到的立即标记失败
    final files = <_BatchFile>[];
    for (final entry in _entries) {
      try {
        if (entry.file.path.isEmpty) {
          entry.status = _FileStatus.failed;
          entry.message = '路径为空';
          _failed++;
          continue;
        }
        final bytes = await File(entry.file.path).readAsBytes();
        files.add((
          path: '$basePath/${entry.file.relPath}',
          bytes: bytes,
          entry: entry,
        ));
      } catch (e) {
        entry.status = _FileStatus.failed;
        entry.message = '读取失败: $e';
        _failed++;
      }
    }
    if (mounted) {
      setState(() {
        _status = '已加载 ${files.length} 个文件 · 失败 $_failed';
      });
    }

    // 按用户选择/自动策略执行
    switch (_method) {
      case _UploadMethod.contents:
        await _runContents(owner, repo, branch, msg, files);
      case _UploadMethod.gitdata:
        await _runGitData(token, owner, repo, branch, msg, files);
      case _UploadMethod.gitcli:
        await _runGitCli(token, owner, repo, branch, msg, files);
      case _UploadMethod.auto:
        await _runAuto(token, owner, repo, branch, msg, files);
    }

    if (mounted) {
      setState(() {
        _busy = false;
        _status = _failed == 0
            ? '全部上传完成：$_uploaded 成功'
            : '上传完成：$_uploaded 成功，$_failed 失败';
      });
    }
    _showToast(_status);
  }

  List<({String path, List<int> bytes})> _apiFiles(List<_BatchFile> files) =>
      files.map((f) => (path: f.path, bytes: f.bytes)).toList();

  /// 方法A：Contents API 逐文件提交
  Future<void> _runContents(
    String owner,
    String repo,
    String branch,
    String msg,
    List<_BatchFile> files,
  ) async {
    final token = _tokenCtrl.text.trim();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final entry = f.entry;
      if (entry.status == _FileStatus.success) continue;
      try {
        setState(() => entry.status = _FileStatus.uploading);
        await widget.github.uploadBinary(
          token: token,
          owner: owner,
          repo: repo,
          branch: branch,
          path: f.path,
          bytes: f.bytes,
          message: '$msg: ${entry.file.relPath}',
          provider: GitProviderType.github,
        );
        entry.status = _FileStatus.success;
        _uploaded++;
        if (_failed > 0) _failed--;
      } catch (e) {
        entry.status = _FileStatus.failed;
        entry.message = 'Contents 失败: $e';
        _failed++;
      }
      if (mounted) {
        setState(() {
          _status =
              'Contents 逐文件 ${i + 1}/${files.length} · 已成功 $_uploaded · 失败 $_failed';
        });
      }
    }
  }

  /// 方法B：Git Data API 批量提交（一次 commit 上传全部文件）
  Future<void> _runGitData(
    String token,
    String owner,
    String repo,
    String branch,
    String msg,
    List<_BatchFile> files,
  ) async {
    if (files.isEmpty) return;
    for (final f in files) {
      if (f.entry.status != _FileStatus.success) {
        f.entry.status = _FileStatus.uploading;
      }
    }
    try {
      await widget.github.uploadBatchViaGitData(
        token: token,
        owner: owner,
        repo: repo,
        branch: branch,
        files: _apiFiles(files),
        message: '$msg（Git Data 批量）',
      );
      for (final f in files) {
        if (f.entry.status != _FileStatus.success) {
          f.entry.status = _FileStatus.success;
          _uploaded++;
          if (_failed > 0) _failed--;
        }
      }
    } catch (e) {
      for (final f in files) {
        if (f.entry.status != _FileStatus.success) {
          f.entry.status = _FileStatus.failed;
          f.entry.message = 'Git Data 失败: $e';
          _failed++;
        }
      }
      rethrow;
    }
  }

  /// 方法C：git CLI（桌面端 clone + commit + push）
  Future<void> _runGitCli(
    String token,
    String owner,
    String repo,
    String branch,
    String msg,
    List<_BatchFile> files,
  ) async {
    if (files.isEmpty) return;
    try {
      await widget.github.uploadViaGitCli(
        token: token,
        owner: owner,
        repo: repo,
        branch: branch,
        files: _apiFiles(files),
        message: '$msg（git CLI）',
      );
      for (final f in files) {
        if (f.entry.status != _FileStatus.success) {
          f.entry.status = _FileStatus.success;
          _uploaded++;
          if (_failed > 0) _failed--;
        }
      }
    } catch (e) {
      for (final f in files) {
        if (f.entry.status != _FileStatus.success) {
          f.entry.status = _FileStatus.failed;
          f.entry.message = 'git CLI 失败: $e';
        }
      }
      rethrow;
    }
  }

  /// 自动模式：Git Data 批量 → Contents 逐文件 → git CLI，逐级回退
  Future<void> _runAuto(
    String token,
    String owner,
    String repo,
    String branch,
    String msg,
    List<_BatchFile> files,
  ) async {
    if (files.isEmpty) return;

    // 第一级：Git Data 批量（最快，一次 commit）
    await _tryLevel(() async {
      final pending = _pendingFiles(files);
      if (pending.isEmpty) return;
      await _runGitData(token, owner, repo, branch, msg, pending);
    });
    if (_pendingFiles(files).isEmpty) return;

    // 第二级：Contents 逐文件（兼容性最好）
    await _tryLevel(() async {
      final pending = _pendingFiles(files);
      if (pending.isEmpty) return;
      await _runContents(owner, repo, branch, msg, pending);
    });
    if (_pendingFiles(files).isEmpty) return;

    // 第三级：git CLI 兜底（桌面端，能处理分支不存在等情况）
    await _tryLevel(() async {
      final pending = _pendingFiles(files);
      if (pending.isEmpty) return;
      await _runGitCli(token, owner, repo, branch, msg, pending);
    });
  }

  /// 执行单个回退级别，失败吞掉异常交给下一级
  Future<void> _tryLevel(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  /// 尚未成功的文件（供回退计算）
  List<_BatchFile> _pendingFiles(List<_BatchFile> files) =>
      files.where((f) => f.entry.status != _FileStatus.success).toList();

  void _clearSelection() {
    setState(() {
      _entries = [];
      _status = '';
      _uploaded = 0;
      _failed = 0;
    });
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _entries.length;
    final done = _uploaded + _failed;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Column(
      children: [
        if (_busy) LinearProgressIndicator(value: progress, minHeight: 3),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 仓库地址
              _inputCard(
                controller: _repoUrlCtrl,
                icon: Icons.storage_outlined,
                label: '仓库地址（如 owner/repo 或 https://github.com/owner/repo）',
              ),
              const SizedBox(height: 10),
              // 分支 + 令牌
              Row(children: [
                Expanded(
                  child: _inputCard(
                    controller: _branchCtrl,
                    icon: Icons.call_split,
                    label: '分支',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _tokenInputCard(cs),
                ),
              ]),
              if (_tokenVerified)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('令牌已校验',
                        style: TextStyle(fontSize: 12, color: Colors.green[700])),
                  ]),
                ),
              const SizedBox(height: 10),
              // 目标路径
              _inputCard(
                controller: _targetPathCtrl,
                icon: Icons.folder_outlined,
                label: '目标路径（如 source/_posts）',
              ),
              const SizedBox(height: 10),
              // 提交信息
              _inputCard(
                controller: _commitMsgCtrl,
                icon: Icons.message_outlined,
                label: '提交信息',
              ),
              const SizedBox(height: 16),
              // 上传方式选择
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.alt_route, size: 18,
                          color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      const Text('上传方式',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const Spacer(),
                      Text(
                        _method == _UploadMethod.auto
                            ? '失败自动切换'
                            : '仅用该方式',
                        style: TextStyle(
                            fontSize: 11, color: cs.primary),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _UploadMethod.values
                          .map((m) => ChoiceChip(
                                label: Text(m.label),
                                selected: _method == m,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _method = m),
                                labelStyle: TextStyle(
                                    fontSize: 12,
                                    color: _method == m
                                        ? cs.primary
                                        : const Color(0xFF475569)),
                                selectedColor: cs.primary.withOpacity(0.12),
                                checkmarkColor: cs.primary,
                                side: BorderSide(
                                  color: _method == m
                                      ? cs.primary.withOpacity(0.5)
                                      : Colors.black.withOpacity(0.08),
                                ),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ))
                          .toList(),
                    ),
                    if (_method == _UploadMethod.auto)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '顺序：Git Data 批量 → Contents 逐文件 → git CLI（桌面端）',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 选择按钮
              Row(children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.attach_file,
                    label: '选择文件',
                    color: cs.primary,
                    onTap: _busy ? null : _pickFiles,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    icon: Icons.folder_open,
                    label: '选择文件夹',
                    color: const Color(0xFF8B5CF6),
                    onTap: _busy ? null : _pickFolder,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // 已选文件列表（含上传状态）
              if (_entries.isNotEmpty)
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: Row(children: [
                          const Icon(Icons.list_alt, size: 18,
                              color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text(
                            '已选 ${_entries.length} 个文件',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: _clearSelection,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 18,
                                  color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ]),
                      ),
                      SizedBox(
                        height: 220,
                        child: ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (_, i) {
                            final e = _entries[i];
                            final f = e.file;
                            final ext = f.name.contains('.')
                                ? f.name.split('.').last.toUpperCase()
                                : '';
                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(ext,
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary)),
                                ),
                              ),
                              title: Text(f.name,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                e.message.isNotEmpty
                                    ? e.message
                                    : f.relPath,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: e.status == _FileStatus.failed
                                      ? Colors.red.shade400
                                      : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: _statusIcon(e.status, f.size),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    if (_uploaded > 0)
                      _statusChip('$_uploaded 成功', Colors.green),
                    if (_failed > 0) ...[
                      const SizedBox(width: 8),
                      _statusChip('$_failed 失败', Colors.red),
                    ],
                    if (_uploaded == 0 && _failed == 0)
                      Text(_status,
                          style: TextStyle(
                              color: cs.primary, fontSize: 13)),
                  ]),
                ),
            ],
          ),
        ),
        // 底部上传按钮
        if (_entries.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _uploadAll,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_busy
                    ? '上传中 $_uploaded/${_entries.length}...'
                    : '上传到 GitHub'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusIcon(_FileStatus status, int size) {
    switch (status) {
      case _FileStatus.success:
        return const Icon(Icons.check_circle, size: 18, color: Colors.green);
      case _FileStatus.failed:
        return const Icon(Icons.cancel, size: 18, color: Colors.red);
      case _FileStatus.uploading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _FileStatus.pending:
        return Text(
          _formatSize(size),
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        );
    }
  }

  Widget _inputCard({
    required TextEditingController controller,
    required IconData icon,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _tokenInputCard(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: _tokenCtrl,
        obscureText: !_showToken,
        onChanged: (_) => setState(() => _tokenVerified = false),
        decoration: InputDecoration(
          labelText: 'GitHub 令牌（Token）',
          prefixIcon: const Icon(Icons.key, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: Icon(
                _showToken ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
            _tokenChecking
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.verified_user, size: 18),
                    tooltip: '校验令牌',
                    onPressed: _verifyToken,
                  ),
          ]),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 12, color: color)),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
