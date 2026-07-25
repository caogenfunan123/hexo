import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/repo_config.dart';
import '../services/github_service.dart';

/// 文件夹上传页面
/// 允许用户选择本地文件夹，批量上传到 GitHub 仓库的指定分支
class FolderUploadScreen extends StatefulWidget {
  /// 可用仓库列表
  final List<RepoConfig> repos;
  /// 当前激活的仓库ID
  final String? activeRepoId;
  /// GitHub 服务
  final GitHubService githubService;

  const FolderUploadScreen({
    super.key,
    required this.repos,
    this.activeRepoId,
    required this.githubService,
  });

  @override
  State<FolderUploadScreen> createState() => _FolderUploadScreenState();
}

class _FolderUploadScreenState extends State<FolderUploadScreen> {
  // 选中的文件夹路径
  String? _folderPath;

  // 扫描到的文件列表
  List<File> _files = [];
  int _totalSize = 0; // 总大小（字节）

  // 上传参数
  RepoConfig? _selectedRepo;
  String _branch = '';
  String _basePath = '';
  String _commitMessage = 'upload: batch upload folder';

  // 上传状态
  bool _uploading = false;
  int _uploadedCount = 0;
  String? _error;
  String? _successMsg;

  // 大文件阈值（超过此大小使用逐个上传，单位字节，默认 10MB）
  static const int _largeFileThreshold = 10 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  /// 初始化默认值
  void _initDefaults() {
    if (widget.repos.isNotEmpty) {
      final activeId = widget.activeRepoId;
      final match = activeId != null
          ? widget.repos.where((r) => r.id == activeId).firstOrNull
          : null;
      _selectedRepo = match ?? widget.repos.first;
      _branch = _selectedRepo!.branch;
    }
  }

