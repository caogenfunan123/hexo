import 'dart:html' show window;

/// 通过 dart:html 的 window.localStorage 读写。
/// 仅在 Flutter Web 构建时编译。

String? webStorageRead(String key) => window.localStorage[key];

void webStorageWrite(String key, String value) {
  window.localStorage[key] = value;
}

void webStorageRemove(String key) {
  window.localStorage.remove(key);
}