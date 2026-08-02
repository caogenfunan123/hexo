import 'dart:convert';

import '../core/repository/blog_repository.dart';
import '../models/article.dart';
import '../models/blog_post.dart';
import '../models/blog_site_config.dart';
import 'log_service.dart';

/// 文章同步映射条目
/// 记录本地文章与远程文章的对应关系
class SyncMapping {
  final String localArticleId;
  final int remotePostId;
  final String siteId;
  final DateTime lastSyncAt;
  final DateTime? localModifiedAt; // 最后同步时本地修改时间
  final DateTime? remoteModifiedAt; // 最后同步时远程修改时间

  const SyncMapping({
    required this.localArticleId,
    required this.remotePostId,
    required this.siteId,
    required this.lastSyncAt,
    this.localModifiedAt,
    this.remoteModifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'localArticleId': localArticleId,
        'remotePostId': remotePostId,
        'siteId': siteId,
        'lastSyncAt': lastSyncAt.toIso8601String(),
        if (localModifiedAt != null) 'localModifiedAt': localModifiedAt!.toIso8601String(),
        if (remoteModifiedAt != null) 'remoteModifiedAt': remoteModifiedAt!.toIso8601String(),
      };

  factory SyncMapping.fromJson(Map<String, dynamic> j) {
    return SyncMapping(
      localArticleId: j['localArticleId']?.toString() ?? '',
      remotePostId: (j['remotePostId'] as num?)?.toInt() ?? 0,
      siteId: j['siteId']?.toString() ?? '',
      lastSyncAt: DateTime.tryParse(j['lastSyncAt']?.toString() ?? '') ?? DateTime.now(),
      localModifiedAt: DateTime.tryParse(j['localModifiedAt']?.toString() ?? ''),
      remoteModifiedAt: DateTime.tryParse(j['remoteModifiedAt']?.toString() ?? ''),
    );
  }
}

/// 同步状态
enum SyncStatus {
  /// 仅在本地存在
  localOnly,
  /// 仅在远程存在
  remoteOnly,
  /// 已同步，本地更新
  localNewer,
  /// 已同步，远程更新
  remoteNewer,
  /// 已同步，双方均有更新（冲突）
  conflict,
  /// 已同步，一致
  synced,
}

/// 同步结果条目
class SyncEntry {
  final String? localArticleId;
  final int? remotePostId;
  final String title;
  final SyncStatus status;
  final DateTime? localModifiedAt;
  final DateTime? remoteModifiedAt;

  const SyncEntry({
    this.localArticleId,
    this.remotePostId,
    required this.title,
    required this.status,
    this.localModifiedAt,
    this.remoteModifiedAt,
  });

  bool get hasConflict => status == SyncStatus.conflict;
  bool get needsPush => status == SyncStatus.localOnly || status == SyncStatus.localNewer;
  bool get needsPull => status == SyncStatus.remoteOnly || status == SyncStatus.remoteNewer;
}

/// 双向同步服务
///
/// 管理本地文章与远程 CMS 文章的映射关系，提供：
/// - 同步状态检测
/// - 冲突发现
/// - 推送/拉取操作
class SyncService {
  final LogService _logService;
  final Map<String, List<SyncMapping>> _mappings = {}; // key: siteId

  SyncService(this._logService);

  /// 获取指定站点的所有映射
  List<SyncMapping> getMappings(String siteId) {
    return _mappings[siteId] ?? [];
  }

  /// 添加或更新映射
  void setMapping(SyncMapping mapping) {
    _mappings.putIfAbsent(mapping.siteId, () => []);
    final list = _mappings[mapping.siteId]!;
    final idx = list.indexWhere((m) => m.localArticleId == mapping.localArticleId);
    if (idx >= 0) {
      list[idx] = mapping;
    } else {
      list.add(mapping);
    }
  }

  /// 移除映射
  void removeMapping(String siteId, String localArticleId) {
    _mappings[siteId]?.removeWhere((m) => m.localArticleId == localArticleId);
  }

  /// 根据本地文章 ID 查找映射
  SyncMapping? findByLocalId(String siteId, String localArticleId) {
    final list = _mappings[siteId];
    if (list == null) return null;
    for (final m in list) {
      if (m.localArticleId == localArticleId) return m;
    }
    return null;
  }

  /// 根据远程文章 ID 查找映射
  SyncMapping? findByRemoteId(String siteId, int remotePostId) {
    final list = _mappings[siteId];
    if (list == null) return null;
    for (final m in list) {
      if (m.remotePostId == remotePostId) return m;
    }
    return null;
  }

