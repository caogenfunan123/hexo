import 'package:flutter_test/flutter_test.dart';
import 'package:hexo/services/static_blog_batch_publish_service.dart';
import 'package:hexo/services/github_service.dart';
import 'package:hexo/models/blog_post.dart';
import 'package:hexo/models/repo_config.dart';
import 'package:hexo/models/app_settings.dart';
import 'package:hexo/core/site_manager.dart';

void main() {
  group('StaticBlogBatchPublishService Tests', () {
    late StaticBlogBatchPublishService service;
    late MockSiteManager siteManager;
    late MockGitHubService githubService;

    setUp(() {
      siteManager = MockSiteManager();
      githubService = MockGitHubService();
      service = StaticBlogBatchPublishService(
        siteManager: siteManager,
        githubService: githubService,
      );
    });

    test('Should publish a post to all static repos', () async {
      final post = BlogPost(
        title: 'Test Post',
        contentMd: 'This is a test post content.',
        date: DateTime(2026, 1, 2, 10, 30),
        tags: ['test', 'demo'],
        categories: ['general'],
        status: 'publish',
        slug: 'test-post',
      );

      bool completed = false;
      bool? success;
      Map<String, dynamic>? results;

      await service.batchPublishToStaticBlogs(
        post,
        onProgress: (_, __, ___) {},
        onComplete: (s, m, r) {
          completed = true;
          success = s;
          results = r;
        },
      );

      expect(completed, isTrue);
      expect(success, isTrue);
      expect(githubService.writtenPaths.length, 2);
      expect(githubService.writtenPaths.every((p) => p.endsWith('.md')), isTrue);
      // Hexo 仓库的文章内容包含 frontmatter 与正文
      final hexoContent = githubService.writtenContents.first;
      expect(hexoContent, contains('---'));
      expect(hexoContent, contains('title: "Test Post"'));
      expect(hexoContent, contains('tags:'));
      expect(hexoContent, contains('This is a test post content.'));
      // 默认仓库排在前面
      expect(results!.values.where((r) => r['success'] == true).length, 2);
    });

    test('Should only publish to selected sites when specified', () async {
      final post = BlogPost(
        title: 'Selected Post',
        contentMd: 'Content',
        date: DateTime(2026, 1, 2),
        status: 'publish',
      );

      bool? success;
      await service.batchPublishToStaticBlogs(
        post,
        selectedSiteIds: ['2'],
        onComplete: (s, m, r) => success = s,
      );

      expect(success, isTrue);
      expect(githubService.writtenPaths, hasLength(1));
    });

    test('Should report failure when repo has no token', () async {
      final post = BlogPost(
        title: 'No Token Post',
        contentMd: 'Content',
        date: DateTime(2026, 1, 2),
        status: 'publish',
      );
      siteManager.noTokenRepos = true;

      bool? success;
      Map<String, dynamic>? results;
      await service.batchPublishToStaticBlogs(
        post,
        onComplete: (s, m, r) {
          success = s;
          results = r;
        },
      );

      expect(success, isFalse);
      expect(results!.values.where((r) => r['success'] == false).length, 2);
    });
  });
}

class MockGitHubService extends GitHubService {
  final List<String> writtenPaths = [];
  final List<String> writtenContents = [];

  @override
  Future<Map<String, String>?> getRawFile(RepoConfig repo, String path) async {
    return null;
  }

  @override
  Future<void> putRawFile(
    RepoConfig repo,
    String path,
    String content, {
    String? sha,
    String? commitMessage,
  }) async {
    writtenPaths.add(path);
    writtenContents.add(content);
  }
}

class MockSiteManager extends SiteManager {
  bool noTokenRepos = false;

  MockSiteManager()
      : super(
          staticRepos: const [],
          dynamicSites: const [],
          appSettings: const AppSettings(),
          activeSiteId: '1',
        );

  @override
  List<RepoConfig> get staticRepos => [
        RepoConfig(
          id: '1',
          name: 'Hexo Blog',
          owner: 'owner',
          repo: 'hexo-blog',
          frameworkId: 'hexo',
          token: noTokenRepos ? '' : 'token1',
          isDefault: true,
        ),
        RepoConfig(
          id: '2',
          name: 'Hugo Blog',
          owner: 'owner',
          repo: 'hugo-blog',
          frameworkId: 'hugo',
          token: noTokenRepos ? '' : 'token2',
        ),
      ];
}
