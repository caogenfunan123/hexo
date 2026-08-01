import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

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
  final _targetPathCtrl = TextEditingController(text: 'source/_posts');
  final _commitMsgCtrl = TextEditingController(text: 'upload: batch files');
  List<PlatformFile> _selectedFiles = [];
  bool _busy = false;
  String _status = '';
  int _uploaded = 0;
  int _failed = 0;
  RepoConfig? _repo;

  @override
  void initState() {
    super.initState();
    _repo = widget.activeRepo ??
        (widget.repos.isNotEmpty ? widget.repos.first : null);
  }

  @override
  void dispose() {
    _targetPathCtrl.dispose();
    _commitMsgCtrl.dispose();
    super.dispose();
  }

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
      setState(() => _selectedFiles = result.files);
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final dir = Directory(result);
      final files = <PlatformFile>[];
      void scan(Directory d) {
        for (final entity in d.listSync(recursive: true)) {
          if (entity is File) {
            final relPath = entity.path.substring(result.length + 1);
            files.add(PlatformFile(
              name: entity.path.split('/').last,
              path: entity.path,
              size: entity.lengthSync(),
            )..customData = relPath);
          }
        }
      }
      scan(dir);
      setState(() => _selectedFiles = files);
    }
  }

  Future<void> _uploadAll() async {
    final repo = _repo;
    if (repo == null || repo.token.isEmpty) {
      _showToast('请先配置仓库与 Token');
      return;
    }
    if (_selectedFiles.isEmpty) {
      _showToast('请先选择文件');
      return;
    }
    setState(() {
      _busy = true;
      _uploaded = 0;
      _failed = 0;
      _status = '正在上传...';
    });

    final basePath = _targetPathCtrl.text.replaceAll(RegExp(r'/+$'), '');
    final msg = _commitMsgCtrl.text.trim();

    for (final file in _selectedFiles) {
      try {
        if (file.path == null) continue;
        final bytes = await File(file.path!).readAsBytes();
        final relPath = file.customData?.toString() ?? file.name;
        final targetPath = '$basePath/$relPath';

        await widget.github.uploadBinary(
          token: repo.token,
          owner: repo.owner,
          repo: repo.repo,
          branch: repo.branch,
          path: targetPath,
          bytes: bytes,
          message: '$msg: $relPath',
        );
        _uploaded++;
        if (mounted) {
          setState(() => _status = '已上传 $_uploaded/${_selectedFiles.length}');
        }
      } catch (e) {
        _failed++;
        if (mounted) {
          setState(() => _status = '已完成 $_uploaded/$_failed 失败');
        }
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = '上传完成: $_uploaded 成功, $_failed 失败';
      });
    }
    _showToast(_status);
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles = [];
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 仓库选择器
              if (widget.repos.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: DropdownButtonFormField<String>(
                    value: _repo?.id,
                    decoration: const InputDecoration(
                      labelText: '目标仓库',
                      prefixIcon:
                          Icon(Icons.storage_outlined, size: 20),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                    ),
                    items: widget.repos
                        .map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.name} (${r.fullName})',
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(
                        () => _repo = widget.repos.firstWhere((e) => e.id == v)),
                  ),
                ),
              // 目标路径
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _targetPathCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标路径（如 source/_posts）',
                    prefixIcon: Icon(Icons.folder_outlined, size: 20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 提交信息
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _commitMsgCtrl,
                  decoration: const InputDecoration(
                    labelText: '提交信息',
                    prefixIcon: Icon(Icons.message_outlined, size: 20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
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
              // 已选文件列表
              if (_selectedFiles.isNotEmpty)
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
                            '已选 ${_selectedFiles.length} 个文件',
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
                        height: 200,
                        child: ListView.builder(
                          itemCount: _selectedFiles.length,
                          itemBuilder: (_, i) {
                            final f = _selectedFiles[i];
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
                                f.customData?.toString() ?? f.path ?? '',
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _formatSize(f.size),
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B)),
                              ),
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
        if (_selectedFiles.isNotEmpty)
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
            child: FilledButton.icon(
              onPressed: _busy ? null : _uploadAll,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(_busy ? '上传中...' : '上传到 GitHub'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
      ],
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