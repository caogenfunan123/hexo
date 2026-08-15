import '../models/blog_framework.dart';
import '../models/git_provider.dart';
import '../models/wizard_models.dart';
import 'framework_build_map.dart';

/// 骨架文件条目
class SkeletonFile {
  final String path;
  final String content;

  const SkeletonFile({required this.path, required this.content});
}

/// 站点骨架生成器
///
/// 按 [BlogFramework.presets] 生成最小可构建骨架文件清单，
/// front matter 对齐各框架 `postFrontMatter` / `pageFrontMatter`。
/// 模式一额外生成 CI 流水线文件（GitHub Actions / GitLab CI），
/// 构建步骤按框架类型生成，上传产物目录对齐 [FrameworkBuildMap.buildOutputDirectory]。
class SiteScaffoldBuilder {
  const SiteScaffoldBuilder();

  /// 生成完整骨架文件清单（不含欢迎文章）。
  /// [mode] 为 one 时附加对应平台的 CI 文件。
  List<SkeletonFile> build(
    WizardMode mode,
    GitProviderType provider, {
    required String frameworkId,
    required String siteTitle,
  }) {
    final files = <SkeletonFile>[
      ..._buildFrameworkFiles(frameworkId, siteTitle),
      ..._buildCommonFiles(),
    ];
    if (mode == WizardMode.one) {
      files.addAll(_buildCiFiles(provider, frameworkId));
    }
    return files;
  }

  /// 生成欢迎文章（skipWelcomePost 为 false 时调用）。
  /// 返回 (路径, 内容)。
  (String, String) buildWelcomePost({
    required String frameworkId,
    required String siteTitle,
  }) {
    final framework = BlogFramework.byId(frameworkId);
    final postsPath = framework?.defaultPostsPath ?? 'source/_posts';
    final title = '欢迎使用 $siteTitle';
    final date = _todayDate();
    final content = _welcomePostContent(frameworkId, title, date);
    final fileBase = _slugify('欢迎使用 ${siteTitle.isEmpty ? '我的博客' : siteTitle}');
    final path = frameworkId == 'jekyll'
        ? '$postsPath/$date-$fileBase.md'
        : '$postsPath/$fileBase.md';
    return (path, content);
  }

  // ────────────────────────────────────────────────
  // 框架骨架
  // ────────────────────────────────────────────────

  List<SkeletonFile> _buildFrameworkFiles(String frameworkId, String siteTitle) {
    switch (frameworkId) {
      case 'hexo':
        return _buildHexo(siteTitle);
      case 'hugo':
        return _buildHugo(siteTitle);
      case 'jekyll':
        return _buildJekyll(siteTitle);
      case 'vuepress':
        return _buildVuepress(siteTitle);
      case 'gatsby':
        return _buildGatsby(siteTitle);
      case 'nextjs':
        return _buildNextjs(siteTitle);
      case 'astro':
        return _buildAstro(siteTitle);
      case 'pelican':
        return _buildPelican(siteTitle);
      case '11ty':
        return _buildEleventy(siteTitle);
      default:
        return _buildCustom(siteTitle);
    }
  }

  List<SkeletonFile> _buildCommonFiles() {
    return [
      const SkeletonFile(
        path: '.gitignore',
        content: '.DS_Store\nnode_modules/\ndist/\npublic/\n_site/\nout/\n.output/\n.vscode/\n.idea/\n',
      ),
    ];
  }

