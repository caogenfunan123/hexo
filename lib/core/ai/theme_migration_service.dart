import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import '../../services/github_service.dart';
import 'ai_session_manager.dart';

/// 主题迁移服务：跨框架主题转换
class ThemeMigrationService {
  final AiService _aiService;

  ThemeMigrationService(this._aiService, GitHubService _);

  /// 分析主题源码，识别源框架
  Future<ThemeAnalysis> analyzeSource({
    required AppSettings settings,
    required String sourceCode, // 主题源码的目录结构描述
  }) async {
    final prompt = '''
分析以下主题源码的目录结构和关键文件，识别：
1. 原始框架类型（Hugo/Jekyll/Hexo/Astro/VuePress/Next.js/Gatsby/11ty/Pelican）
2. 模板语法类型
3. 配置文件格式
4. 目录结构特点
5. 关键文件清单

源码结构：
$sourceCode

请以 JSON 格式返回：
{
  "framework": "框架ID",
  "frameworkName": "框架名称",
  "templateSyntax": "模板语法",
  "configFormat": "配置格式",
  "directoryStructure": "目录结构描述",
  "keyFiles": ["文件1", "文件2"]
}
''';

    final result = await _aiService.complete(
      settings: settings,
      systemPrompt: AiSessionManager.themeAnalysisPrompt,
      userPrompt: prompt,
      temperature: 0.3,
    );

    try {
      final json = _extractJson(result);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return ThemeAnalysis(
        sourceFramework: map['framework']?.toString() ?? 'unknown',
        sourceFrameworkName: map['frameworkName']?.toString() ?? '未知',
        templateSyntax: map['templateSyntax']?.toString() ?? '',
        configFormat: map['configFormat']?.toString() ?? '',
        directoryStructure: map['directoryStructure']?.toString() ?? '',
        keyFiles: (map['keyFiles'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
    } catch (_) {
      return ThemeAnalysis(
        sourceFramework: 'unknown',
        sourceFrameworkName: '无法识别',
        templateSyntax: '',
        configFormat: '',
        directoryStructure: '',
        keyFiles: [],
      );
    }
  }

  /// 执行跨框架迁移转换
  Future<ThemeMigrationResult> migrate({
    required AppSettings settings,
    required String sourceFramework,
    required String targetFramework,
    required String sourceCode,
    required String themeName,
    String? additionalInstructions,
  }) async {
    final systemPrompt = AiSessionManager.getSystemPrompt(
      AiSessionType.themeMigration,
      targetFramework: targetFramework,
    );

    final userPrompt = '''
请将以下 $sourceFramework 主题源码转换为 $targetFramework 主题。

目标主题名称：$themeName
${additionalInstructions != null ? '额外要求：$additionalInstructions' : ''}

=== 源主题源码 ===
$sourceCode
=== 结束 ===

请输出：
1. 转换进度摘要
2. 文件对照表（源路径 → 目标路径）
3. 每个文件的完整源码（标注【文件路径】themes/$themeName/xxx）
4. 迁移报告：列出未完美兼容的代码片段
''';

    final result = await _aiService.complete(
      settings: settings,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.5,
    );

    // 解析 AI 输出，提取文件路径和内容
    final files = _parseFileOutput(result, themeName);

    return ThemeMigrationResult(
      rawOutput: result,
      files: files,
      themeName: themeName,
    );
  }

  /// 解析 AI 输出中的文件路径和内容
  List<ThemeFile> _parseFileOutput(String output, String themeName) {
    final files = <ThemeFile>[];
    final lines = output.split('\n');
    String? currentPath;
    StringBuffer? currentContent;
    String? currentLang;

    for (final line in lines) {
      // 匹配 【文件路径】themes/xxx/file.ext
      final pathMatch = RegExp(r'【文件路径】\s*(.+)').firstMatch(line);
      if (pathMatch != null) {
        // 保存上一个文件
        if (currentPath != null && currentContent != null) {
          files.add(ThemeFile(
            path: currentPath,
            content: currentContent.toString().trim(),
            language: currentLang ?? 'text',
          ));
        }
        currentPath = pathMatch.group(1)!.trim();
        currentContent = StringBuffer();
        currentLang = 'text';
        continue;
      }

      // 匹配 ```language 代码块开始
      final codeStart = RegExp(r'^```(\w+)?').firstMatch(line);
      if (codeStart != null && currentPath != null) {
        currentLang = codeStart.group(1) ?? 'text';
        continue;
      }

      // 匹配 ``` 代码块结束
      if (line.trim() == '```' && currentPath != null) {
        continue;
      }

      // 收集内容
      if (currentPath != null && currentContent != null) {
        currentContent.writeln(line);
      }
    }

    // 保存最后一个文件
    if (currentPath != null && currentContent != null) {
      files.add(ThemeFile(
        path: currentPath,
        content: currentContent.toString().trim(),
        language: currentLang ?? 'text',
      ));
    }

    return files;
  }

  String _extractJson(String text) {
    // 提取 JSON 块
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    final match = RegExp(r'```(?:json)?\s*\n([\s\S]*?)\n```').firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return text;
  }

  /// 通过 Git 克隆第三方主题仓库
  Future<String> cloneThemeRepo(String repoUrl, String tempDir) async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final result = await Process.run('git', ['clone', '--depth', '1', repoUrl, tempDir]);
    if (result.exitCode != 0) {
      throw Exception('克隆仓库失败: ${result.stderr}');
    }
    return tempDir;
  }

  /// 读取本地目录结构
  Future<String> readDirectoryStructure(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return '目录不存在';

    final buf = StringBuffer();
    await _listDir(dir, buf, '');
    return buf.toString();
  }

  Future<void> _listDir(Directory dir, StringBuffer buf, String prefix) async {
    final entities = await dir.list().toList();
    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return a.path.compareTo(b.path);
    });

    for (final entity in entities) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.git')) continue;
      if (name == 'node_modules') continue;

      if (entity is Directory) {
        buf.writeln('$prefix📁 $name/');
        await _listDir(entity, buf, '$prefix  ');
      } else if (entity is File) {
        final size = await entity.length();
        buf.writeln('$prefix📄 $name (${_formatSize(size)})');
      }
    }
  }

  /// 读取目录下所有文本文件内容
  Future<Map<String, String>> readAllTextFiles(String dirPath) async {
    final files = <String, String>{};
    await _readDir(Directory(dirPath), files, dirPath);
    return files;
  }

  Future<void> _readDir(Directory dir, Map<String, String> files, String basePath) async {
    final entities = await dir.list().toList();
    for (final entity in entities) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.git') || name == 'node_modules') continue;

      if (entity is Directory) {
        await _readDir(entity, files, basePath);
      } else if (entity is File) {
        // 只读取文本文件
        final ext = name.split('.').last.toLowerCase();
        const textExts = {
          'html', 'ejs', 'njk', 'liquid', 'md', 'yml', 'yaml', 'toml',
          'json', 'js', 'ts', 'jsx', 'tsx', 'css', 'scss', 'less',
          'xml', 'svg', 'txt', 'cfg', 'ini', 'conf', 'py', 'rb',
          'go', 'astro', 'vue', 'svelte', 'hbs', 'mustache', 'j2',
        };
        if (textExts.contains(ext) || name.contains('.')) {
          try {
            final content = await entity.readAsString();
            final relativePath = entity.path.substring(basePath.length + 1);
            files[relativePath] = content;
          } catch (_) {
            // 跳过二进制文件
          }
        }
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ThemeAnalysis {
  final String sourceFramework;
  final String sourceFrameworkName;
  final String templateSyntax;
  final String configFormat;
  final String directoryStructure;
  final List<String> keyFiles;

  const ThemeAnalysis({
    required this.sourceFramework,
    required this.sourceFrameworkName,
    required this.templateSyntax,
    required this.configFormat,
    required this.directoryStructure,
    required this.keyFiles,
  });
}

class ThemeMigrationResult {
  final String rawOutput;
  final List<ThemeFile> files;
  final String themeName;

  const ThemeMigrationResult({
    required this.rawOutput,
    required this.files,
    required this.themeName,
  });
}

class ThemeFile {
  final String path;
  final String content;
  final String language;

  const ThemeFile({
    required this.path,
    required this.content,
    this.language = 'text',
  });
}