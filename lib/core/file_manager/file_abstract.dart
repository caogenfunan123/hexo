/// 文件实体
class FileEntity {
  final String name;
  final String path; // 相对路径
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? lastModified;

  const FileEntity({
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.sizeBytes,
    this.lastModified,
  });
}

/// 应用文件操作抽象接口
/// 【核心规则】所有业务代码只调用此接口，不感知底层是安卓沙盒还是桌面本地磁盘
/// 【强制工程细则1】Android 11+ 分区存储适配
abstract class AppFileOperator {
  /// 读取文件内容（相对路径）
  Future<String> readFile(String relativePath);

  /// 写入文件内容（相对路径），自动创建父目录
  Future<void> writeFile(String relativePath, String content);

  /// 写入二进制文件
  Future<void> writeBinaryFile(String relativePath, List<int> bytes);

  /// 删除文件
  Future<void> deleteFile(String relativePath);

  /// 检查文件是否存在
  Future<bool> exists(String relativePath);

  /// 列出目录内容
  Future<List<FileEntity>> listDirectory(String relativePath);

  /// 创建目录（递归）
  Future<void> createDirectory(String relativePath);

  /// 获取文件的绝对路径（平台层实现）
  Future<String> getAbsolutePath(String relativePath);

  /// 获取根目录路径
  Future<String> getRootPath();

  /// 是否使用分区存储（Android 11+ 自动检测）
  /// 桌面端返回 false
  bool isScopedStorageRequired() => false;

  /// 导出文件到用户可访问的公共目录
  /// 仅在 Android 11+ 上需要 SAF/MediaStore
  /// 桌面端直接复制到目标路径
  Future<String?> exportToUserDirectory(String relativePath, {String? exportName});

  /// 获取内部存储路径（应用私有目录，非用户可见）
  Future<String> getInternalStoragePath() async => getRootPath();

  /// 获取导出目录（用户可见的公共目录，桌面端同 rootPath）
  Future<String> getExportDirectory() async => getRootPath();

  /// 读取二进制文件（相对路径）
  Future<List<int>> readBinaryFile(String relativePath) async {
    try {
      final root = await getRootPath();
      final file = File('$root/$relativePath');
      if (!await file.exists()) {
        throw FileSystemException('File not found', relativePath);
      }
      return await file.readAsBytes();
    } catch (e) {
      rethrow;
    }
  }

  /// 复制文件
  Future<void> copyFile(String sourcePath, String destPath) async {
    final content = await readFile(sourcePath);
    await writeFile(destPath, content);
  }

  /// 移动文件
  Future<void> moveFile(String sourcePath, String destPath) async {
    await copyFile(sourcePath, destPath);
    await deleteFile(sourcePath);
  }

  /// 获取当前平台的 Android SDK 版本号
  ///
  /// 返回 0 表示非 Android 平台或无法获取。
  /// Android 各版本对应关系：
  /// - SDK 29 = Android 10 (分区存储可选，支持 requestLegacyExternalStorage)
  /// - SDK 30 = Android 11 (强制分区存储)
  /// - SDK 31 = Android 12
  /// - SDK 33 = Android 13
  Future<int> getSdkVersion() async => 0;