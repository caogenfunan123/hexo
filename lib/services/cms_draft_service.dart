import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/blog_post.dart';
import '../models/blog_site_config.dart';

/// CMS 草稿持久化服务
///
/// 使用 SQLite 存储动态 CMS 的未发布草稿，
/// 与静态博客的 JSON 草稿存储并行，互不干扰。
///
/// 表结构:
/// ```sql
/// CREATE TABLE cms_drafts (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   local_id TEXT NOT NULL UNIQUE,
///   site_id TEXT NOT NULL,
///   site_type TEXT NOT NULL,
///   cms_post_id INTEGER,
///   title TEXT NOT NULL,
///   content_md TEXT NOT NULL,
///   status TEXT DEFAULT 'draft',
///   slug TEXT,
///   tags TEXT,
///   categories TEXT,
///   link TEXT,
///   created_at TEXT NOT NULL,
///   updated_at TEXT NOT NULL
/// )
/// ```
class CmsDraftService {
  static const _tableName = 'cms_drafts';
  static const _dbName = 'cms_drafts.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_id TEXT NOT NULL UNIQUE,
            site_id TEXT NOT NULL,
            site_type TEXT NOT NULL,
            cms_post_id INTEGER,
            title TEXT NOT NULL,
            content_md TEXT NOT NULL,
            status TEXT DEFAULT 'draft',
            slug TEXT,
            tags TEXT,
            categories TEXT,
            link TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_cms_drafts_site_id ON $_tableName(site_id)',
        );
        await db.execute(
          'CREATE INDEX idx_cms_drafts_status ON $_tableName(status)',
        );
      },
    );
  }

  /// 保存或更新草稿
  Future<void> saveDraft(BlogPost post) async {
    final db = await _database;
    final now = DateTime.now().toIso8601String();

    // 使用 title + siteId 组合作为 local_id
    final localId = '${post.siteId ?? 'unknown'}_${post.title}';

    final existing = await db.query(
      _tableName,
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        _tableName,
        _postToMap(post, localId, now),
        where: 'local_id = ?',
        whereArgs: [localId],
      );
    } else {
      await db.insert(
        _tableName,
        _postToMap(post, localId, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 获取指定站点的所有草稿
  Future<List<BlogPost>> getDrafts(String siteId) async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      where: 'site_id = ? AND status = ?',
      whereArgs: [siteId, 'draft'],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapToPost).toList();
  }

  /// 获取指定站点的所有已发布文章
  Future<List<BlogPost>> getPublished(String siteId) async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      where: 'site_id = ? AND status = ?',
      whereArgs: [siteId, 'publish'],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapToPost).toList();
  }

  /// 获取单篇草稿（按 local_id）
  Future<BlogPost?> getByLocalId(String localId) async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapToPost(rows.first);
  }

  /// 更新草稿状态（发布后）
  Future<void> markPublished(String localId, int cmsPostId, String link) async {
    final db = await _database;
    await db.update(
      _tableName,
      {
        'status': 'publish',
        'cms_post_id': cmsPostId,
        'link': link,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// 删除草稿
  Future<void> deleteDraft(String localId) async {
    final db = await _database;
    await db.delete(
      _tableName,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// 获取所有站点草稿统计
  Future<Map<String, int>> getDraftCounts() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT site_id, COUNT(*) as cnt FROM $_tableName WHERE status = ? GROUP BY site_id',
      ['draft'],
    );
    final result = <String, int>{};
    for (final row in rows) {
      result[row['site_id'] as String] = row['cnt'] as int;
    }
    return result;
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  // ── 内部转换 ──

  Map<String, dynamic> _postToMap(BlogPost post, String localId, String now) {
    return {
      'local_id': localId,
      'site_id': post.siteId ?? '',
      'site_type': post.siteType?.name ?? '',
      'cms_post_id': post.id,
      'title': post.title,
      'content_md': post.contentMd,
      'status': post.status,
      'slug': post.slug,
      'tags': jsonEncode(post.tags),
      'categories': jsonEncode(post.categories),
      'link': post.link,
      'created_at': post.date.toIso8601String(),
      'updated_at': now,
    };
  }

  BlogPost _mapToPost(Map<String, dynamic> row) {
    return BlogPost(
      id: row['cms_post_id'] as int?,
      title: row['title'] as String? ?? '',
      contentMd: row['content_md'] as String? ?? '',
      date: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
      status: row['status'] as String? ?? 'draft',
      slug: row['slug'] as String?,
      tags: _parseList(row['tags']),
      categories: _parseList(row['categories']),
      siteId: row['site_id'] as String?,
      siteType: BlogType.fromString(row['site_type'] as String?),
      link: row['link'] as String?,
    );
  }

  List<String> _parseList(dynamic val) {
    if (val == null) return [];
    if (val is String) {
      try {
        final decoded = jsonDecode(val);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    return [];
  }
}