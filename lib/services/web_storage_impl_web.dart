import 'dart:html' show window;

/// 访问浏览器 window.localStorage。key 已由调用方加好前缀。
String? webStorageRead(String key) {
  if (window.localStorage == null) return null;
  return window.localStorage![key];
}

void webStorageWrite(String key, String value) {
  window.localStorage?[key] = value;
}

void webStorageRemove(String key) {
  window.localStorage?.remove(key);
}