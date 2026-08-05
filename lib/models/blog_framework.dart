/// 静态博客框架预设
///
/// 每个框架的 front matter 模板均严格遵循其官方文档规范。
/// 关键差异：
/// - Jekyll 强制要求文件名带 YYYY-MM-DD 日期前缀
/// - Pelican 使用键值对元数据格式（非 YAML front matter）
/// - Next.js 原生使用 export 语句而非 YAML（模板兼容两种模式）
/// - Astro 使用 Zod schema 验证 front matter 字段
class BlogFramework {
  final String id;
  final String name;
  final String defaultPostsPath;
  final String defaultPagesPath;
  final bool postDatePrefix; // 文件名是否自动加日期前缀
  final String postFrontMatter;
  final String pageFrontMatter;

  const BlogFramework({
    required this.id,
    required this.name,
    required this.defaultPostsPath,
    required this.defaultPagesPath,
    this.postDatePrefix = false,
    this.postFrontMatter = '',
    this.pageFrontMatter = '',
  });

  static const List<BlogFramework> presets = [
    // ── Hexo ──
    // Front Matter: YAML，支持 tags/categories
    // 文件名: 自由命名，无日期前缀要求
    BlogFramework(
      id: 'hexo',
      name: 'Hexo',
      defaultPostsPath: 'source/_posts',
      defaultPagesPath: 'source',
      postDatePrefix: false,
      postFrontMatter: '''---
title: {{title}}
date: {{date}}
tags: {{tags}}
categories: {{categories}}
---
''',
      pageFrontMatter: '''---
title: {{title}}
date: {{date}}
type: page
---
''',
    ),
    // ── Hugo ──
    // Front Matter: YAML/TOML/JSON 均可，这里用 YAML
    // 文件名: 自由命名，无日期前缀要求
    // 注意: date 格式应带时区（如 2026-08-05T10:30:00+08:00）
    //       draft 默认应为 false，hugo new 会设为 true 需手动改
    BlogFramework(
      id: 'hugo',
      name: 'Hugo',
      defaultPostsPath: 'content/posts',
      defaultPagesPath: 'content',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: false
description: ""
tags: {{tags}}
categories: {{categories}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: false
type: page
---
''',
    ),
    // ── Jekyll ──
    // Front Matter: 仅 YAML，必须有 layout 字段
    // 文件名: 强制 YYYY-MM-DD-title.md 格式！缺少日期前缀文章不会显示
    // date 格式: 2026-08-05 14:30:00 +0800（需包含时间和时区）
    BlogFramework(
      id: 'jekyll',
      name: 'Jekyll',
      defaultPostsPath: '_posts',
      defaultPagesPath: '',
      postDatePrefix: true, // 关键：Jekyll 必须带日期前缀
      postFrontMatter: '''---
layout: post
title: "{{title}}"
date: {{date}} +0800
categories: {{categories}}
tags: {{tags}}
description: ""
---
''',
      pageFrontMatter: '''---
layout: page
title: "{{title}}"
permalink: /{{slug}}/
---
''',
    ),
    // ── VuePress ──
    // Front Matter: 仅 YAML
    // 文件名: 自由命名，路径决定路由
    // 注意: 文章必须放在 docs/posts/ 子目录下，否则侧边栏和首页列表无法自动扫描
    //       README.md 和 index.md 不能同时存在于同一目录
    BlogFramework(
      id: 'vuepress',
      name: 'VuePress',
      defaultPostsPath: 'docs/posts',
      defaultPagesPath: 'docs',
      postDatePrefix: false,
      postFrontMatter: '''---
title: {{title}}
date: {{date}}
description: ""
tags: {{tags}}
---
''',
      pageFrontMatter: '''---
title: {{title}}
sidebar: auto
---
''',
    ),
    // ── Gatsby ──
    // Front Matter: YAML，字段通过 GraphQL 查询
    // 文件名: 推荐 kebab-case，slug 在 front matter 中定义
    // 注意: 2026 年 Gatsby 处于维护模式，不建议新项目使用
    BlogFramework(
      id: 'gatsby',
      name: 'Gatsby',
      defaultPostsPath: 'content/blog',
      defaultPagesPath: 'src/pages',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: "{{date}}"
slug: "{{slug}}"
tags: {{tags}}
draft: {{draft}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
slug: "/{{slug}}/"
---
''',
    ),
    // ── Next.js ──
    // Front Matter: YAML（配合 gray-matter 插件解析，最通用方案）
    // 文件名: 放在 content/ 目录，动态路由用 [slug]/page.tsx
    // 注意: 必须在根目录创建 mdx-components.tsx 文件
    //       如使用 @next/mdx 原生方案，可改用 export const metadata
    BlogFramework(
      id: 'nextjs',
      name: 'Next.js',
      defaultPostsPath: 'content',
      defaultPagesPath: 'pages',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: "{{date}}"
tags: {{tags}}
draft: {{draft}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
date: "{{date}}"
---
''',
    ),
    // ── Astro ──
    // Front Matter: YAML，但字段必须符合 content.config.ts 中 Zod schema 定义
    // 文件名: 推荐 kebab-case，放在 src/content/blog/ 下
    // 注意: Astro 5+ 必须使用 content.config.ts + glob loader
    //       必填字段由 schema 定义（通常 title/description/pubDate）
    BlogFramework(
      id: 'astro',
      name: 'Astro',
      defaultPostsPath: 'src/content/blog',
      defaultPagesPath: 'src/pages',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
description: ""
pubDate: {{date}}
draft: {{draft}}
tags: {{tags}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
layout: ../layouts/Page.astro
---
''',
    ),
    // ── Pelican ──
    // Front Matter: 键值对格式（非 YAML！），不用 --- 分隔符
    // 文件名: 自由命名，无日期前缀要求
    // 注意: 元数据与正文之间用空行分隔
    //       文章必须放在 content/posts/ 子目录下
    //       Tags/Category 为空时不应输出该行（Pelican 不识别 [] 语法）
    //       Slug 应使用 ASCII 字符，中文标题需转拼音或用时间戳
    BlogFramework(
      id: 'pelican',
      name: 'Pelican',
      defaultPostsPath: 'content/posts',
      defaultPagesPath: 'content/pages',
      postDatePrefix: false,
      postFrontMatter: '''Title: {{title}}
Date: {{date}}
Tags: {{tags}}
Category: {{categories}}
Slug: {{slug}}
Status: published

''',
      pageFrontMatter: '''Title: {{title}}
Date: {{date}}
Template: page

''',
    ),
    // ── 11ty (Eleventy) ──
    // Front Matter: YAML，通过 layout 键指定布局
    // 文件名: 自由命名，扩展名决定模板引擎
    // 注意: Nunjucks 过滤器用括号传参 date("yyyy")，Liquid 用冒号 date: "%Y"
    //       Eleventy v2 默认不注册 date 过滤器，需在 .eleventy.js 中手动添加
    BlogFramework(
      id: '11ty',
      name: '11ty',
      defaultPostsPath: 'src/posts',
      defaultPagesPath: 'src',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: {{date}}
tags: {{tags}}
layout: layout.njk
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
layout: layout.njk
---
''',
    ),
  ];

  static BlogFramework? byId(String id) {
    try {
      return presets.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  static BlogFramework custom(String postsPath, String pagesPath) {
    return BlogFramework(
      id: 'custom',
      name: '自定义',
      defaultPostsPath: postsPath,
      defaultPagesPath: pagesPath,
      postDatePrefix: false,
    );
  }
}
