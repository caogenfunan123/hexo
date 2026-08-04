/// 局域网 P2P 同步界面
///
/// 显示发现设备列表、连接状态、文件同步进度
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/p2p_sync_service.dart';
import '../models/article.dart';

class P2PSyncScreen extends StatefulWidget {
  final P2PSyncService p2pService;
  final List<Article> localArticles;
  final void Function(List<P2PFileEntry> files)? onFilesReceived;

  const P2PSyncScreen({
    super.key,
    required this.p2pService,
    this.localArticles = const [],
    this.onFilesReceived,
  });

  @override
  State<P2PSyncScreen> createState() => _P2PSyncScreenState();
}

class _P2PSyncScreenState extends State<P2PSyncScreen> {
  List<P2PDevice> _devices = [];
  List<String> _logs = [];
  P2PState _p2pState = P2PState.idle;
  bool _isRunning = false;
  StreamSubscription<P2PDevice>? _deviceSub;
  StreamSubscription<P2PDevice>? _lostSub;
  StreamSubscription<String>? _logSub;

  @override
  void initState() {
    super.initState();
    _updateState();
    _deviceSub = widget.p2pService.onDeviceDiscovered.listen((d) {
      if (!mounted) return;
      setState(() => _devices = widget.p2pService.discoveredDevices);
    });
    _lostSub = widget.p2pService.onDeviceLost.listen((d) {
      if (!mounted) return;
      setState(() => _devices = widget.p2pService.discoveredDevices);
    });
    _logSub = widget.p2pService.onLog.listen((msg) {
      if (!mounted) return;
      setState(() {
        _logs.add(msg);
        if (_logs.length > 100) _logs.removeAt(0);
      });
    });
  }

  void _updateState() {
    _p2pState = widget.p2pService.state;
    _isRunning = _p2pState != P2PState.idle;
    _devices = widget.p2pService.discoveredDevices;
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _lostSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleP2P() async {
    if (_isRunning) {
      await widget.p2pService.stop();
    } else {
      await widget.p2pService.start();
    }
    if (!mounted) return;
    setState(() => _updateState());
  }

  Future<void> _connectToDevice(P2PDevice device) async {
    final success = await widget.p2pService.connectToDevice(device);
    if (!mounted) return;
    setState(() => _updateState());
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接到 ${device.name}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接失败，请检查网络和防火墙设置')),
      );
    }
  }

  Future<void> _syncFiles() async {
    if (widget.localArticles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可同步的文章')),
      );
      return;
    }

    // 将本地文章转换为 P2PFileEntry
    final files = widget.localArticles.map((a) => P2PFileEntry(
      path: a.fileName(),
      content: a.content,
      modifiedAt: a.updatedAt,
      sha256: _simpleHash(a.content),
    )).toList();

    final success = await widget.p2pService.sendFiles(files);
    if (!mounted) return;
    setState(() => _updateState());

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已发送 ${files.length} 个文件')),
      );
    }
  }

  String _simpleHash(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash) + input.codeUnitAt(i);
      hash |= 0;
    }
    return hash.toRadixString(16);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网 P2P 同步'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 服务开关
          Switch(
            value: _isRunning,
            onChanged: (_) => _toggleP2P(),
            activeColor: cs.primary,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          _buildStatusBar(cs, isDark),
          const Divider(height: 1),
          // 设备列表
          Expanded(
            child: Row(
              children: [
                // 左侧：设备列表
                Expanded(
                  flex: 3,
                  child: _buildDeviceList(cs, isDark),
                ),
                const VerticalDivider(width: 1),
                // 右侧：日志
                Expanded(
                  flex: 2,
                  child: _buildLogPanel(cs, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme cs, bool isDark) {
    final statusText = switch (_p2pState) {
      P2PState.idle => '未启动',
      P2PState.discovering => '正在发现设备...',
      P2PState.connecting => '正在连接...',
      P2PState.connected => '已连接: ${widget.p2pService.connectedDevice?.name ?? ""}',
      P2PState.syncing => '正在同步...',
      P2PState.error => '错误: ${widget.p2pService.errorMessage ?? ""}',
    };

    final statusColor = switch (_p2pState) {
      P2PState.connected => Colors.green,
      P2PState.syncing => Colors.blue,
      P2PState.error => Colors.red,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1F2937),
            ),
          ),
          const Spacer(),
          Text(
            '设备ID: ${widget.p2pService.deviceId}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(ColorScheme cs, bool isDark) {
    if (!_isRunning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('P2P 服务未启动', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('启动服务'),
              onPressed: _toggleP2P,
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text('正在搜索局域网设备...', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text(
              '确保其他设备也启动了 P2P 同步',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '发现 ${_devices.length} 个设备',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withOpacity(0.7) : const Color(0xFF6B7280),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _devices.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (_, i) {
              final device = _devices[i];
              final isConnected = widget.p2pService.connectedDevice?.id == device.id;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isConnected
                        ? Colors.green.withOpacity(0.2)
                        : cs.primary.withOpacity(0.1),
                    child: Icon(
                      isConnected ? Icons.link : Icons.devices,
                      size: 18,
                      color: isConnected ? Colors.green : cs.primary,
                    ),
                  ),
                  title: Text(
                    device.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '${device.address}:${device.port}',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade500),
                  ),
                  trailing: isConnected
                      ? TextButton(
                          onPressed: () {
                            widget.p2pService.disconnect();
                            setState(() => _updateState());
                          },
                          child: const Text('断开', style: TextStyle(color: Colors.red)),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _connectToDevice(device),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 32),
                          ),
                          child: const Text('连接', style: TextStyle(fontSize: 12)),
                        ),
                ),
              );
            },
          ),
        ),
        // 同步按钮
        if (widget.p2pService.connectedDevice != null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text('同步 ${widget.localArticles.length} 篇文章'),
                  onPressed: _p2pState == P2PState.syncing ? null : _syncFiles,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogPanel(ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '同步日志',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withOpacity(0.7) : const Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _logs.clear()),
                child: Text(
                  '清空',
                  style: TextStyle(fontSize: 11, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  itemCount: _logs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: isDark
                          ? Colors.white.withOpacity(0.5)
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}