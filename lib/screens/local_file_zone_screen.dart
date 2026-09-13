import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';

/// 本地文件区：固定统一的本地文件暂存界面。
///
/// 替代原生 openFolder（移动端私有沙盒 / 无 MIME 处理程序时易报错）：
/// - 应用内浏览 StorageService 根目录（分类子文件夹 + 站点目录）
/// - 文本文件支持查看与编辑（保存即回写本地，完成"暂存修改"）
/// - 可把仓库文件"下载到本地"暂存、编辑后再"统一上传"回仓库
/// - 可从系统选择文件导入暂存区
/// - 可选择外部目录浏览任意位置的文件
///
/// 跨平台（Android/iOS/桌面）统一走 dart:io 文件读写，不依赖原生 channel。
class LocalFileZoneScreen extends StatefulWidget {
  final StorageService storage;
  final GitHubService? github;
  final RepoConfig? activeRepo;
  final void Function(String fileName, String content, String filePath)? onOpenFile;

  const LocalFileZoneScreen({
    super.key,
    required this.storage,
    this.github,
    this.activeRepo,
    this.onOpenFile,
  });

  @override
  State<LocalFileZoneScreen> createState() => _LocalFileZoneScreenState();
}

class _LocalFileZoneScreenState extends State<LocalFileZoneScreen> {
  Directory? _cwd;
  final List<FileSystemEntity> _entries = [];
  final Set<String> _loadErrors = {};
  bool _loading = true;
  static const _channel = MethodChannel('hexo/native');

  @override
  void initState() {
    super.initState();
    _openRoot();
  }

