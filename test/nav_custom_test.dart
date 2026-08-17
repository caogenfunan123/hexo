import 'package:flutter_test/flutter_test.dart';
import 'package:hexo/core/repository/static_blog_repository.dart';
import 'package:hexo/desktop/feature_entries.dart';
import 'package:hexo/models/nav_custom_config.dart';
import 'package:hexo/models/ui_settings.dart';

void main() {
  group('NavCustomConfig', () {
    test('默认未自定义时回落模式默认过滤', () {
      const cfg = NavCustomConfig();
      expect(cfg.hasOverride('drafts'), false);
      expect(cfg.isPinned('drafts'), false);
    });

    test('自定义后某入口可隐藏', () {
      const cfg = NavCustomConfig(
        customized: true,
        visible: {'drafts': false},
      );
      expect(cfg.hasOverride('drafts'), true);
      expect(cfg.visible['drafts'], false);
    });

    test('JSON 序列化与反序列化往返一致', () {
      const cfg = NavCustomConfig(
        customized: true,
        visible: {'home': true, 'drafts': false},
        pinnedOrder: ['home', 'drafts'],
      );
      final restored = NavCustomConfig.fromJson(cfg.toJson());
      expect(restored.customized, true);
      expect(restored.visible, {'home': true, 'drafts': false});
      expect(restored.pinnedOrder, ['home', 'drafts']);
    });

    test('损坏 JSON 容错：非 Map / 非 List 字段安全降级', () {
      const bad = {
        'customized': 'yes',
        'visible': 'not-a-map',
        'pinnedOrder': 42,
      };
      final cfg = NavCustomConfig.fromJson(bad);
      expect(cfg.customized, false);
      expect(cfg.visible, isEmpty);
      expect(cfg.pinnedOrder, isEmpty);
    });
  });

  group('NavEntries.navVisibleFor（2.1）', () {
    test('标准模式所有注册入口均可见', () {
      const cfg = NavCustomConfig();
      for (final id in NavEntries.registry.keys) {
        expect(
          NavEntries.navVisibleFor(id, AppMode.standard, [], cfg),
          isTrue,
          reason: '$id 应在标准模式显示',
        );
      }
    });

    test('简易模式默认只显示 shown 项', () {
      const cfg = NavCustomConfig();
      expect(NavEntries.navVisibleFor('home', AppMode.simple, [], cfg), isTrue);
      expect(
        NavEntries.navVisibleFor('drafts', AppMode.simple, [], cfg),
        isTrue,
      );
      expect(
        NavEntries.navVisibleFor('logs', AppMode.simple, [], cfg),
        isFalse,
      );
      expect(
        NavEntries.navVisibleFor('recycle_bin', AppMode.simple, [], cfg),
        isFalse,
      );
      expect(
        NavEntries.navVisibleFor('recycle_bin', AppMode.simple, ['recycle_bin'], cfg),
        isTrue,
      );
    });

    test('自定义隐藏覆盖默认显示', () {
      const cfg = NavCustomConfig(
        customized: true,
        visible: {'home': false},
      );
      expect(
        NavEntries.navVisibleFor('home', AppMode.standard, [], cfg),
        isFalse,
      );
    });

    test('自定义显示覆盖简易模式默认隐藏', () {
      const cfg = NavCustomConfig(
        customized: true,
        visible: {'logs': true},
      );
      expect(NavEntries.navVisibleFor('logs', AppMode.simple, [], cfg), isTrue);
    });

    test('未知 id 在简易模式回落为不可见', () {
      const cfg = NavCustomConfig();
      expect(NavEntries.navVisibleFor('no_such_id', AppMode.simple, [], cfg),
          isFalse);
    });

    test('自定义配置只影响已配置项，其余回落默认', () {
      const cfg = NavCustomConfig(
        customized: true,
        visible: {'home': true},
      );
      expect(NavEntries.navVisibleFor('drafts', AppMode.simple, [], cfg), isTrue);
      expect(
        NavEntries.navVisibleFor('recycle_bin', AppMode.simple, [], cfg),
        isFalse,
      );
    });
  });

  group('快照指纹可比性（7.1）', () {
    test('指纹拼接按路径排序且含 SHA，内容变更即改变指纹', () {
      // 复刻 listPostsFingerprint 的拼接规则：数量;path:sha;（排序后）
      String fingerprint(Iterable<(String, String)> files) {
        final all = files.toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
        final sb = StringBuffer('${all.length};');
        for (final f in all) {
          sb.write('${f.$1}:${f.$2};');
        }
        return sb.toString();
      }

      final v1 = fingerprint([('a.md', 'sha1'), ('b.md', 'sha2')]);
      expect(v1, '2;a.md:sha1;b.md:sha2;');

      // 顺序无关（排序后一致）
      final v1b = fingerprint([('b.md', 'sha2'), ('a.md', 'sha1')]);
      expect(v1b, v1);

      // 内容变更（SHA 变）→ 指纹变
      final v2 = fingerprint([('a.md', 'shaX'), ('b.md', 'sha2')]);
      expect(v2, isNot(v1));

      // 增删文件 → 指纹变
      final v3 = fingerprint([('a.md', 'sha1')]);
      expect(v3, isNot(v1));
      final v4 = fingerprint(
          [('a.md', 'sha1'), ('b.md', 'sha2'), ('c.md', 'sha3')]);
      expect(v4, isNot(v1));
    });

    test('快照 JSON 往返保留指纹与空文章列表', () {
      final snap = StaticBlogSnapshot(
        fingerprint: '3;a.md:sha1;b.md:sha2;c.md:sha3;',
        savedAt: DateTime(2026, 8, 17, 12, 0, 0),
        posts: const [],
      );
      final restored = StaticBlogSnapshot.fromJson(snap.toJson());
      expect(restored.fingerprint, snap.fingerprint);
      expect(restored.savedAt, snap.savedAt);
      expect(restored.posts, isEmpty);
    });
  });

  group('双端一致入口集合（6.1）', () {
    test('注册表含全部枢纽页可访问入口 id', () {
      const hubIds = [
        'home',
        'new_article',
        'drafts',
        'cloud_sync',
        'p2p_sync',
        'site_manager',
        'create_site',
        'agent_workbench',
        'theme_store',
        'ai_model_manager',
        'image_bed',
        'proxy_settings',
        'recycle_bin',
        'snippets',
        'template_manager',
        'config_editor',
        'logs',
        'settings',
        'help',
        'all_features',
        'customize_sidebar',
      ];
      for (final id in hubIds) {
        expect(NavEntries.registry.keys, contains(id), reason: '$id 应在注册表');
      }
    });

    test('被合并的去重入口 id 仍保留定义，便于枢纽页访问', () {
      // 这些入口被合并进 同步中心/站点管理，但功能不删除（枢纽页可访问）
      for (final id in [
        'remote_posts',
        'sync_status',
        'history',
        'add_site',
        'blog_site_manager',
      ]) {
        expect(NavEntries.registry.keys, contains(id), reason: '$id 不应被删除');
      }
    });
  });
}