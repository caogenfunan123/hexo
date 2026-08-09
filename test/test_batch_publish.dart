import 'package:flutter_test/flutter_test.dart';
import 'package:hexo_app/services/static_blog_batch_publish_service.dart';
import 'package:hexo_app/services/template_service.dart';
import 'package:hexo_app/models/blog_post.dart';
import 'package:hexo_app/models/repo_config.dart';
import 'package:hexo_app/core/site_manager.dart';

void main() {
  group('StaticBlogBatchPublishService Tests', () {
    late StaticBlogBatchPublishService service;
    late TemplateService templateService;
    late MockSiteManager siteManager;
    late MockGitService gitService;

    setUp(() {
      templateService = TemplateService();
      siteManager = MockSiteManager();
      gitService = MockGitService();
      service = StaticBlogBatchPublishService(
        settings: MockAppSettings(),
        siteManager: siteManager,
        gitService: gitService,
        templateService: templateService,
      );
    });

    test('Should convert content for Hexo framework', () async {
      final post = BlogPost(
        id: '1',
        title: 'Test Post',
        contentMd: 'This is a test post content.',
        date: DateTime.now(),
        tags: ['test', 'demo'],
        categories: ['general'],
        status: 'publish',
      );

      final repoConfig = RepoConfig(
        id: '1',
        name: 'Test Blog',
        repoUrl: 'https://github.com/test/blog',
        localPath: '/tmp/test-blog',
        frameworkId: 'hexo',
        isStatic: true,
      );

      final converted = await service._convertContentForSite(post, repoConfig, siteManager.getSite('1')!);

      expect(converted, contains('---'));
      expect(converted, contains('title: "Test Post"'));
      expect(converted, contains('tags: [test, demo]'));
      expect(converted, contains('categories: [general]'));
      expect(converted, contains('status: publish'));
      expect(converted, contains('This is a test post content.'));
    });

    test('Should generate frontmatter correctly', () {
      final frontmatter = {
        'title': 'Test Post',
        'date': '2023-01-01T00:00:00.000',
        'tags': ['test', 'demo'],
        'categories': ['general'],
        'status': 'publish',
      };

      final result = service._generateFrontmatter(frontmatter);

      expect(result, contains('---'));
      expect(result, contains('title: "Test Post"'));
      expect(result, contains('date: "2023-01-01T00:00:00.000"'));
      expect(result, contains('tags: [test, demo]'));
      expect(result, contains('categories: [general]'));
      expect(result, contains('status: "publish"'));
    });

    test('Should create temporary file', () async {
      final repoConfig = RepoConfig(
        id: '1',
        name: 'Test Blog',
        repoUrl: 'https://github.com/test/blog',
        localPath: '/tmp/test-blog',
        frameworkId: 'hexo',
        isStatic: true,
      );

      final tempFile = await service._createTempFile('test content', repoConfig);
      
      expect(tempFile, isNotNull);
      expect(await tempFile.readAsString(), 'test content');
      expect(tempFile.path, endsWith('.md'));
      
      // Clean up
      await tempFile.delete();
    });
  });
}

class MockSiteManager implements SiteManager {
  @override
  List<SiteIdentity> get staticSites => [
    SiteIdentity(
      id: '1',
      name: 'Test Blog',
      type: 'hexo',
      isStatic: true,
      siteUrl: 'https://test-blog.com',
      previewUrl: 'https://preview.test-blog.com',
    ),
  ];

  @override
  SiteIdentity? get currentStaticRepo => staticSites.first;

  @override
  List<SiteIdentity> get dynamicSites => [];

  @override
  SiteIdentity? get currentDynamicSite => null;

  SiteIdentity? getSite(String id) {
    return staticSites.firstWhere((site) => site.id == id);
  }
}

class MockAppSettings {
  String get language => 'zh-CN';
}

class MockGitService {
  Future<void> commitFile({
    required RepoConfig repoConfig,
    required String filePath,
    required String commitMessage,
    String authorName = 'Hexo Blog Manager',
    String authorEmail = 'noreply@hexo.blog',
  }) async {
    // Mock implementation
  }

  Future<void> push(RepoConfig repoConfig) async {
    // Mock implementation
  }
}