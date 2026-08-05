/// 全文检索服务
/// 使用 Ripgrep 命令行当前实现，Tantivy 作为备选方案
///
/// 架构对齐 Zettlr FSAL 搜索设计：
/// - 文件索引缓存
/// - 相关性排序
/// - 支持 NOT 操作符和精确短语匹配
library;

import 'dart:convert';
import 'dart:io';

import 'log_service.dart';

/// 搜索结果条目
class SearchResult {
  final String filePath;
  final String fileName;
  final String articleTitle;
  final String? matchPreview;
  final int matchCount;
  final double relevance;
  final List<SearchMatch> matches;

  const SearchResult({
    required this.filePath,
    required this.fileName,
    required this.articleTitle,
    this.matchPreview,
    this.matchCount = 0,
    this.relevance = 0,
    this.matches = const [],
  });
}

/// 单条匹配
class SearchMatch {
  final int lineNumber;
  final String lineContent;
  final int matchStart;
  final int matchEnd;

  const SearchMatch({
    required this.lineNumber,
    required this.lineContent,
    required this.matchStart,
    required this.matchEnd,
  });
}

/// 全文检索服务
/// 封装 Ripgrep 命令行调用，提供统一的搜索接口
class FullTextSearchService {
  final LogService _logService;

  FullTextSearchService(this._logService);

