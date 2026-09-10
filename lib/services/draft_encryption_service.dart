/// 草稿加密服务
///
/// 对本地 drafts.json 内容做 AES-256-GCM 加密（复用 site_encryption_service
/// 的算法），通过 StorageService 的加解密钩子透明接入，桌面端与移动端共享。
/// 加密状态与密码哈希存于配置文件，密码本身仅在本次会话内存中保留，
/// 防止明文密码落盘。
///
/// 存量迁移保护：首次开启加密时，自动将现有明文 drafts.json 加密为
/// drafts.json.enc（保留 .bak 备份）；关闭加密时反向解密回明文。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'site_encryption_service.dart';
import 'storage_service.dart';

/// 草稿加密服务（全局单例式状态）
class DraftEncryptionService {
  static const _metaFile = 'draft_enc.json';

  /// 是否已开启草稿加密
  static bool enabled = false;

  /// 会话内内存密码（不落盘）
  static String? _password;

  /// 密码哈希（用于设置/验证）
  static String _passwordHash = '';

  /// 校验用的 salt
  static String _salt = '';

  /// 初始化：加载加密元数据
  static Future<void> load(StorageService storage) async {
    if (kIsWeb) return;
    try {
      final root = await storage.root;
      final f = File('${root.path}/$_metaFile');
      if (!await f.exists()) return;
      final text = await f.readAsString();
      if (text.trim().isEmpty) return;
      final m = jsonDecode(text) as Map<String, dynamic>;
      enabled = m['enabled'] == true;
      _passwordHash = m['passwordHash']?.toString() ?? '';
      _salt = m['salt']?.toString() ?? '';
      if (enabled && _passwordHash.isEmpty) {
        // 元数据异常：加密已开但无密码哈希 → 视为未开启，避免锁死数据
        enabled = false;
      }
    } catch (e) {
      debugPrint('DraftEncryption: load meta error: $e');
    }
  }

  /// 密码是否已设置
  static bool get hasPassword => _passwordHash.isNotEmpty;

  /// 会话中是否持有正确密码
  static bool get unlocked => _password != null;

  /// 设置加密密码（首次启用时）
  ///
  /// [password] 用户设置的密码
  /// [confirm] 确认密码
  /// 返回 null 表示成功，否则返回错误提示
  static Future<String?> setPassword(String password, String confirm, StorageService storage) async {
    if (password.length < 8) return '密码至少 8 位';
    if (password != confirm) return '两次输入的密码不一致';

    final salt = _generateSalt();
    final hash = _deriveHash(password, salt);
    _password = password;
    _passwordHash = hash;
    _salt = salt;
    enabled = true;
    await _persistMeta(storage);
    return null;
  }

  /// 验证密码（解锁或关闭加密时）
  ///
  /// 返回 null 表示密码正确，否则返回错误提示
  static Future<String?> verifyPassword(String password, StorageService storage) async {
    final h = _deriveHash(password, _salt);
    if (h != _passwordHash) return '密码错误';
    _password = password;
    enabled = true;
    await _persistMeta(storage);
    return null;
  }

  /// 修改密码
  static Future<String?> changePassword(String oldPassword, String newPassword, String confirm, StorageService storage) async {
    final verifyResult = await verifyPassword(oldPassword, storage);
    if (verifyResult != null) return verifyResult;
    if (newPassword.length < 8) return '新密码至少 8 位';
    if (newPassword != confirm) return '两次输入的新密码不一致';
    return await setPassword(newPassword, confirm, storage);
  }

