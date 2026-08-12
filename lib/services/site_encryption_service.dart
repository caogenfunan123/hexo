/// 站点加密服务
/// 使用 AES-256-GCM 对站点文件进行独立加密
///
/// 对标：Yank Note .c.md 加密方案
/// 流程：KDF 派生密钥 → AES-256-GCM 加密 → 保存加密文件
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 站点加密服务
class SiteEncryptionService {
  static const int _saltLength = 16;
  static const int _ivLength = 12;
  static const int _tagLength = 16;
  static const int _keyLength = 32; // 256 bits
  static const int _pbkdf2Iterations = 100000;

  /// 从密码派生密钥（使用 UTF-8 字节，保证非 ASCII 密码跨端一致）
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// 生成随机字节
  static Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  /// 加密文本
  ///
  /// [plainText] 明文内容
  /// [password] 加密密码
  /// 返回 Base64 编码的加密数据（salt + iv + ciphertext + tag）
  static String encrypt(String plainText, String password) {
    final salt = _generateRandomBytes(_saltLength);
    final key = _deriveKey(password, salt);
    final iv = _generateRandomBytes(_ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagLength * 8, iv, Uint8List(0)),
      );

    final plainBytes = Uint8List.fromList(utf8.encode(plainText));
    final encrypted = cipher.process(plainBytes);

    // 合并：salt + iv + ciphertext
    final result = Uint8List(salt.length + iv.length + encrypted.length);
    result.setAll(0, salt);
    result.setAll(salt.length, iv);
    result.setAll(salt.length + iv.length, encrypted);

    return base64.encode(result);
  }

  /// 解密文本
  ///
  /// [encryptedBase64] Base64 编码的加密数据
  /// [password] 解密密码
  /// 返回解密后的明文
  static String decrypt(String encryptedBase64, String password) {
    final data = base64.decode(encryptedBase64);
    final minLen = _saltLength + _ivLength + _tagLength;
    if (data.length < minLen) {
      throw ArgumentError('加密数据长度不足，可能已损坏');
    }

    final salt = data.sublist(0, _saltLength);
    final iv = data.sublist(_saltLength, _saltLength + _ivLength);
    final ciphertext = data.sublist(_saltLength + _ivLength);

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _tagLength * 8, iv, Uint8List(0)),
      );

    final decrypted = cipher.process(ciphertext);
    return utf8.decode(decrypted);
  }

  /// 加密文件
  ///
  /// [filePath] 文件路径
  /// [password] 加密密码
  /// 加密后的文件保存为 .c.md 扩展名
  static Future<String> encryptFile(String filePath, String password) async {
    final file = await _readFile(filePath);
    final encrypted = encrypt(file, password);
    final encryptedPath = filePath.replaceAll('.md', '.c.md');
    await _writeFile(encryptedPath, encrypted);
    return encryptedPath;
  }

  /// 解密文件
  ///
  /// [encryptedPath] 加密文件路径（.c.md）
  /// [password] 解密密码
  /// 返回解密后的明文内容
  static Future<String> decryptFile(String encryptedPath, String password) async {
    final encrypted = await _readFile(encryptedPath);
    return decrypt(encrypted, password);
  }

  /// 验证密码是否正确
  ///
  /// [encryptedPath] 加密文件路径
  /// [password] 待验证密码
  static Future<bool> verifyPassword(String encryptedPath, String password) async {
    try {
      await decryptFile(encryptedPath, password);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _readFile(String path) async {
    final file = await _getFile(path);
    return file;
  }

  static Future<void> _writeFile(String path, String content) async {
    await File(path).writeAsString(content);
  }

  static Future<String> _getFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    return file.readAsString();
  }
}