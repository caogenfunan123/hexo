/// 全文检索 Isolate 隔离服务
/// 在独立 Isolate 中执行搜索，避免阻塞 UI 线程
///
/// 参考：tantivy-dart (https://github.com/quickwit-oss/tantivy-dart) 移动端内置全文检索
/// 参考：ripgrep (https://github.com/BurntSushi/ripgrep) 二进制预编译
library;

import 'dart:async';
import 'dart:isolate';

import 'full_text_search_service.dart';
import 'log_service.dart';

// ──────────────────────────────────────────────────────────────
// Isolate 通信数据结构（必须为可序列化的简单类型）
// ──────────────────────────────────────────────────────────────

/// 搜索进度状态
enum SearchProgress {
  /// Isolate 已启动，准备开始搜索
  started,

  /// 正在执行搜索（ripgrep 或原生回退）
  searching,

  /// 搜索完成，结果已返回
  done,

  /// 搜索过程中发生错误
  error,
}

/// Isolate 搜索参数
///
/// 所有字段必须为可跨 Isolate 边界传递的基本类型。
class _SearchParams {
  final String directory;
  final String query;
  final List<String> fileTypes;
  final bool caseSensitive;
  final int maxResults;
  final int contextLines;
  final SendPort resultPort;
  final SendPort? progressPort;

  const _SearchParams({
    required this.directory,
    required this.query,
    required this.fileTypes,
    required this.caseSensitive,
    required this.maxResults,
    required this.contextLines,
    required this.resultPort,
    this.progressPort,
  });
}

// ──────────────────────────────────────────────────────────────
// Isolate 入口函数
// ──────────────────────────────────────────────────────────────

/// Isolate 入口：执行全文搜索
///
/// 在独立 Isolate 中实例化 [FullTextSearchService] 并执行搜索。
/// 结果通过 [resultPort] 发送回主 Isolate，进度通过 [progressPort] 发送。
void _executeSearch(_SearchParams params) async {
  try {
    params.progressPort?.send(SearchProgress.started);

    // 在 Isolate 中创建独立的服务实例（Isolate 不共享内存）
    final logService = LogService();
    final searchService = FullTextSearchService(logService);

    params.progressPort?.send(SearchProgress.searching);

    final results = await searchService.search(
      directory: params.directory,
      query: params.query,
      fileTypes: params.fileTypes,
      caseSensitive: params.caseSensitive,
      maxResults: params.maxResults,
      contextLines: params.contextLines,
    );

    // 按相关性排序后返回结果
    results.sort((a, b) => b.relevance.compareTo(a.relevance));

    params.progressPort?.send(SearchProgress.done);
    params.resultPort.send(results);
  } catch (e) {
    params.progressPort?.send(SearchProgress.error);
    // 发送空列表而非异常，避免 Isolate 崩溃影响主线程
    params.resultPort.send(<SearchResult>[]);
  }
}

// ──────────────────────────────────────────────────────────────
// 公开 API
// ──────────────────────────────────────────────────────────────

/// 全文检索 Isolate 隔离包装器
///
/// 将 [FullTextSearchService] 的搜索逻辑放到独立 Isolate 中执行，
/// 避免 Ripgrep 进程调用或大规模文件遍历阻塞 UI 线程。
///
/// 使用方式：
/// ```dart
/// final searchIsolate = FullTextSearchIsolate(logService);
/// final results = await searchIsolate.search(
///   directory: '/path/to/posts',
///   query: 'flutter',
///   onProgress: (progress) => print('Search: $progress'),
/// );
/// ```
///
/// 支持取消操作：
/// ```dart
/// searchIsolate.cancel(); // 立即终止当前搜索
/// ```
class FullTextSearchIsolate {
  final LogService _logService;

  /// 当前正在运行的搜索 Isolate
  Isolate? _currentIsolate;

  /// 取消标志，用于超时或手动取消后的状态同步
  bool _cancelled = false;

