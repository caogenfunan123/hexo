// 非 Web 平台编译目标：全部 no-op。
// StorageService 只在 kIsWeb 时调用这些函数，IO 平台永不触达。

String? webStorageRead(String key) => null;

void webStorageWrite(String key, String value) {}

void webStorageRemove(String key) {}