import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/repo_config.dart';
import '../services/github_service.dart';

class UploadScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final GitHubService github;

  const UploadScreen({
    super.key,
    required this.repos,
    required this.github,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _pathCtrl = TextEditingController();
  final _targetPathCtrl = TextEditingController(text: 'source');
  final _commitMsgCtrl = TextEditingController();
  List<_UploadItem> _items = [];
  List<_DirEntry> _dirEntries = [];
  String _currentDir = '';
  bool _loading = false;
  bool _uploading = false;
  int _uploaded = 0;
  String? _error;
  RepoConfig? _repo;

  @override
  void initState() {
    super.initState();
    if (widget.repos.isNotEmpty) {
      _repo = widget.repos.first;
    }
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _targetPathCtrl.dispose();
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  void _browseLocal() {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      setState(() => _error = '请输入本地路径');
      return;
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      setState(() => _error = '路径不存在: $path');
      return;
    }
    setState(() {
      _currentDir = path;
      _error = null;
    });
    _loadDir(dir);
  }

  Future<void> _loadDir(Directory dir) async {
    setState(() => _loading = true);
    try {
      final entries = <_DirEntry>[];
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          entries.add(_DirEntry(name: name, path: entity.path, isDir: true));
        } else if (entity is File) {
          entries.add(_DirEntry(name: name, path: entity.path, isDir: false));
        }
      }
      entries.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.compareTo(b.name);
      });
      setState(() {
        _dirEntries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '读取目录失败: $e';
        _loading = false;
      });
    }
  }

  void _toggleItem(_DirEntry entry) {
    setState(() {
      if (entry.isDir) {
        // 进入子目录
        _pathCtrl.text = entry.path;
        _browseLocal();
      } else {
        // 选中文件
        final existing = _items.where((i) => i.localPath == entry.path).toList();
        if (existing.isNotEmpty) {
          _items.removeWhere((i) => i.localPath == entry.path);
        } else {
          _items.add(_UploadItem(
            name: entry.name,
            localPath: entry.path,
            size: File(entry.path).lengthSync(),
          ));
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      _items = [];
      for (final e in _dirEntries) {
        if (!e.isDir) {
          _items.add(_UploadItem(
            name: e.name,
            localPath: e.path,
            size: File(e.path).lengthSync(),
          ));
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _items = []);
  }

  Future<void> _uploadAll() async {
    if (_repo == null) {
      setState(() => _error = '请先配置仓库');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = '请选择文件');
      return;
    }
    setState(() {
      _uploading = true;
      _uploaded = 0;
      _error = null;
    });
    final msg = _commitMsgCtrl.text.trim().isEmpty
        ? '批量上传 ${_items.length} 个文件'
        : _commitMsgCtrl.text.trim();
    final basePath = _targetPathCtrl.text.trim();

    try {
      for (final item in _items) {
        final content = await File(item.localPath).readAsBytes();
        final fileName = p.basename(item.localPath);
        final targetPath = basePath.isEmpty ? fileName : '$basePath/$fileName';
        await widget.github.uploadBinary(
          token: _repo!.token,
          owner: _repo!.owner,
          repo: _repo!.repo,
          branch: _repo!.branch,
          path: targetPath,
          bytes: content,
          message: msg,
        );
        setState(() => _uploaded++);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 成功上传 $_uploaded 个文件')),
        );
        setState(() {
          _items = [];
          _uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '上传失败: $e';
          _uploading = false;
        });
      }
    }
  }

  String _formatSize(int size) {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _dirEntries.isEmpty && _items.isEmpty
                  ? _buildEmpty()
                  : _buildContent(),
        ),
        if (_uploading) _buildProgress(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<RepoConfig?>(
                  value: _repo,
                  decoration: const InputDecoration(
                    labelText: '目标仓库',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final r in widget.repos)
                      DropdownMenuItem(
                        value: r,
                        child: Text(r.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _repo = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _targetPathCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标路径',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  decoration: const InputDecoration(
                    labelText: '本地路径',
                    hintText: '/data/user/0/...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loading ? null : _browseLocal,
                child: const Text('浏览'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commitMsgCtrl,
                  decoration: const InputDecoration(
                    labelText: '提交信息',
                    hintText: '批量上传文件',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _uploading ? null : _uploadAll,
                icon: const Icon(Icons.upload),
                label: Text(_uploading ? '上传中...' : '上传'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _selectAll,
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: _clearSelection,
                child: const Text('清空'),
              ),
              const Spacer(),
              Text('已选 ${_items.length} 个文件'),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('输入本地路径后点击浏览'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView.builder(
      itemCount: _dirEntries.length + (_items.isNotEmpty ? _items.length + 1 : 0),
      itemBuilder: (context, i) {
        if (i < _dirEntries.length) {
          final entry = _dirEntries[i];
          final isSelected = !entry.isDir && _items.any((item) => item.localPath == entry.path);
          return ListTile(
            dense: true,
            leading: Icon(
              entry.isDir ? Icons.folder : Icons.insert_drive_file,
              color: entry.isDir ? Colors.amber : Colors.blue,
            ),
            title: Text(entry.name),
            trailing: entry.isDir
                ? const Icon(Icons.chevron_right, size: 16)
                : Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? Colors.green : Colors.grey,
                    size: 16,
                  ),
            onTap: () => _toggleItem(entry),
          );
        } else if (i == _dirEntries.length) {
          return const Divider();
        } else {
          final item = _items[i - _dirEntries.length - 1];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle, color: Colors.green, size: 16),
            title: Text(item.name),
            trailing: Text(_formatSize(item.size)),
            onTap: () => setState(() => _items.removeWhere((e) => e.localPath == item.localPath)),
          );
        }
      },
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _items.isEmpty ? 0 : _uploaded / _items.length,
          ),
          const SizedBox(height: 4),
          Text('$_uploaded / ${_items.length} 已上传'),
        ],
      ),
    );
  }
}

class _DirEntry {
  final String name;
  final String path;
  final bool isDir;

  _DirEntry({required this.name, required this.path, required this.isDir});
}

class _UploadItem {
  final String name;
  final String localPath;
  final int size;

  _UploadItem({required this.name, required this.localPath, required this.size});
}