  List<SkeletonFile> _buildHexo(String siteTitle) {
    return [
      SkeletonFile(
        path: '_config.yml',
        content: '''
# Hexo 站点配置（一键建站生成）
title: ${_yaml(siteTitle.isEmpty ? '我的博客' : siteTitle)}
subtitle: ''
description: ''
language: zh-CN
timezone: ''

# URL
url: http://example.com
root: /

# 写作
new_post_name: :title.md
default_layout: post
auto_spacing: true
titlecase: false

# 目录
source_dir: source
public_dir: public

# 部署
deploy:
  type: ''
''',
      ),
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "hexo-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "hexo generate"
  },
  "hexo": {
    "version": ""
  },
  "dependencies": {
    "hexo": "^7.0.0",
    "hexo-renderer-marked": "^6.0.0",
    "hexo-renderer-ejs": "^2.0.0",
    "hexo-generator-archive": "^2.0.0",
    "hexo-generator-category": "^2.0.0",
    "hexo-generator-index": "^4.0.0",
    "hexo-generator-tag": "^2.0.0",
    "hexo-theme-landscape": "^1.0.0"
  }
}
''',
      ),
      const SkeletonFile(
        path: 'scaffolds/post.md',
        content: '''---
title: {{ title }}
date: {{ date }}
tags:
---
''',
      ),
      const SkeletonFile(
        path: 'scaffolds/page.md',
        content: '''---
title: {{ title }}
date: {{ date }}
type: page
---
''',
      ),
      const SkeletonFile(
        path: 'scaffolds/draft.md',
        content: '''---
title: {{ title }}
tags:
---
''',
      ),
      const SkeletonFile(
        path: 'themes/.gitkeep',
        content: '',
      ),
      const SkeletonFile(
        path: 'source/index.md',
        content: '',
      ),
    ];
  }

  List<SkeletonFile> _buildHugo(String siteTitle) {
    return [
      SkeletonFile(
        path: 'hugo.toml',
        content: '''
baseURL = 'http://example.org/'
languageCode = 'zh-cn'
title = '${_yaml(siteTitle.isEmpty ? '我的博客' : siteTitle)}'
theme = 'ananke'
buildFuture = true

[params]
  description = ''
''',
      ),
      SkeletonFile(
        path: 'config.toml',
        content: '''
# Hugo 配置（hugo.toml 为主，此文件保留以便兼容）
baseURL = 'http://example.org/'
title = '${_yaml(siteTitle.isEmpty ? '我的博客' : siteTitle)}'
buildFuture = true
''',
      ),
      const SkeletonFile(
        path: 'archetypes/default.md',
        content: '''---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
draft: false
---
''',
      ),
      const SkeletonFile(
        path: 'content/_index.md',
        content: '---\ntitle: 首页\n---\n',
      ),
      const SkeletonFile(
        path: 'themes/.gitkeep',
        content: '',
      ),
    ];
  }

  List<SkeletonFile> _buildJekyll(String siteTitle) {
    return [
      SkeletonFile(
        path: '_config.yml',
        content: '''
# Jekyll 站点配置（一键建站生成）
title: ${_yaml(siteTitle.isEmpty ? '我的博客' : siteTitle)}
description: ''
baseurl: ''
url: ''

# 构建
markdown: kramdown
theme: minima
plugins:
  - jekyll-feed
''',
      ),
      SkeletonFile(
        path: 'Gemfile',
        content: '''
source "https://rubygems.org"
gem "jekyll", "~> 4.3"
gem "minima", "~> 2.5"
group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.12"
end
''',
      ),
      const SkeletonFile(
        path: 'index.md',
        content: '---\nlayout: home\n---\n',
      ),
      const SkeletonFile(
        path: 'about.md',
        content: '---\nlayout: page\ntitle: 关于\npermalink: /about/\n---\n',
      ),
      const SkeletonFile(
        path: '_posts/.gitkeep',
        content: '',
      ),
    ];
  }

  List<SkeletonFile> _buildVuepress(String siteTitle) {
    return [
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "vuepress-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "docs:build": "vuepress build docs"
  },
  "dependencies": {
    "vuepress": "^1.9.0"
  }
}
''',
      ),
      SkeletonFile(
        path: 'docs/.vuepress/config.js',
        content: '''
module.exports = {
  title: '${siteTitle.isEmpty ? '我的博客' : siteTitle}',
  description: '',
  themeConfig: {
    nav: [{ text: '首页', link: '/' }]
  }
}
''',
      ),
      const SkeletonFile(
        path: 'docs/README.md',
        content: '# 首页\n\n欢迎访问我的博客。\n',
      ),
    ];
  }

  List<SkeletonFile> _buildGatsby(String siteTitle) {
    return [
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "gatsby-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "gatsby build"
  },
  "dependencies": {
    "gatsby": "^5.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "gatsby-source-filesystem": "^5.0.0",
    "gatsby-transformer-remark": "^6.0.0"
  }
}
''',
      ),
      SkeletonFile(
        path: 'gatsby-config.js',
        content: '''
