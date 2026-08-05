/// P2P mDNS 设备发现服务
///
/// 参考 local_network_flutter (https://github.com/bluefireteam/local_network_flutter)：
/// - 封装 mDNS 服务广播和发现
/// - 使用 dart:io 的 RawDatagramSocket 或 Multicast 实现
/// - 服务类型：_hexo-sync._tcp
/// - 自动发现局域网内其他 Hexo 设备
/// - 设备上线/离线通知
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 发现的设备信息
class MdnsDevice {
  final String id;
  final String name;
  final String hostname;
  final String address;
  final int port;
  final DateTime lastSeen;
  final Map<String, String> properties;

  const MdnsDevice({
    required this.id,
    required this.name,
    required this.hostname,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.properties = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostname': hostname,
        'address': address,
        'port': port,
        'lastSeen': lastSeen.toIso8601String(),
        'properties': properties,
      };

  factory MdnsDevice.fromJson(Map<String, dynamic> j) => MdnsDevice(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        hostname: j['hostname']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        lastSeen:
            DateTime.tryParse(j['lastSeen']?.toString() ?? '') ?? DateTime.now(),
        properties: Map<String, String>.from(j['properties'] ?? {}),
      );

  @override
  bool operator ==(Object other) =>
      other is MdnsDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// P2P mDNS 服务状态
enum MdnsDiscoveryState {
  idle,
  discovering,
  advertising,
  error,
}

/// P2P mDNS 设备发现服务
///
/// 使用组播 UDP 实现局域网设备发现，模拟 mDNS 协议。
/// 服务类型：_hexo-sync._tcp
class P2PMdnsService {
  static const int _multicastPort = 5353;
  static const String _multicastAddress = '224.0.0.251';
  static const String _serviceType = '_hexo-sync._tcp';
  static const int _discoveryIntervalSeconds = 5;
  static const int _cleanupIntervalSeconds = 30;
  static const int _deviceTimeoutSeconds = 60;

  final String _deviceId;
  final String _deviceName;
  final int _servicePort;

  MdnsDiscoveryState _state = MdnsDiscoveryState.idle;
  String? _errorMessage;

  final List<MdnsDevice> _discoveredDevices = [];
  RawDatagramSocket? _multicastSocket;
  StreamSubscription<RawSocketEvent>? _multicastSubscription;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final StreamController<MdnsDevice> _deviceDiscoveredController =
      StreamController<MdnsDevice>.broadcast();
  final StreamController<MdnsDevice> _deviceLostController =
      StreamController<MdnsDevice>.broadcast();
  final StreamController<MdnsDiscoveryState> _stateController =
      StreamController<MdnsDiscoveryState>.broadcast();

  P2PMdnsService({
    required String deviceId,
    required String deviceName,
    required int servicePort,
  })  : _deviceId = deviceId,
        _deviceName = deviceName,
        _servicePort = servicePort;

  // ── Getters ──

  MdnsDiscoveryState get state => _state;
  String? get errorMessage => _errorMessage;
  List<MdnsDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  Stream<MdnsDevice> get onDeviceDiscovered =>
      _deviceDiscoveredController.stream;
  Stream<MdnsDevice> get onDeviceLost => _deviceLostController.stream;
  Stream<MdnsDiscoveryState> get onStateChange => _stateController.stream;

  // ============================================================
  // 启动/停止
  // ============================================================

  /// 启动 mDNS 发现服务
  Future<void> startDiscovery() async {
    if (_state == MdnsDiscoveryState.discovering) return;

    _setState(MdnsDiscoveryState.discovering);

    try {
      await _bindMulticastSocket();
      _startBroadcastTimer();
      _startCleanupTimer();
    } catch (e) {
      _setState(MdnsDiscoveryState.error);
      _errorMessage = '启动发现失败: $e';
    }
  }

  /// 停止 mDNS 发现服务
  Future<void> stopDiscovery() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    await _multicastSubscription?.cancel();
    _multicastSubscription = null;
    _multicastSocket?.close();
    _multicastSocket = null;

    _discoveredDevices.clear();
    _setState(MdnsDiscoveryState.idle);
  }

  /// 启动服务广播
  Future<void> startAdvertising(int port) async {
    _setState(MdnsDiscoveryState.advertising);

    try {
      if (_multicastSocket == null) {
        await _bindMulticastSocket();
      }
      _startBroadcastTimer();
    } catch (e) {
      _setState(MdnsDiscoveryState.error);
      _errorMessage = '启动广播失败: $e';
    }
  }

  /// 停止服务广播
  Future<void> stopAdvertising() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _setState(MdnsDiscoveryState.idle);
  }

  // ============================================================
  // 内部实现
  // ============================================================

  Future<void> _bindMulticastSocket() async {
    _multicastSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _multicastPort,
      reuseAddress: true,
    );

    // 加入组播组
    _multicastSocket!.joinMulticast(
      InternetAddress(_multicastAddress),
    );
    _multicastSocket!.broadcastEnabled = true;
    _multicastSocket!.readEventsEnabled = true;