  /// 选择文件夹
  Future<void> _pickFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择要上传的文件夹',
      );
      if (path == null || path.isEmpty) return;

      setState(() {
        _folderPath = path;
        _error = null;
        _successMsg = null;
      });

      // 扫描文件夹中的所有文件
      await _scanFiles();
    } catch (e) {
      setState(() => _error = '选择文件夹失败: $e');
    }
  }

  /// 递归扫描文件夹中所有文件
  Future<void> _scanFiles() async {
    if (_folderPath == null) return;

    final dir = Directory(_folderPath!);
    if (!await dir.exists()) {
      setState(() => _error = '文件夹不存在');
      return;
    }

    final allFiles = <File>[];
    int totalSize = 0;

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final size = await entity.length();
          // 跳过超过 100MB 的文件（GitHub API 限制）
          if (size <= 100 * 1024 * 1024) {
            allFiles.add(entity);
            totalSize += size;
          }
        }
      }

      setState(() {
        _files = allFiles;
        _totalSize = totalSize;
        _uploadedCount = 0;
        _successMsg = null;
      });
    } catch (e) {
      setState(() => _error = '扫描文件失败: $e');
    }
  }

  /// 开始上传
  Future<void> _startUpload() async {
    if (_selectedRepo == null) {
      setState(() => _error = '请选择目标仓库');
      return;
    }
    if (_branch.trim().isEmpty) {
      setState(() => _error = '请输入目标分支');
      return;
    }
    if (_files.isEmpty) {
      setState(() => _error = '没有可上传的文件');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _successMsg = null;
      _uploadedCount = 0;
    });

    try {
      final repo = _selectedRepo!;
      final folderDir = _folderPath!;

      // 分离小文件和大文件
      final smallFiles = <File>[];
      final largeFiles = <File>[];

      for (final f in _files) {
        final size = await f.length();
        if (size > _largeFileThreshold) {
          largeFiles.add(f);
        } else {
          smallFiles.add(f);
        }
      }

      // 处理小文件：通过 Git Tree API 批量上传
      if (smallFiles.isNotEmpty) {
        final batch = <String, String>{};
        for (final f in smallFiles) {
          final relPath = p.relative(f.path, from: folderDir);
          // 转换为 Unix 路径分隔符
          final unixPath = relPath.replaceAll('\\', '/');
          final bytes = await f.readAsBytes();
          batch[unixPath] = base64Encode(bytes);
        }

        await widget.githubService.uploadFilesToBranch(
          token: repo.token,
          owner: repo.owner,
          repo: repo.repo,
          branch: _branch,
          files: batch,
          message: _commitMessage,
          basePath: _basePath.trim(),
          onProgress: (processed, total) {
            if (mounted) {
              setState(() {
                _uploadedCount = processed;
              });
            }
          },
        );
      }

      // 处理大文件：逐个上传
      for (int i = 0; i < largeFiles.length; i++) {
        final f = largeFiles[i];
        final relPath = p.relative(f.path, from: folderDir).replaceAll('\\', '/');
        final remotePath = _basePath.trim().isEmpty
            ? relPath
            : '${_basePath.trim()}/${relPath}';
        final bytes = await f.readAsBytes();

        await widget.githubService.uploadBinary(
          token: repo.token,
          owner: repo.owner,
          repo: repo.repo,
          branch: _branch,
          path: remotePath,
          bytes: bytes,
          message: _commitMessage,
        );

        if (mounted) {
          setState(() {
            _uploadedCount = smallFiles.length + i + 1;
          });
        }
      }

      if (mounted) {
        setState(() {
          _successMsg = '上传完成！共上传 ${_files.length} 个文件，'
              '总计 ${_formatSize(_totalSize)}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '上传失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 错误提示
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),

          // 成功提示
          if (_successMsg != null)
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMsg!,
                        style:
                            const TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 选择文件夹
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择文件夹',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (_folderPath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _folderPath!,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFolder,
                      icon: const Icon(Icons.folder_copy),
                      label: const Text('浏览文件夹'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 文件预览
          if (_files.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('文件预览',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.description, size: 18),
                        const SizedBox(width: 6),
                        Text('共 ${_files.length} 个文件'),
                        const Spacer(),
                        Text('总计 ${_formatSize(_totalSize)}',
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 显示前20个文件
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount:
                            _files.length > 20 ? 20 : _files.length,
                        itemBuilder: (context, i) {
                          final f = _files[i];
                          final relPath = _folderPath != null
                              ? p.relative(f.path, from: _folderPath!)
                                  .replaceAll('\\', '/')
                              : f.path;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file,
                                    size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    relPath,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (_files.length > 20)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '... 还有 ${_files.length - 20} 个文件',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // 上传配置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('上传配置',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),

                  // 目标仓库
                  DropdownButtonFormField<RepoConfig>(
                    value: _selectedRepo,
                    decoration: const InputDecoration(
                      labelText: '目标仓库',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repository),
                    ),
                    items: widget.repos.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text('${r.name} (${r.fullName})',
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: _uploading
                        ? null
                        : (r) {
                            if (r != null) {
                              setState(() {
                                _selectedRepo = r;
                                _branch = r.branch;
                              });
                            }
                          },
                  ),

                  const SizedBox(height: 12),

                  // 目标分支
                  TextFormField(
                    initialValue: _branch,
                    decoration: const InputDecoration(
                      labelText: '目标分支',
                      hintText: '例如 main 或 hexo',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.branch),
                    ),
                    enabled: !_uploading,
                    onChanged: (v) => _branch = v.trim(),
                  ),

                  const SizedBox(height: 12),

                  // 目标路径前缀
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: '目标路径前缀',
                      hintText: '留空表示上传到仓库根目录',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder),
                    ),
                    enabled: !_uploading,
                    onChanged: (v) => _basePath = v.trim(),
                  ),

                  const SizedBox(height: 12),

                  // 提交信息
                  TextFormField(
                    initialValue: _commitMessage,
                    decoration: const InputDecoration(
                      labelText: '提交信息',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                    enabled: !_uploading,
                    onChanged: (v) => _commitMessage = v.trim(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 上传按钮
          ElevatedButton.icon(
            onPressed: (_uploading || _files.isEmpty) ? null : _startUpload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(_uploading
                ? '上传中...'
                : '上传 ${_files.length} 个文件'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          // 上传进度
          if (_uploading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _files.isEmpty
                            ? 0
                            : _uploadedCount / _files.length,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '已上传 $_uploadedCount / ${_files.length} 个文件',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