  FullTextSearchIsolate(this._logService);

  /// 取消当前正在进行的搜索
  ///
  /// 立即终止 Isolate 并清理资源。已取消的搜索返回空结果列表。
  void cancel() {
    _cancelled = true;
    _currentIsolate?.kill(priority: Isolate.immediate);
    _currentIsolate = null;
    _logService.add('全文检索(Isolate)', '搜索已取消', success: true);
  }

  /// 是否有正在进行的搜索
  bool get isSearching => _currentIsolate != null;

  /// 在独立 Isolate 中执行全文搜索
  ///
  /// [directory] 搜索根目录
  /// [query] 搜索关键词，支持正则表达式（由底层 Ripgrep 处理）
  /// [fileTypes] 文件类型过滤，如 ['md', 'markdown']
  /// [caseSensitive] 是否区分大小写
  /// [maxResults] 最大结果数
  /// [contextLines] 每条匹配的上下文行数
  /// [onProgress] 进度回调，在搜索过程中接收 [SearchProgress] 状态更新
  ///
  /// 返回按相关性降序排列的搜索结果列表。
  /// 如果搜索被取消或发生错误，返回空列表。
  Future<List<SearchResult>> search({
    required String directory,
    required String query,
    List<String> fileTypes = const ['md', 'markdown'],
    bool caseSensitive = false,
    int maxResults = 100,
    int contextLines = 2,
    void Function(SearchProgress progress)? onProgress,
  }) async {
    _cancelled = false;

    // 取消之前的搜索（如果存在）
    if (_currentIsolate != null) {
      _currentIsolate!.kill(priority: Isolate.immediate);
      _currentIsolate = null;
    }

    // 创建通信端口
    final resultPort = ReceivePort();
    ReceivePort? progressPort;

    // 仅在调用方需要进度回调时创建进度端口
    if (onProgress != null) {
      progressPort = ReceivePort();
      progressPort.listen((message) {
        if (message is SearchProgress) {
          onProgress(message);
        }
      });
    }

    final params = _SearchParams(
      directory: directory,
      query: query,
      fileTypes: fileTypes,
      caseSensitive: caseSensitive,
      maxResults: maxResults,
      contextLines: contextLines,
      resultPort: resultPort.sendPort,
      progressPort: progressPort?.sendPort,
    );

    _logService.add('全文检索(Isolate)', '开始在 Isolate 中搜索 "$query"');

    try {
      // 创建独立 Isolate 执行搜索
      _currentIsolate = await Isolate.spawn(_executeSearch, params);

      // 等待搜索结果（带超时保护）
      final completer = Completer<List<SearchResult>>();
      late StreamSubscription<dynamic> subscription;

      subscription = resultPort.listen((message) {
        if (!completer.isCompleted) {
          if (message is List<SearchResult>) {
            completer.complete(message);
          } else {
            completer.complete(<SearchResult>[]);
          }
        }
        subscription.cancel();
      });

      // 超时保护：30 秒后自动取消
      final results = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logService.add(
            '全文检索(Isolate)',
            '搜索超时，已自动取消',
            success: false,
          );
          cancel();
          return <SearchResult>[];
        },
      );

      if (_cancelled) {
        return <SearchResult>[];
      }

      _logService.add(
        '全文检索(Isolate)',
        '搜索 "$query" 完成，找到 ${results.length} 个结果',
      );
      return results;
    } catch (e) {
      if (_cancelled) {
        return <SearchResult>[];
      }
      _logService.add(
        '全文检索(Isolate)',
        '搜索失败: $e',
        success: false,
      );
      return <SearchResult>[];
    } finally {
      // 清理资源
      resultPort.close();
      progressPort?.close();
      _currentIsolate = null;
    }
  }

  /// 释放资源
  ///
  /// 取消正在进行的搜索并清理所有内部状态。
  void dispose() {
    cancel();
    _currentIsolate = null;
  }
}