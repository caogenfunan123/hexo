import '../core/repository/blog_repository.dart';
import '../models/blog_site_config.dart';

/// 远程分类/标签缓存条目
class TaxonomyCache {
  final String siteId;
  final List<String> categories;
  final List<String> tags;
  final DateTime fetchedAt;

  const TaxonomyCache({
    required this.siteId,
    required this.categories,
    required this.tags,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'siteId': siteId,
        'categories': categories,
        'tags': tags,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory TaxonomyCache.fromJson(Map<String, dynamic> j) {
    return TaxonomyCache(
      siteId: j['siteId']?.toString() ?? '',
      categories: (j['categories'] as List?)?.map((e) => e.toString()).toList() ?? [],
      tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      fetchedAt: DateTime.tryParse(j['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// 远程分类/标签本地缓存服务
///
/// 从 CMS 站点拉取已有的分类和标签，缓存到本地供编辑器自动补全使用。
/// 缓存过期时间：24 小时。
class TaxonomyCacheService {
  final Map<String, TaxonomyCache> _cache = {};
  static const _maxAge = Duration(hours: 24);

  /// 获取站点的分类列表（优先从缓存）
  Future<List<String>> getCategories(BlogSiteConfig config, BlogRepository adapter) async {
    final cache = _cache[config.id];
    if (cache != null && _isFresh(cache.fetchedAt)) {
      return cache.categories;
    }
    try {
      final posts = await adapter.getPosts(perPage: 50);
      final cats = <String>{};
      for (final post in posts) {
        cats.addAll(post.categories);
      }
      final tags = <String>{};
      for (final post in posts) {
        tags.addAll(post.tags);
      }
      _cache[config.id] = TaxonomyCache(
        siteId: config.id,
        categories: cats.toList()..sort(),
        tags: tags.toList()..sort(),
        fetchedAt: DateTime.now(),
      );
      return cats.toList()..sort();
    } catch (_) {
      return cache?.categories ?? [];
    }
  }

  /// 获取站点的标签列表（优先从缓存）
  Future<List<String>> getTags(BlogSiteConfig config, BlogRepository adapter) async {
    final cache = _cache[config.id];
    if (cache != null && _isFresh(cache.fetchedAt)) {
      return cache.tags;
    }
    try {
      final posts = await adapter.getPosts(perPage: 50);
      final tags = <String>{};
      for (final post in posts) {
        tags.addAll(post.tags);
      }
      final cats = <String>{};
      for (final post in posts) {
        cats.addAll(post.categories);
      }
      _cache[config.id] = TaxonomyCache(
        siteId: config.id,
        categories: cats.toList()..sort(),
        tags: tags.toList()..sort(),
        fetchedAt: DateTime.now(),
      );
      return tags.toList()..sort();
    } catch (_) {
      return cache?.tags ?? [];
    }
  }

  /// 清除站点缓存
  void clear(String siteId) {
    _cache.remove(siteId);
  }

  /// 清除所有缓存
  void clearAll() {
    _cache.clear();
  }

  bool _isFresh(DateTime fetched) {
    return DateTime.now().difference(fetched) < _maxAge;
  }
}