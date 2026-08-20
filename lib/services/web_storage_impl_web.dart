import 'dart:js_interop';

/// 通过 dart:js_interop 访问浏览器 window.localStorage。

@JS('window.localStorage')
external JSObject get _localStorage;

extension _StorageExt on JSObject {
  external JSString? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

String? webStorageRead(String key) {
  final v = _localStorage.getItem(key);
  return v?.toDart;
}

void webStorageWrite(String key, String value) {
  _localStorage.setItem(key, value);
}

void webStorageRemove(String key) {
  _localStorage.removeItem(key);
}