module.exports = {
  siteMetadata: {
    title: '${siteTitle.isEmpty ? '我的博客' : siteTitle}',
    description: '',
  },
  plugins: [
    {
      resolve: 'gatsby-source-filesystem',
      options: { name: 'blog', path: '${'content/blog'}' },
    },
    'gatsby-transformer-remark',
  ],
}
''',
      ),
      const SkeletonFile(
        path: 'src/pages/index.js',
        content: '''
import React from "react"

export default function Home() {
  return <h1>欢迎访问我的博客</h1>
}
''',
      ),
    ];
  }

  List<SkeletonFile> _buildNextjs(String siteTitle) {
    return [
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "nextjs-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "next build && next export"
  },
  "dependencies": {
    "next": "^13.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
''',
      ),
      SkeletonFile(
        path: 'next.config.js',
        content: '''
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
}

module.exports = nextConfig
''',
      ),
      const SkeletonFile(
        path: 'pages/index.js',
        content: '''
export default function Home() {
  return (
    <main>
      <h1>欢迎访问我的博客</h1>
    </main>
  )
}
''',
      ),
    ];
  }

  List<SkeletonFile> _buildAstro(String siteTitle) {
    return [
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "astro-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "astro build"
  },
  "dependencies": {
    "astro": "^4.0.0"
  }
}
''',
      ),
      SkeletonFile(
        path: 'astro.config.mjs',
        content: '''
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://example.com',
});
''',
      ),
      const SkeletonFile(
        path: 'src/pages/index.astro',
        content: '''---
---
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <title>欢迎访问我的博客</title>
  </head>
  <body>
    <h1>欢迎访问我的博客</h1>
  </body>
</html>
''',
      ),
    ];
  }

  List<SkeletonFile> _buildPelican(String siteTitle) {
    return [
      SkeletonFile(
        path: 'pelicanconf.py',
        content: '''
SITENAME = '${siteTitle.isEmpty ? '我的博客' : siteTitle}'
SITEURL = 'https://example.com'
TIMEZONE = 'Asia/Shanghai'
DEFAULT_LANG = 'zh'
PATH = 'content'
THEME = 'simple'
''',
      ),
      SkeletonFile(
        path: 'publishconf.py',
        content: '''
from pelicanconf import *

SITEURL = 'https://example.com'
RELATIVE_URLS = False
DELETE_OUTPUT_DIRECTORY = True
''',
      ),
      const SkeletonFile(
        path: 'content/index.md',
        content: 'Title: 首页\nDate: 2026-01-01\nStatus: published\n\n欢迎访问我的博客。\n',
      ),
      SkeletonFile(
        path: 'requirements.txt',
        content: 'pelican\nmarkdown\n',
      ),
    ];
  }

  List<SkeletonFile> _buildEleventy(String siteTitle) {
    return [
      SkeletonFile(
        path: 'package.json',
        content: '''
{
  "name": "eleventy-blog",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "eleventy"
  },
  "dependencies": {
    "@11ty/eleventy": "^2.0.0"
  }
}
''',
      ),
      SkeletonFile(
        path: '.eleventy.js',
        content: '''
module.exports = function (eleventyConfig) {
  return {
    dir: {
      input: 'src',
      output: '_site'
    }
  }
}
''',
      ),
      const SkeletonFile(
        path: 'src/index.njk',
        content: '---\ntitle: 首页\nlayout: layout.njk\n---\n<h1>欢迎访问我的博客</h1>\n',
      ),
      const SkeletonFile(
        path: 'src/_includes/layout.njk',
        content: '<!DOCTYPE html>\n<html lang="zh-CN">\n<head><title>{{ title }}</title></head>\n<body>{{ content | safe }}</body>\n</html>\n',
      ),
    ];
  }

  List<SkeletonFile> _buildCustom(String siteTitle) {
    // custom 框架：仅生成 index 占位，构建由用户自行配置
    return [
      SkeletonFile(
        path: 'index.html',
        content: '<!DOCTYPE html>\n<html lang="zh-CN">\n<head><meta charset="utf-8"><title>${siteTitle.isEmpty ? '我的博客' : siteTitle}</title></head>\n<body><h1>欢迎访问我的博客</h1></body>\n</html>\n',
      ),
    ];
  }

  // ────────────────────────────────────────────────
  // CI 流水线
  // ────────────────────────────────────────────────

  List<SkeletonFile> _buildCiFiles(
      GitProviderType provider, String frameworkId) {
    if (provider == GitProviderType.gitlab) {
      return [
        SkeletonFile(
          path: '.gitlab-ci.yml',
          content: _gitlabCi(frameworkId),
        ),
      ];
    }
    return [
      SkeletonFile(
        path: '.github/workflows/deploy.yml',
        content: _githubActions(frameworkId),
      ),
    ];
  }

  String _githubActions(String frameworkId) {
    final info = FrameworkBuildMap.forFramework(frameworkId);
    final steps = _githubBuildSteps(info);
    return '''