  /// 关闭加密：将加密的 drafts.json 解密回明文 drafts.json
  static Future<String?> disable(StorageService storage) async {
    if (_password == null) return '请先输入当前密码';
    try {
      final root = await storage.root;
      final encFile = File('${root.path}/${StorageService.encDraftsFile}');
      final plainFile = File('${root.path}/${StorageService.draftsFile}');
      if (await encFile.exists()) {
        final encText = await encFile.readAsString();
        if (encText.trim().isNotEmpty) {
          final plain = SiteEncryptionService.decrypt(encText.trim(), _password!);
          await plainFile.writeAsString(plain, flush: true);
        }
        // 保留加密文件作为备份
        await encFile.rename('${encFile.path}.bak');
      }
      enabled = false;
      _password = null;
      _passwordHash = '';
      _salt = '';
      await _persistMeta(storage);
      return null;
    } catch (e) {
      debugPrint('DraftEncryption: disable error: $e');
      return '关闭加密失败：$e';
    }
  }

  /// 对明文 JSON 加密（saveDrafts 钩子）
  static String? encryptJson(String plainJson) {
    if (!enabled || _password == null) return null;
    try {
      return SiteEncryptionService.encrypt(plainJson, _password!);
    } catch (e) {
      debugPrint('DraftEncryption: encrypt error: $e');
      return null;
    }
  }

  /// 对加密 JSON 解密（loadDrafts 钩子），返回明文，失败返回 null
  static String? decryptJson(String encJson) {
    if (!enabled || _password == null) return null;
    try {
      return SiteEncryptionService.decrypt(encJson, _password!);
    } catch (e) {
      debugPrint('DraftEncryption: decrypt error: $e');
      return null;
    }
  }

  // ── 内部工具 ──

  static String _generateSalt() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _deriveHash(String password, String salt) {
    // 用 SHA-256 组合 + 迭代（仅用于校验密码，不用于派生数据密钥）
    var h = '$salt|$password';
    for (int i = 0; i < 50000; i++) {
      h = _sha256Hex(h);
    }
    return h;
  }

  static String _sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static Future<void> _persistMeta(StorageService storage) async {
    try {
      final root = await storage.root;
      final f = File('${root.path}/$_metaFile');
      final data = jsonEncode({
        'enabled': enabled,
        'passwordHash': _passwordHash,
        'salt': _salt,
      });
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('DraftEncryption: persist meta error: $e');
    }
  }

  /// 加密 drafts.json → drafts.json.enc（开启加密时调用）
  static Future<void> encryptExistingDrafts(StorageService storage) async {
    try {
      final root = await storage.root;
      final plainFile = File('${root.path}/${StorageService.draftsFile}');
      final encFile = File('${root.path}/${StorageService.encDraftsFile}');
      if (!await plainFile.exists()) return;
      final text = await plainFile.readAsString();
      if (text.trim().isEmpty || _password == null) return;
      final enc = SiteEncryptionService.encrypt(text.trim(), _password!);
      await encFile.writeAsString(enc, flush: true);
      // 保留明文备份，避免写入失败时数据丢失
      if (await plainFile.exists()) {
        await plainFile.rename('${plainFile.path}.bak');
      }
    } catch (e) {
      debugPrint('DraftEncryption: encrypt existing error: $e');
    }
  }

  /// 解密 drafts.json.enc → drafts.json（解锁成功时调用）
  static Future<void> decryptExistingDrafts(StorageService storage) async {
    try {
      final root = await storage.root;
      final encFile = File('${root.path}/${StorageService.encDraftsFile}');
      final plainFile = File('${root.path}/${StorageService.draftsFile}');
      if (!await encFile.exists() || _password == null) return;
      final enc = await encFile.readAsString();
      if (enc.trim().isEmpty) return;
      final plain = SiteEncryptionService.decrypt(enc.trim(), _password!);
      await plainFile.writeAsString(plain, flush: true);
      // 解密成功后移除加密文件，避免下次启动仍被当作加密态回读；
      // 保留 .enc.bak 以便明文写入异常时人工恢复
      try {
        await encFile.rename('${encFile.path}.bak');
      } catch (e) {
        debugPrint('DraftEncryption: rename enc backup failed: $e');
      }
    } catch (e) {
      debugPrint('DraftEncryption: decrypt existing error: $e');
    }
  }
}