    _multicastSubscription = _multicastSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        _handleMulticastPacket();
      }
    });
  }

  void _handleMulticastPacket() {
    final socket = _multicastSocket;
    if (socket == null) return;

    Datagram? datagram;
    try {
      datagram = socket.receive();
    } catch (e) { debugPrint('P2PMdns: packet handle failed: $e');
      return;
    }
    if (datagram == null) return;

    try {
      final data = utf8.decode(datagram.data);
      _processMessage(data, datagram.address.address);
    } catch (e) { debugPrint('P2PMdns: broadcast send failed: $e');
      // 忽略无效消息
    }
  }

  void _processMessage(String message, String sourceAddress) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type']?.toString() ?? '';

      switch (type) {
        case 'query':
          // 收到查询请求，回复服务信息
          _sendServiceResponse(sourceAddress);
          break;
        case 'response':
          // 收到服务响应
          _handleServiceResponse(json, sourceAddress);
          break;
        case 'goodbye':
          // 设备下线通知
          _handleGoodbye(json);
          break;
      }
    } catch (e) { debugPrint('P2PMdns: cleanup failed: $e');
      // 忽略无法解析的消息
    }
  }

  void _sendServiceResponse(String targetAddress) {
    final socket = _multicastSocket;
    if (socket == null) return;

    final response = jsonEncode({
      'type': 'response',
      'serviceType': _serviceType,
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'hostname': Platform.localHostname,
      'port': _servicePort,
      'timestamp': DateTime.now().toIso8601String(),
      'properties': {
        'platform': Platform.operatingSystem,
        'version': '1.0.0',
      },
    });

    try {
      socket.send(
        utf8.encode(response),
        InternetAddress(targetAddress),
        _multicastPort,
      );
    } catch (e) { debugPrint('P2PMdns: response parse failed: $e'); }
  }

  void _handleServiceResponse(Map<String, dynamic> json, String sourceAddress) {
    final deviceId = json['deviceId']?.toString() ?? '';
    // 忽略自己
    if (deviceId == _deviceId) return;

    final device = MdnsDevice(
      id: deviceId,
      name: json['deviceName']?.toString() ?? 'Unknown',
      hostname: json['hostname']?.toString() ?? sourceAddress,
      address: sourceAddress,
      port: (json['port'] as num?)?.toInt() ?? _servicePort,
      lastSeen: DateTime.now(),
      properties: json['properties'] != null
          ? Map<String, String>.from(json['properties'])
          : {},
    );

    final existingIndex =
        _discoveredDevices.indexWhere((d) => d.id == device.id);
    if (existingIndex >= 0) {
      _discoveredDevices[existingIndex] = device;
    } else {
      _discoveredDevices.add(device);
      _deviceDiscoveredController.add(device);
    }
  }

  void _handleGoodbye(Map<String, dynamic> json) {
    final deviceId = json['deviceId']?.toString() ?? '';
    final device = _discoveredDevices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => MdnsDevice(
        id: deviceId,
        name: '',
        hostname: '',
        address: '',
        port: 0,
        lastSeen: DateTime.now(),
      ),
    );
    _discoveredDevices.removeWhere((d) => d.id == deviceId);
    _deviceLostController.add(device);
  }

  void _startBroadcastTimer() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(
      Duration(seconds: _discoveryIntervalSeconds),
      (_) => _sendQuery(),
    );
    // 立即发送一次
    _sendQuery();
  }

  void _sendQuery() {
    final socket = _multicastSocket;
    if (socket == null) return;

    final query = jsonEncode({
      'type': 'query',
      'serviceType': _serviceType,
      'deviceId': _deviceId,
      'deviceName': _deviceName,
    });

    try {
      socket.send(
        utf8.encode(query),
        InternetAddress(_multicastAddress),
        _multicastPort,
      );
    } catch (e) { debugPrint('P2PMdns: goodbye send failed: $e'); }
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      Duration(seconds: _cleanupIntervalSeconds),
      (_) => _cleanupStaleDevices(),
    );
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleDevices = _discoveredDevices
        .where((d) =>
            now.difference(d.lastSeen).inSeconds > _deviceTimeoutSeconds)
        .toList();

    for (final device in staleDevices) {
      _discoveredDevices.remove(device);
      _deviceLostController.add(device);
    }
  }

  /// 发送下线通知
  Future<void> _sendGoodbye() async {
    final socket = _multicastSocket;
    if (socket == null) return;

    final goodbye = jsonEncode({
      'type': 'goodbye',
      'serviceType': _serviceType,
      'deviceId': _deviceId,
      'deviceName': _deviceName,
    });

    try {
      socket.send(
        utf8.encode(goodbye),
        InternetAddress(_multicastAddress),
        _multicastPort,
      );
    } catch (e) { debugPrint('P2PMdns: state update failed: $e'); }
  }

  void _setState(MdnsDiscoveryState newState) {
    _state = newState;
    if (newState != MdnsDiscoveryState.error) {
      _errorMessage = null;
    }
    _stateController.add(newState);
  }

  // ============================================================
  // 清理
  // ============================================================

  Future<void> dispose() async {
    await _sendGoodbye();
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    await _multicastSubscription?.cancel();
    _multicastSubscription = null;
    _multicastSocket?.close();
    _deviceDiscoveredController.close();
    _deviceLostController.close();
    _stateController.close();
    _state = MdnsDiscoveryState.idle;
  }
}