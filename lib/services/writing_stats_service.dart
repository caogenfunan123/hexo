/// 写作统计服务：字数统计、按日写作历史、连续写作天数
///
/// 数据来源：drafts 列表（Article.updatedAt / content）+ 持久化写作日志。
/// 写作日志记录每日总字数（增量累加），用于计算连续写作天数与历史趋势。
library;

import 'dart:convert';
import 'dart:io';

import '../models/article.dart';

/// 单日写作记录
class WritingDayStat {
  final String dateKey; // yyyy-MM-dd
  final int wordCount; // 当日累计写入字数
  final DateTime date;

  const WritingDayStat({
    required this.dateKey,
    required this.wordCount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'date': dateKey,
        'count': wordCount,
      };

  factory WritingDayStat.fromJson(Map<String, dynamic> j) {
    final key = j['date']?.toString() ?? '';
    return WritingDayStat(
      dateKey: key,
      wordCount: (j['count'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse(key) ?? DateTime.now(),
    );
  }
}

/// 写作统计聚合结果
class WritingStats {
  final int totalWords; // 全部草稿总字数
  final int todayWords; // 今日写入字数
  final int todayDrafts; // 今日更新的草稿数
  final int streakDays; // 连续写作天数
  final List<WritingDayStat> history; // 最近 N 天历史

  const WritingStats({
    required this.totalWords,
    required this.todayWords,
    required this.todayDrafts,
    required this.streakDays,
    required this.history,
  });
}

/// 写作统计服务
class WritingStatsService {
  static const _file = 'writing_stats.json';

  final Directory _root;
  List<WritingDayStat> _days = [];

  WritingStatsService(this._root);

  Future<void> load() async {
    try {
      final f = File('${_root.path}/$_file');
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        _days = data
            .whereType<Map>()
            .map((e) => WritingDayStat.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = File('${_root.path}/$_file');
      final tmp = File('${f.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _days.map((d) => d.toJson()).toList(),
        ),
      );
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// 记录今日新增字数（增量累加）
  Future<void> recordTodayWords(int addedWords) async {
    if (addedWords <= 0) return;
    final today = _dateKey(DateTime.now());
    final idx = _days.indexWhere((d) => d.dateKey == today);
    if (idx >= 0) {
      final old = _days[idx];
      _days[idx] = WritingDayStat(
        dateKey: today,
        wordCount: old.wordCount + addedWords,
        date: DateTime.now(),
      );
    } else {
      _days.insert(
        0,
        WritingDayStat(
          dateKey: today,
          wordCount: addedWords,
          date: DateTime.now(),
        ),
      );
    }
    _days.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    // 仅保留最近 180 天
    if (_days.length > 180) {
      _days = _days.sublist(0, 180);
    }
    await _save();
  }

  /// 计算统计
  WritingStats compute(List<Article> drafts) {
    final now = DateTime.now();
    final todayKey = _dateKey(now);

    int totalWords = 0;
    int todayWords = 0;
    int todayDrafts = 0;

    for (final a in drafts) {
      final content = a.content;
      final len = countWords(content);
      totalWords += len;
      if (_dateKey(a.updatedAt) == todayKey) {
        todayWords += len;
        todayDrafts++;
      }
    }

    // 合并持久化日志：今日字数以日志为准（更准确反映增量写入），
    // 无日志时以草稿重算兜底。
    WritingDayStat? todayLog;
    for (final d in _days) {
      if (d.dateKey == todayKey) {
        todayLog = d;
        break;
      }
    }
    if (todayLog != null && todayLog.wordCount > 0) {
      todayWords = todayLog.wordCount;
    }

    // 连续写作天数：从今天（或昨天）往前数，日期连续
    int streak = 0;
    final daySet = _days.map((d) => d.dateKey).toSet();
    if (daySet.isEmpty) {
      streak = todayDrafts > 0 ? 1 : 0;
    } else {
      var cursor = DateTime(now.year, now.month, now.day);
      if (!daySet.contains(_dateKey(cursor))) {
        cursor = cursor.subtract(const Duration(days: 1));
      }
      while (daySet.contains(_dateKey(cursor))) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      if (streak == 0 && todayDrafts > 0) streak = 1;
    }

    return WritingStats(
      totalWords: totalWords,
      todayWords: todayWords,
      todayDrafts: todayDrafts,
      streakDays: streak,
      history: List.unmodifiable(_days),
    );
  }

  /// 统计字数：中文按字符、英文按单词
  /// 先剥离 Markdown 语法（代码块/行内代码/链接/图片/强调/标题/分隔线），
  /// 避免符号被计入。
  static int countWords(String text) {
    if (text.isEmpty) return 0;
    var t = text;
    // 移除代码块
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    t = t.replaceAll(RegExp(r'`[^`\n]*`'), ' ');
    // 移除图片/链接，仅保留其文本（alt/文字）
    t = t.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');
    t = t.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    // 移除行首标题井号与分隔线
    t = t.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^(\s*[-*_]\s*){3,}$', multiLine: true), '');
    // 移除强调/删除线符号
    t = t.replaceAll(RegExp(r'\*\*|__|\*|_|~~|`'), ' ');
    // 移除 HTML 标签
    t = t.replaceAll(RegExp(r'<[^>]*>'), ' ');

    final cn = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');
    final cnCount = cn.allMatches(t).length;
    final en = t
        .replaceAll(cn, ' ')
        .replaceAll(RegExp(r'[^\x00-\x7F]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return cnCount + en.length;
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