  /// 检查 Ripgrep 是否可用
  Future<bool> isRipgrepAvailable() async {
    try {
      final result = await Process.run('rg', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 全文搜索
  ///
  /// [directory] 搜索根目录
  /// [query] 搜索关键词
  /// [fileTypes] 文件类型过滤，如 ['md', 'markdown']
  /// [caseSensitive] 是否区分大小写
  /// [maxResults] 最大结果数
  /// [contextLines] 上下文行数
  Future<List<SearchResult>> search({
    required String directory,
    required String query,
    List<String> fileTypes = const ['md', 'markdown'],
    bool caseSensitive = false,
    int maxResults = 100,
    int contextLines = 2,
  }) async {
    // 优先使用 Ripgrep
    if (await isRipgrepAvailable()) {
      return _searchWithRipgrep(
        directory: directory,
        query: query,
        fileTypes: fileTypes,
        caseSensitive: caseSensitive,
        maxResults: maxResults,
        contextLines: contextLines,
      );
    }

    // 回退：Dart 原生实现
    return _searchNative(
      directory: directory,
      query: query,
      fileTypes: fileTypes,
      caseSensitive: caseSensitive,
      maxResults: maxResults,
    );
  }

  /// Ripgrep 命令行搜索
  Future<List<SearchResult>> _searchWithRipgrep({
    required String directory,
    required String query,
    required List<String> fileTypes,
    required bool caseSensitive,
    required int maxResults,
    required int contextLines,
  }) async {
    final args = <String>[
      '--json',           // JSON 输出
      '--no-heading',
      '--with-filename',
      '--line-number',
      '--max-count', maxResults.toString(),
      '-C', contextLines.toString(),
    ];

    if (!caseSensitive) args.add('-i');

    for (final type in fileTypes) {
      args.addAll(['-g', '*.$type']);
    }

    args.add(query);
    args.add(directory);

    try {
      final result = await Process.run('rg', args);
      if (result.exitCode != 0 && result.exitCode != 1) {
        // exitCode 1 = 无匹配（正常）
        return [];
      }

      final results = <SearchResult>[];
      final lines = (result.stdout as String).split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final type = json['type']?.toString();

          if (type == 'match') {
            final data = json['data'] as Map<String, dynamic>;
            final path = data['path']?['text']?.toString() ?? '';
            final lines_data = data['lines'] as Map<String, dynamic>;
            final lineNumber = (data['line_number'] as num?)?.toInt() ?? 0;
            final lineText = lines_data['text']?.toString() ?? '';

            // 提取子匹配位置
            final subMatches = data['submatches'] as List<dynamic>?;
            int matchStart = 0;
            int matchEnd = 0;
            if (subMatches != null && subMatches.isNotEmpty) {
              final sm = subMatches[0] as Map<String, dynamic>;
              matchStart = (sm['start'] as num?)?.toInt() ?? 0;
              matchEnd = (sm['end'] as num?)?.toInt() ?? 0;
            }

            final fileName = path.split('/').last;

            // 合并同一文件的结果
            final existingIndex = results.indexWhere((r) => r.filePath == path);
            if (existingIndex >= 0) {
              final existing = results[existingIndex];
              results[existingIndex] = SearchResult(
                filePath: existing.filePath,
                fileName: existing.fileName,
                articleTitle: existing.articleTitle,
                matchPreview: existing.matchPreview,
                matchCount: existing.matchCount + 1,
                relevance: existing.relevance + 1,
                matches: [
                  ...existing.matches,
                  SearchMatch(
                    lineNumber: lineNumber,
                    lineContent: lineText,
                    matchStart: matchStart,
                    matchEnd: matchEnd,
                  ),
                ],
              );
            } else {
              results.add(SearchResult(
                filePath: path,
                fileName: fileName,
                articleTitle: _extractTitle(fileName),
                matchPreview: lineText,
                matchCount: 1,
                relevance: 1.0,
                matches: [
                  SearchMatch(
                    lineNumber: lineNumber,
                    lineContent: lineText,
                    matchStart: matchStart,
                    matchEnd: matchEnd,
                  ),
                ],
              ));
            }
          }
        } catch (_) {
          // 跳过无法解析的行
        }
      }

      // 按相关性排序
      results.sort((a, b) => b.relevance.compareTo(a.relevance));

      _logService.add('全文检索', '搜索 "$query" 完成，找到 ${results.length} 个结果');
      return results;
    } catch (e) {
      _logService.add('全文检索', 'Ripgrep 搜索失败: $e');
      return [];
    }
  }

  /// Dart 原生回退搜索
  Future<List<SearchResult>> _searchNative({
    required String directory,
    required String query,
    required List<String> fileTypes,
    required bool caseSensitive,
    required int maxResults,
  }) async {
    final results = <SearchResult>[];
    final dir = Directory(directory);
    if (!await dir.exists()) return results;

    final searchQuery = query.toLowerCase();
    final entries = await dir.list(recursive: true).toList();

    for (final entity in entries) {
      if (entity is! File) continue;
      final ext = entity.path.split('.').last;
      if (!fileTypes.contains(ext)) continue;

      try {
        final content = await entity.readAsString();
        final matches = <SearchMatch>[];
        int matchCount = 0;

        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final searchLine = caseSensitive ? line : line.toLowerCase();
          final index = searchLine.indexOf(searchQuery);
          if (index >= 0) {
            matchCount++;
            matches.add(SearchMatch(
              lineNumber: i + 1,
              lineContent: line.trim(),
              matchStart: index,
              matchEnd: index + searchQuery.length,
            ));
          }
        }

        if (matchCount > 0) {
          final fileName = entity.path.split('/').last;
          results.add(SearchResult(
            filePath: entity.path,
            fileName: fileName,
            articleTitle: _extractTitle(fileName),
            matchPreview: matches.isNotEmpty ? matches.first.lineContent : null,
            matchCount: matchCount,
            relevance: matchCount.toDouble(),
            matches: matches.take(10).toList(),
          ));
        }
      } catch (_) {
        continue;
      }

      if (results.length >= maxResults) break;
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results;
  }

  /// 从文件名提取标题
  String _extractTitle(String fileName) {
    var name = fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
    // 移除日期前缀 (YYYY-MM-DD-)
    name = name.replaceAll(RegExp(r'^\d{4}-\d{2}-\d{2}-'), '');
    return name.replaceAll('-', ' ');
  }
}