import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexo/models/article.dart';
import 'package:hexo/services/writing_stats_service.dart';

void main() {
  group('WritingStatsService', () {
    test('countWords should count Chinese chars and English words', () {
      expect(WritingStatsService.countWords(''), 0);
      expect(WritingStatsService.countWords('hello world'), 2);
      expect(WritingStatsService.countWords('你好世界'), 4);
      expect(WritingStatsService.countWords('你好 world'), 3);
    });

    test('should track today words and total', () {
      final service = WritingStatsService(Directory.systemTemp.createTempSync('ws_test'));
      final now = DateTime.now();
      final draft = Article(
        id: '1',
        title: 't',
        content: '今天写了一些内容',
        createdAt: now,
        updatedAt: now,
      );
      final stats = service.compute([draft]);
      expect(stats.todayWords, greaterThanOrEqualTo(7));
      expect(stats.todayDrafts, 1);
      expect(stats.totalWords, greaterThanOrEqualTo(7));
      expect(stats.streakDays, greaterThanOrEqualTo(1));
    });
  });
}
