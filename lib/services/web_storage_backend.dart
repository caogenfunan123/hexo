import 'web_storage_impl_stub.dart'
    if (dart.library.html) 'web_storage_impl_web.dart' as impl;

/// Web 平台 localStorage 文本读写。
///
/// StorageService 在 kIsWeb 时通过这套函数持久化 JSON 文件内容，
/// 彻底绕开 dart:io 的 File/Directory（浏览器环境不可用）。
/// 非 Web 平台编译为 no-op（实际文件读写走 dart:io 路径）。

String? webStorageRead(String key) => impl.webStorageRead(key);

void webStorageWrite(String key, String value) =>
    impl.webStorageWrite(key, value);

void webStorageRemove(String key) => impl.webStorageRemove(key);