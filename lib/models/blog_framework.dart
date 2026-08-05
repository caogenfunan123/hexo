/// 静态博客框架预设
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
    BlogFramework(
      id: 'hugo',
      name: 'Hugo',
      defaultPostsPath: 'content/posts',
      defaultPagesPath: 'content',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: {{draft}}
tags: {{tags}}
categories: {{categories}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: {{draft}}
type: page
---
''',
    ),
    // ── Jekyll ──
    BlogFramework(
      id: 'jekyll',
      name: 'Jekyll',
      defaultPostsPath: '_posts',
      defaultPagesPath: '',
      postDatePrefix: false,
      postFrontMatter: '''---
layout: post
title: "{{title}}"
date: {{date}}
categories: {{categories}}
tags: {{tags}}
permalink: /{{title}}/
---
''',
      pageFrontMatter: '''---
layout: page
title: "{{title}}"
permalink: /{{title}}/
---
''',
    ),
    // ── VuePress ──
    BlogFramework(
      id: 'vuepress',
      name: 'VuePress',
      defaultPostsPath: 'docs',
      defaultPagesPath: 'docs',
      postDatePrefix: false,
      postFrontMatter: '''---
title: {{title}}
date: {{date}}
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
    BlogFramework(
      id: 'gatsby',
      name: 'Gatsby',
      defaultPostsPath: 'content/blog',
      defaultPagesPath: 'src/pages',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
date: "{{date}}"
slug: "/{{title}}/"
tags: {{tags}}
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
slug: "/{{title}}/"
---
''',
    ),
    // ── Next.js ──
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
---
''',
      pageFrontMatter: '''---
title: "{{title}}"
---
''',
    ),
    // ── Astro ──
    BlogFramework(
      id: 'astro',
      name: 'Astro',
      defaultPostsPath: 'src/content',
      defaultPagesPath: 'src/pages',
      postDatePrefix: false,
      postFrontMatter: '''---
title: "{{title}}"
pubDate: {{date}}
draft: false
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
    BlogFramework(
      id: 'pelican',
      name: 'Pelican',
      defaultPostsPath: 'content',
      defaultPagesPath: 'content/pages',
      postDatePrefix: false,
      postFrontMatter: '''---
Title: {{title}}
Date: {{date}}
Tags: {{tags}}
Category: {{categories}}
---
''',
      pageFrontMatter: '''---
Title: {{title}}
Date: {{date}}
Template: page
---
''',
    ),
    // ── 11ty ──
    BlogFramework(
      id: '11ty',
      name: '11ty',
      defaultPostsPath: 'src',
      defaultPagesPath: 'src',
      postDatePrefix: false,
      postFrontMatter: '''---
title: {{title}}
date: {{date}}
tags: {{tags}}
layout: post.njk
---
''',
      pageFrontMatter: '''---
title: {{title}}
layout: page.njk
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