  Future<void> _openRoot() async {
    setState(() => _loading = true);
    try {
      final root = await widget.storage.root;
      if (!await root.exists()) await root.create(recursive: true);
      await widget.storage.ensureCategoryDirs();
      _cwd = root;
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadErrors.add('打开根目录失败: $e');
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadEntries() async {
    final dir = _cwd;
    if (dir == null || !mounted) return;
    setState(() => _loading = true);
    final entries = <FileSystemEntity>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        entries.add(e);
      }
    } catch (e) {
      if (mounted) _loadErrors.add('无法读取目录: ${dir.path}（$e）');
    }
    entries.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return a.path
          .split(Platform.pathSeparator)
          .last
          .toLowerCase()
          .compareTo(b.path.split(Platform.pathSeparator).last.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _loading = false;
    });
  }

  String _name(FileSystemEntity e) =>
      e.path.split(Platform.pathSeparator).last;

  Future<void> _enter(Directory dir) async {
    _cwd = dir;
    await _loadEntries();
  }

  Future<void> _goUp() async {
    final dir = _cwd;
    if (dir == null) return;
    final parent = dir.parent;
    final root = await widget.storage.root;
    final isRoot = dir.path == root.path;
    if (isRoot) return;
    _cwd = parent;
    await _loadEntries();
  }

  Future<void> _refresh() async {
    await _loadEntries();
  }

  /// 选择外部目录浏览
  Future<void> _chooseExternalDirectory() async {
    // Android 11+ 需要检查"所有文件访问"权限
    if (Platform.isAndroid) {
      try {
        final hasPermission = await _channel.invokeMethod<bool>('checkManageStoragePermission');
        if (hasPermission != true) {
          // 弹窗说明权限用途
          if (!mounted) return;
          final granted = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要文件访问权限'),
              content: const Text('浏览和编辑设备上的文件需要"所有文件访问"权限。\n\n请点击"授权"前往系统设置中开启。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('授权'),
                ),
              ],
            ),
          );
          if (granted != true) return;
          // 请求权限
          final result = await _channel.invokeMethod<bool>('requestManageStoragePermission');
          if (result != true) {
            _showToast('未获得文件访问权限');
            return;
          }
        }
      } catch (e) {
        _showToast('权限检查失败: $e');
        return;
      }
    }
    // 选择目录
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || !mounted) return;
    final dir = Directory(path);
    if (!await dir.exists()) {
      _showToast('目录不存在: $path');
      return;
    }
    _cwd = dir;
    await _loadEntries();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  /// 文本文件：查看或编辑（保存回写本地）
  Future<void> _openTextEditor(File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      _showToast('读取失败: $e');
      return;
    }
    final size = await file.length();
    if (size > 512 * 1024) {
      _showToast('文件较大，仅预览前 512KB');
    }
    if (!mounted) return;
    final controller = TextEditingController(text: content);
    final segment = size > 512 * 1024 ? content.substring(0, 512 * 1024) : content;
    controller.text = segment;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_name(file)),
        content: SizedBox(
          width: 560,
          height: 400,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: '在此编辑本地文件，保存后回写暂存区',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存到本地'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await file.writeAsString(controller.text, flush: true);
        _showToast('已保存到本地暂存: ${_name(file)}');
      } catch (e) {
        _showToast('保存失败: $e');
      }
    }
    controller.dispose();
  }

  /// 选择系统文件导入当前目录（暂存区补充）
  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final cwd = _cwd;
    if (cwd == null) return;
    var ok = 0;
    for (final f in result.files) {
      final src = f.path;
      if (src == null) continue;
      final dest = File('${cwd.path}/${f.name}');
      try {
        if (await dest.exists()) {
          final fName = f.name;
          final dot = fName.lastIndexOf('.');
          final base = dot > 0 ? fName.substring(0, dot) : fName;
          final ext = dot > 0 ? fName.substring(dot) : '';
          final ts = DateTime.now().millisecondsSinceEpoch;
          final alt = File('${cwd.path}/${base}_$ts$ext');
          await File(src).copy(alt.path);
        } else {
          await File(src).copy(dest.path);
        }
        ok++;
      } catch (e) {
        _showToast('导入失败: ${f.name} ($e)');
      }
    }
    if (ok > 0) {
      _showToast('已导入 $ok 个文件到暂存区');
      await _loadEntries();
    }
  }

  /// 下载仓库文件到本地暂存区
  Future<void> _downloadFromRepo(String path) async {
    final github = widget.github;
    final repo = widget.activeRepo;
    if (github == null || repo == null) {
      _showToast('请先在工作区绑定仓库');
      return;
    }
    final cwd = _cwd;
    if (cwd == null) return;
    try {
      final data = await github.getRawFile(repo, path);
      if (data == null) {
        _showToast('仓库文件不存在: $path');
        return;
      }
      final name = path.split('/').last;
      final dest = File('${cwd.path}/$name');
      await dest.writeAsString(data['content'] ?? '', flush: true);
      _showToast('已下载到本地暂存: $name');
      await _loadEntries();
    } catch (e) {
      _showToast('下载失败: $e');
    }
  }

  /// 上传本地文件到仓库（统一上传）
  Future<void> _uploadToRepo(File file, String repoPath) async {
    final github = widget.github;
    final repo = widget.activeRepo;
    if (github == null || repo == null) {
      _showToast('请先在工作区绑定仓库');
      return;
    }
    try {
      final content = await file.readAsString();
      String? sha;
      try {
        final existing = await github.getRawFile(repo, repoPath);
        sha = existing?['sha'];
      } catch (_) {}
      await github.putRawFile(repo, repoPath, content,
          sha: sha, commitMessage: 'chore: upload ${_name(file)}');
      _showToast('已上传到仓库: $repoPath');
    } catch (e) {
      _showToast('上传失败: $e');
    }
  }

  /// 文件操作菜单：编辑 / 在编辑器中打开 / 上传仓库 / 复制路径
  Future<void> _fileActions(File file) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(_name(file)),
              subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            if (widget.onOpenFile != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('在编辑器中打开'),
                onTap: () => Navigator.pop(ctx, 'open_in_editor'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑 / 查看（保存回写本地暂存）'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('统一上传到仓库'),
              onTap: () => Navigator.pop(ctx, 'upload'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('复制完整路径'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'open_in_editor':
        await _openInEditor(file);
        break;
      case 'edit':
        await _openTextEditor(file);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: file.path));
        _showToast('已复制路径');
        break;
      case 'upload':
        if (widget.github == null || widget.activeRepo == null) {
          _showToast('请先在工作区绑定仓库');
          return;
        }
        final repoPath = await _askRepoPath(_name(file));
        if (repoPath == null) return;
        await _uploadToRepo(file, repoPath);
        break;
    }
  }

  /// 在编辑器中打开文件
  Future<void> _openInEditor(File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      _showToast('读取失败: $e');
      return;
    }
    final name = _name(file);
    final fileName = name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
    widget.onOpenFile?.call(fileName, content, file.path);
    if (mounted) {
      _showToast('已打开: $name');
      Navigator.of(context).pop();
    }
  }

  Future<String?> _askRepoPath(String fileName) async {
    final ctrl = TextEditingController(
      text: 'source/_posts/$fileName',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传到仓库路径'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '仓库相对路径',
            helperText: '例如 source/_posts/example.md',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('上传'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  @override
  void dispose() {
    _cwd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootPath = _cwd?.path ?? '';
    final showUp = _cwd != null;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('本地文件区'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '选择外部目录',
            onPressed: _loading ? null : _chooseExternalDirectory,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '下载仓库文件到暂存',
            onPressed: () async {
              final path = await _askRepoPath('example.md');
              if (path != null) await _downloadFromRepo(path);
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: '导入文件到暂存区',
            onPressed: _loading ? null : _importFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rootPath.isEmpty ? '加载中...' : rootPath,
                    style: const TextStyle(fontSize: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showUp)
                  TextButton.icon(
                    onPressed: _loading ? null : _goUp,
                    icon: const Icon(Icons.arrow_upward, size: 15),
                    label: const Text('上一级'),
                  ),
              ],
            ),
          ),
          if (_loadErrors.isNotEmpty)
            for (final e in _loadErrors)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: cs.errorContainer.withOpacity(0.5),
                child: Text(e,
                    style: TextStyle(fontSize: 11, color: cs.onErrorContainer)),
              ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Text('该目录为空，可导入或下载文件到暂存区',
                            style: TextStyle(color: cs.outline)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _entries.length,
                        itemBuilder: (ctx, i) {
                          final e = _entries[i];
                          final name = _name(e);
                          final isDir = e is Directory;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDir
                                  ? Icons.folder
                                  : _iconForFile(name),
                              color: isDir ? cs.primary : cs.outline,
                              size: 20,
                            ),
                            title: Text(name,
                                style: const TextStyle(fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: isDir
                                ? null
                                : Text(
                                    _fileDetail(e as File),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                            trailing: isDir
                                ? const Icon(Icons.chevron_right, size: 18)
                                : null,
                            onTap: () {
                              if (e is Directory) {
                                _enter(e);
                              } else if (e is File) {
                                _fileActions(e);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.md')) return Icons.description_outlined;
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.png') || lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') || lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _fileDetail(File f) {
    final size = f.lengthSync();
    return _formatSize(size);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}