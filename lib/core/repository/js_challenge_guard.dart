import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// slowAES JS 反爬挑战处理
///
/// 部分托管平台 / 安全插件会在站点前置一层 JS 反爬挑战
/// （如 `aes.js` + slowAES 解密），所有请求（含 /wp-json、wp-login.php）
/// 首次返回一段 HTML，要求浏览器执行 JS 计算出 `__test` cookie 后重定向。
///
/// 本类负责：
/// 1. 识别 slowAES 挑战响应
/// 2. 用 AES-128-CBC 解密出 `__test` cookie 值（slowAES.decrypt(c,2,a,b)）
/// 3. 缓存 cookie，带 cookie 重发请求
class JsChallengeGuard {
  /// 匹配挑战页中的 32 位 hex 参数（a=key, b=iv, c=ciphertext）
  static final RegExp _hexNumber = RegExp(r'toNumbers\("([0-9a-f]{32})"\)');

  /// 判断响应是否为 slowAES 挑战页
  static bool isChallenge(String body) {
    return body.contains('slowAES') && body.contains('document.cookie');
  }

  /// 从挑战页求解 `__test` cookie 值（不含 `__test=` 前缀）
  ///
  /// 挑战页示例：
  /// ```
  /// var a=toNumbers("f655...b4"),b=toNumbers("9834...80"),c=toNumbers("4c7a...b5")
  /// document.cookie="__test="+toHex(slowAES.decrypt(c,2,a,b))+"; max-age=21600;..."
  /// ```
  /// 无法求解时返回 null。
  static String? solve(String html) {
    final matches =
        _hexNumber.allMatches(html).map((m) => m.group(1)!).toList();
    if (matches.length < 3) return null;

    final key = _hexToBytes(matches[0]);
    final iv = _hexToBytes(matches[1]);
    final ct = _hexToBytes(matches[2]);
    if (key.length != 16 || iv.length != 16 || ct.length != 16) return null;

    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));

    final out = Uint8List(ct.length);
    cipher.processBlock(ct, 0, out, 0);
    return _bytesToHex(out);
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 统一 HTTP 响应结果
class JsResponse {
  final int statusCode;
  final String text;

  const JsResponse(this.statusCode, this.text);

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// 带 slowAES 挑战自动处理的 HTTP 客户端
///
/// 请求流程：
/// 1. 若已缓存该 host 的有效 cookie，带上 `Cookie: __test=...`
/// 2. 响应若为挑战页，求解 cookie 并带 cookie 重发一次
/// 3. 返回最终响应
class JsChallengeHttp {
  final HttpClient _client;

  /// host -> (cookie, 过期时间)
  final Map<String, ({String cookie, DateTime expires})> _cookieCache = {};

  JsChallengeHttp(this._client);

  /// 发送请求，自动处理 slowAES 反爬挑战
  Future<JsResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    List<int>? rawBody,
    int? contentLength,
  }) async {
    var resp = await _once(
      method,
      uri,
      headers: headers,
      body: body,
      rawBody: rawBody,
      contentLength: contentLength,
    );

    // 响应为挑战页 → 求解 cookie 并带 cookie 重试
    if (JsChallengeGuard.isChallenge(resp.text)) {
      final cookie = JsChallengeGuard.solve(resp.text);
      if (cookie != null) {
        _setCookie(uri.host, cookie);
        resp = await _once(
          method,
          uri,
          headers: headers,
          body: body,
          rawBody: rawBody,
          contentLength: contentLength,
        );
      }
    }
    return resp;
  }

  Future<JsResponse> _once(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    List<int>? rawBody,
    int? contentLength,
  }) async {
    final req = switch (method) {
      'POST' => await _client.postUrl(uri),
      'PUT' => await _client.putUrl(uri),
      'DELETE' => await _client.deleteUrl(uri),
      _ => await _client.getUrl(uri),
    };

    headers?.forEach((k, v) => req.headers.set(k, v));

    final cookie = _cookieFor(uri.host);
    if (cookie != null) {
      req.headers.set('Cookie', '__test=$cookie');
    }

    if (rawBody != null) {
      if (contentLength != null) req.contentLength = contentLength;
      req.add(rawBody);
    } else if (body != null) {
      req.write(body);
    }

    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    return JsResponse(response.statusCode, text);
  }

  /// 获取指定 host 的有效 cookie，过期则清除
  String? _cookieFor(String host) {
    final entry = _cookieCache[host];
    if (entry == null) return null;
    if (!entry.expires.isAfter(DateTime.now())) {
      _cookieCache.remove(host);
      return null;
    }
    return entry.cookie;
  }

  void _setCookie(String host, String cookie) {
    // 挑战页 cookie max-age=21600（6 小时）
    _cookieCache[host] = (
      cookie: cookie,
      expires: DateTime.now().add(const Duration(hours: 6)),
    );
  }
}
