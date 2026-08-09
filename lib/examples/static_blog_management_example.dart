import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/repository/blog_repository.dart';
import '../core/repository/static_blog_repository.dart';
import '../core/site_manager.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../models/blog_site_config.dart';
import '../screens/unified_remote_posts_screen.dart';
import '../screens/static_blog_posts_screen.dart';
import '../services/log_service.dart';

/// 静态博客文章管理示例
/// 
/// 展示如何使用新的静态博客管理功能
class StaticBlogManagementExample extends StatefulWidget {
  final SiteManager siteManager;
  final LogService logService;

  const StaticBlogManagementExample({
    super.key,
    required this.siteManager,
    required this.logService,
  });

  @override
  State<StaticBlogManagementExample> createState() => _StaticBlogManagementExampleState();
}

class _StaticBlogManagementExampleState extends State<StaticBlogManagementExample> {
  int _currentIndex = 0;
  
  // 示例数据
  final List<RepoConfig> _staticRepos = [
    RepoConfig(
      id: 'hexo-blog-1',
      name: '我的Hexo博客',
      owner: 'myusername',
      repo: 'my-hexo-blog',
      branch: 'main',
      postsPath: 'source/_posts',
      frameworkId: 'hexo',
      siteUrl: 'https://myblog.github.io',
      token: 'github_token_here',
      isDefault: true,
    ),
    RepoConfig(
      id: 'hugo-blog-1',
      name: '我的Hugo博客',
      owner: 'myusername',
      repo: 'my-hugo-blog',
      branch: 'main',
      postsPath: 'content/posts',
      frameworkId: 'hugo',
      siteUrl: 'https://myhugo.example.com',
      token: 'github_token_here',
      isDefault: false,
    ),
  ];

  final List<BlogSiteConfig> _dynamicSites = [
    BlogSiteConfig(
      id: 'wordpress-1',
      name: 'WordPress博客',
      type: BlogType.wordpress,
      siteUrl: 'https://mywordpress.com',
      wpUsername: 'admin',
      wpAppPassword: 'app_password_here',
      isDefault: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('静态博客文章管理'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.all_inclusive),
            label: '统一管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.code),
            label: '静态博客',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.web),
            label: '动态CMS',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildUnifiedManagement();
      case 1:
        return _buildStaticBlogManagement();
      case 2:
        return _buildDynamicCMSManagement();
      default:
        return _buildUnifiedManagement();
    }
  }

  Widget _buildUnifiedManagement() {
    return UnifiedRemotePostsScreen(
      siteManager: widget.siteManager,
      logService: widget.logService,
      onOpenInEditor: (post) {
        _showSnackBar('打开文章: ${post.title}');
        // TODO: 实现打开到编辑器的逻辑
      },
      onDeletePost: (post) async {
        _showSnackBar('删除文章: ${post.title}');
        // TODO: 实现删除文章的逻辑
        await Future.delayed(const Duration(seconds: 1));
        return;
      },
    );
  }

  Widget _buildStaticBlogManagement() {
    if (_staticRepos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.code_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '暂无静态博客配置',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Text(
              '请先添加静态博客仓库配置',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _staticRepos.length,
      itemBuilder: (context, index) {
        final repo = _staticRepos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _openStaticBlog(repo),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          repo.frameworkId.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          repo.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${repo.owner}/${repo.repo}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '文章路径: ${repo.postsPath}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('查看文章'),
                          onPressed: () => _openStaticBlog(repo),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('刷新'),
                          onPressed: () => _refreshStaticBlog(repo),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDynamicCMSManagement() {
    if (_dynamicSites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.web_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '暂无动态CMS配置',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Text(
              '请先添加动态CMS站点配置',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dynamicSites.length,
      itemBuilder: (context, index) {
        final site = _dynamicSites[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _openDynamicCMS(site),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          site.type.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0E7490),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          site.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    site.siteUrl,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('查看文章'),
                          onPressed: () => _openDynamicCMS(site),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('刷新'),
                          onPressed: () => _refreshDynamicCMS(site),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openStaticBlog(RepoConfig repo) {
    // 创建静态博客管理界面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StaticBlogPostsScreen(
          repoConfig: repo,
          siteManager: widget.siteManager,
          logService: widget.logService,
          onOpenInEditor: (post) {
            _showSnackBar('打开文章: ${post.title}');
            // TODO: 实现打开到编辑器的逻辑
          },
          onDeletePost: (post) async {
            _showSnackBar('删除文章: ${post.title}');
            // TODO: 实现删除文章的逻辑
            await Future.delayed(const Duration(seconds: 1));
            return;
          },
        ),
      ),
    );
  }

  void _openDynamicCMS(BlogSiteConfig site) {
    _showSnackBar('打开动态CMS: ${site.name}');
    // TODO: 实现打开动态CMS管理界面的逻辑
  }

  void _refreshStaticBlog(RepoConfig repo) {
    _showSnackBar('刷新静态博客: ${repo.name}');
    // TODO: 实现刷新静态博客的逻辑
  }

  void _refreshDynamicCMS(BlogSiteConfig site) {
    _showSnackBar('刷新动态CMS: ${site.name}');
    // TODO: 实现刷新动态CMS的逻辑
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 使用示例：如何集成到现有应用
class IntegrationExample {
  /// 创建站点管理器
  static SiteManager createSiteManager() {
    final staticRepos = <RepoConfig>[];
    final dynamicSites = <BlogSiteConfig>[];
    final appSettings = AppSettings(); // 假设有应用设置
    
    return SiteManager(
      staticRepos: staticRepos,
      dynamicSites: dynamicSites,
      appSettings: appSettings,
      activeSiteId: '', // 设置活跃站点ID
    );
  }

  /// 创建日志服务
  static LogService createLogService() {
    return LogService(); // 假设有日志服务
  }

  /// 集成到主应用
  static Widget integrateIntoApp() {
    final siteManager = createSiteManager();
    final logService = createLogService();
    
    return StaticBlogManagementExample(
      siteManager: siteManager,
      logService: logService,
    );
  }
}