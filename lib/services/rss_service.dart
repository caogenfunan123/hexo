import 'dart:convert';
import 'dart:io';

class RssItem {
  final String title;
  final String link;
  final String description;
  final DateTime? pubDate;

  RssItem({
    required this.title,
    required this.link,
    required this.description,
    this.pubDate,
  });
}

class RssService {
  Future<List<RssItem>> fetch(String siteUrl) async {
    final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
    final candidates = [
      '$base/atom.xml',
      '$base/rss.xml',
      '$base/feed.xml',
      '$base/rss2.xml',
    ];
    Object? lastError;
    for (final url in candidates) {
      try {
        final xml = await _get(url);
        final items = _parse(xml);
        if (items.isNotEmpty) return items;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw Exception('RSS 获取失败: $lastError');
    return [];
  }

  Future<String> _get(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'HexoBlogManager');
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 200 && res.statusCode < 300) return text;
      throw Exception('HTTP ${res.statusCode}');
    } finally {
      client.close(force: true);
    }
  }

  List<RssItem> _parse(String xml) {
    final items = <RssItem>[];
    // RSS item
    final itemRe = RegExp(r'<item[\s>][\s\S]*?</item>', caseSensitive: false);
    final entryRe = RegExp(r'<entry[\s>][\s\S]*?</entry>', caseSensitive: false);
    final blocks = [...itemRe.allMatches(xml), ...entryRe.allMatches(xml)];
    for (final m in blocks) {
      final block = m.group(0) ?? '';
      final title = _tag(block, 'title');
      var link = _tag(block, 'link');
      if (link.isEmpty) {
        final lm = RegExp(r'<link[^>]*href=["' "'" r']([^"' "'" r']+)', caseSensitive: false)
            .firstMatch(block);
        link = lm?.group(1) ?? '';
      }
      final desc = _tag(block, 'description').isNotEmpty
          ? _tag(block, 'description')
          : _tag(block, 'summary').isNotEmpty
              ? _tag(block, 'summary')
              : _tag(block, 'content');
      final dateStr = _tag(block, 'pubDate').isNotEmpty
          ? _tag(block, 'pubDate')
          : _tag(block, 'updated').isNotEmpty
              ? _tag(block, 'updated')
              : _tag(block, 'published');
      items.add(RssItem(
        title: _strip(title),
        link: link,
        description: _strip(desc),
        pubDate: DateTime.tryParse(dateStr),
      ));
    }
    return items;
  }

  String _tag(String xml, String name) {
    final re = RegExp(
      '<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>',
      caseSensitive: false,
    );
    final m = re.firstMatch(xml);
    return m?.group(1)?.trim() ?? '';
  }

  String _strip(String s) => s
      .replaceAll(RegExp(r'<!\[CDATA\['), '')
      .replaceAll(']]>', '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}