name: Deploy Pages
on:
  push:
    branches: [main]
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
$steps
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ${info.buildOutputDirectory}
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: \${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
''';
  }

  String _githubBuildSteps(FrameworkBuildInfo info) {
    final base = '''
      - name: Checkout
        uses: actions/checkout@v4
''';
    switch (info.buildType) {
      case 'node':
        return base + '''
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 18
      - name: Install
        run: npm ci
      - name: Build
        run: ${info.buildCommand}
''';
      case 'jekyll':
        return base + '''
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.1'
      - name: Install
        run: bundle install
      - name: Build
        run: ${info.buildCommand}
''';
      case 'hugo':
        return base + '''
      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v3
        with:
          hugo-version: '0.128.0'
      - name: Build
        run: ${info.buildCommand}
''';
      case 'pelican':
        return base + '''
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install
        run: pip install -r requirements.txt
      - name: Build
        run: ${info.buildCommand}
''';
      default:
        return base + '''
      - name: Build
        run: ${info.buildCommand}
''';
    }
  }

  String _gitlabCi(String frameworkId) {
    final info = FrameworkBuildMap.forFramework(frameworkId);
    final image = _gitlabImage(info.buildType);
    return '''
pages:
  stage: deploy
  image: $image
  script:
$_gitlabScript(info)
  artifacts:
    paths:
      - ${info.buildOutputDirectory}
  rules:
    - if: \$CI_COMMIT_BRANCH == "main"
''';
  }

  String _gitlabScript(FrameworkBuildInfo info) {
    switch (info.buildType) {
      case 'node':
        return '    - npm ci\n    - ${info.buildCommand}';
      case 'jekyll':
        return '    - bundle install\n    - ${info.buildCommand}';
      case 'hugo':
        return '    - ${info.buildCommand}';
      case 'pelican':
        return '    - pip install -r requirements.txt\n    - ${info.buildCommand}';
      default:
        return '    - ${info.buildCommand}';
    }
  }

  String _gitlabImage(String buildType) {
    switch (buildType) {
      case 'jekyll':
        return 'ruby:3';
      case 'hugo':
        return 'hugo:latest';
      case 'pelican':
        return 'python:3';
      case 'node':
      default:
        return 'node:18';
    }
  }

  // ────────────────────────────────────────────────
  // 欢迎文章
  // ────────────────────────────────────────────────

  String _welcomePostContent(String frameworkId, String title, String date) {
    final framework = BlogFramework.byId(frameworkId);
    final fm = framework?.postFrontMatter ?? '';
    if (frameworkId == 'pelican') {
      return '''
Title: $title
Date: $date
Status: published

欢迎来到我的博客！这里将记录我的技术分享与生活思考。

你可以通过侧边栏「新建文章」发布第一篇正式内容。
''';
    }
    final filled = fm
        .replaceAll('{{title}}', title)
        .replaceAll('{{date}}', date)
        .replaceAll('{{tags}}', '')
        .replaceAll('{{categories}}', '')
        .replaceAll('{{slug}}', 'welcome')
        .replaceAll('{{draft}}', 'false');
    return '''
$filled

欢迎来到我的博客！这里将记录我的技术分享与生活思考。

你可以通过侧边栏「新建文章」发布第一篇正式内容。
''';
  }

  // ────────────────────────────────────────────────
  // 工具
  // ────────────────────────────────────────────────

  String _todayDate() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  String _slugify(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'welcome' : cleaned;
  }

  String _yaml(String s) =>
      s.contains(':') || s.contains('#') ? '"$s"' : s;
}
