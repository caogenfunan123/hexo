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
}