  /// 比较本地和远程文章列表，生成同步状态
  Future<List<SyncEntry>> compareSync(
    BlogSiteConfig siteConfig,
    BlogRepository adapter,
    List<Article> localArticles,
  ) async {
    final entries = <SyncEntry>[];
    final siteId = siteConfig.id;
    final mappings = getMappings(siteId);
    final mappedLocalIds = mappings.map((m) => m.localArticleId).toSet();
    final mappedRemoteIds = mappings.map((m) => m.remotePostId).toSet();

    // 1. 本地文章 → 检查同步状态
    for (final article in localArticles) {
      final mapping = findByLocalId(siteId, article.id);
      if (mapping == null) {
        // 仅在本地，未同步过
        entries.add(SyncEntry(
          localArticleId: article.id,
          title: article.title,
          status: SyncStatus.localOnly,
          localModifiedAt: article.updatedAt,
        ));
      } else {
        // 有映射，比较时间
        if (article.updatedAt.isAfter(mapping.lastSyncAt)) {
          // 本地有更新
          entries.add(SyncEntry(
            localArticleId: article.id,
            remotePostId: mapping.remotePostId,
            title: article.title,
            status: SyncStatus.localNewer,
            localModifiedAt: article.updatedAt,
            remoteModifiedAt: mapping.remoteModifiedAt,
          ));
        } else {
          entries.add(SyncEntry(
            localArticleId: article.id,
            remotePostId: mapping.remotePostId,
            title: article.title,
            status: SyncStatus.synced,
            localModifiedAt: article.updatedAt,
            remoteModifiedAt: mapping.remoteModifiedAt,
          ));
        }
      }
    }

    // 2. 远程文章 → 检查是否已映射
    try {
      // 分页拉取全部远程文章
      final allRemotePosts = <BlogPost>[];
      int page = 1;
      const perPage = 50;
      while (true) {
        final posts = await adapter.getPosts(page: page, perPage: perPage);
        if (posts.isEmpty) break;
        allRemotePosts.addAll(posts);
        if (posts.length < perPage) break;
        page++;
      }

      for (final post in allRemotePosts) {
        if (post.id == null) continue;
        if (mappedRemoteIds.contains(post.id)) {
          // 已映射，检查远程是否有更新
          final mapping = findByRemoteId(siteId, post.id!);
          if (mapping != null && post.modifiedDate.isAfter(mapping.lastSyncAt)) {
            // 更新已有条目的状态
            final idx = entries.indexWhere((e) => e.remotePostId == post.id);
            if (idx >= 0 && entries[idx].status == SyncStatus.synced) {
              entries[idx] = SyncEntry(
                localArticleId: entries[idx].localArticleId,
                remotePostId: post.id,
                title: post.title,
                status: SyncStatus.remoteNewer,
                localModifiedAt: entries[idx].localModifiedAt,
                remoteModifiedAt: post.modifiedDate,
              );
            } else if (idx >= 0 && entries[idx].status == SyncStatus.localNewer) {
              // 本地和远程都有更新 → 冲突
              entries[idx] = SyncEntry(
                localArticleId: entries[idx].localArticleId,
                remotePostId: post.id,
                title: post.title,
                status: SyncStatus.conflict,
                localModifiedAt: entries[idx].localModifiedAt,
                remoteModifiedAt: post.modifiedDate,
              );
            }
          }
        } else {
          // 仅在远程
          entries.add(SyncEntry(
            remotePostId: post.id,
            title: post.title,
            status: SyncStatus.remoteOnly,
            remoteModifiedAt: post.modifiedDate,
          ));
        }
      }
    } catch (e) {
      _logService.add('同步检测失败', '无法获取远程文章列表: $e', success: false);
    }

    return entries;
  }

  /// 推送本地文章到远程
  Future<BlogPost> pushToRemote(
    BlogRepository adapter,
    Article article,
    String siteId,
  ) async {
    final mapping = findByLocalId(siteId, article.id);

    final post = BlogPost(
      id: mapping?.remotePostId,
      title: article.title,
      contentMd: article.content,
      status: article.published ? 'publish' : 'draft',
      tags: article.tags,
      categories: article.categories,
      date: article.createdAt,
      siteId: siteId,
      siteType: adapter.config.type,
    );

    final result = mapping?.remotePostId != null
        ? await adapter.updatePost(post)
        : await adapter.createPost(post);

    // 更新映射
    if (result.id != null) {
      setMapping(SyncMapping(
        localArticleId: article.id,
        remotePostId: result.id!,
        siteId: siteId,
        lastSyncAt: DateTime.now(),
        localModifiedAt: article.updatedAt,
        remoteModifiedAt: result.modifiedDate,
      ));
    }

    _logService.add('推送同步', '已推送「${article.title}」到 ${adapter.config.type.displayName}');
    return result;
  }

  /// 拉取远程文章到本地
  /// [localArticleId] 拉取后本地文章的 ID，用于建立映射
  Future<BlogPost> pullFromRemote(
    BlogRepository adapter,
    int remotePostId,
    String siteId, {
    String? localArticleId,
  }) async {
    final post = await adapter.getPostById(remotePostId);
    if (post == null) {
      throw Exception('远程文章不存在: ID=$remotePostId');
    }

    // 建立映射关系
    if (localArticleId != null) {
      setMapping(SyncMapping(
        localArticleId: localArticleId,
        remotePostId: remotePostId,
        siteId: siteId,
        lastSyncAt: DateTime.now(),
        localModifiedAt: DateTime.now(),
        remoteModifiedAt: post.modifiedDate,
      ));
    }

    _logService.add('拉取同步', '已拉取「${post.title}」从 ${adapter.config.type.displayName}');
    return post;
  }

  /// 序列化所有映射
  String toJsonString() {
    final allMappings = <Map<String, dynamic>>[];
    for (final list in _mappings.values) {
      for (final m in list) {
        allMappings.add(m.toJson());
      }
    }
    return jsonEncode(allMappings);
  }

  /// 反序列化映射
  void fromJsonString(String json) {
    try {
      final list = jsonDecode(json) as List;
      for (final item in list) {
        final mapping = SyncMapping.fromJson(item as Map<String, dynamic>);
        setMapping(mapping);
      }
    } catch (e) {
      _logService.add('加载同步映射失败', '$e', success: false);
    }
  }

  /// 清空所有映射
  void clear() {
    _mappings.clear();
  }
}