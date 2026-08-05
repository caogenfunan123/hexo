import 'dart:convert';

/// 模板项：博文模板 / 页面模板
class TemplateItem {
  final String id;
  final String name;
  final String frontMatter; // 完整 FrontMatter 模板（含 ---）
  final String frameworkId; // 适配框架ID，'custom' 表示自定义/通用
  final bool isPost; // true=博文模板, false=页面模板
  final bool isBuiltin; // 是否内置预设
  final DateTime createdAt;

  const TemplateItem({
    required this.id,
    required this.name,
    required this.frontMatter,
    this.frameworkId = 'custom',
    this.isPost = true,
    this.isBuiltin = false,
    required this.createdAt,
  });

  TemplateItem copyWith({
    String? id,
    String? name,
    String? frontMatter,
    String? frameworkId,
    bool? isPost,
    bool? isBuiltin,
    DateTime? createdAt,
  }) {
    return TemplateItem(
      id: id ?? this.id,
      name: name ?? this.name,
      frontMatter: frontMatter ?? this.frontMatter,
      frameworkId: frameworkId ?? this.frameworkId,
      isPost: isPost ?? this.isPost,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'frontMatter': frontMatter,
        'frameworkId': frameworkId,
        'isPost': isPost,
        'isBuiltin': isBuiltin,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TemplateItem.fromJson(Map<String, dynamic> j) => TemplateItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        frontMatter: j['frontMatter']?.toString() ?? '',
        frameworkId: j['frameworkId']?.toString() ?? 'custom',
        isPost: j['isPost'] != false,
        isBuiltin: j['isBuiltin'] == true,
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  /// 用变量填充模板
  String apply({
    String title = '',
    String date = '',
    String tags = '',
    String categories = '',
    String slug = '',
    bool draft = false,
  }) {
    var fm = frontMatter
        .replaceAll('{{title}}', title)
        .replaceAll('{{date}}', date)
        .replaceAll('{{tags}}', tags)
        .replaceAll('{{categories}}', categories)
        .replaceAll('{{slug}}', slug.isEmpty ? title : slug)
        .replaceAll('{{draft}}', draft.toString());
    return fm;
  }

  /// 导出为分享用的 JSON 字符串
  String exportString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 从导入的 JSON 字符串创建
  factory TemplateItem.importFrom(String jsonStr) {
    final j = jsonDecode(jsonStr);
    if (j is! Map) throw Exception('无效的模板数据');
    final t = TemplateItem.fromJson(Map<String, dynamic>.from(j));
    // 导入后重置 ID 和时间
    final now = DateTime.now();
    return t.copyWith(
      id: 'import_${now.millisecondsSinceEpoch}',
      isBuiltin: false,
      createdAt: now,
    );
  }
}

/// 内置预设模板
class TemplatePresets {
  static const _now = '2026-01-01T00:00:00';

  // ── 博文模板 ──
  static List<TemplateItem> postTemplates() {
    final now = DateTime.parse(_now);
    return [
      // Hexo
      TemplateItem(
        id: 'builtin_hexo_post',
        name: 'Hexo 文章模板',
        frameworkId: 'hexo',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: {{title}}
date: {{date}}
tags: {{tags}}
categories: {{categories}}
---
''',
      ),
      // Hugo
      // 注意: date 用纯日期(YYYY-MM-DD)，draft 必须为 false
      TemplateItem(
        id: 'builtin_hugo_post',
        name: 'Hugo 文章模板',
        frameworkId: 'hugo',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: {{draft}}
description: ""
tags: {{tags}}
categories: {{categories}}
---
''',
      ),
      // Jekyll
      TemplateItem(
        id: 'builtin_jekyll_post',
        name: 'Jekyll 文章模板',
        frameworkId: 'jekyll',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
layout: post
title: "{{title}}"
date: {{date}} +0800
categories: {{categories}}
tags: {{tags}}
description: ""
---
''',
      ),
      // Astro
      TemplateItem(
        id: 'builtin_astro_post',
        name: 'Astro 文章模板',
        frameworkId: 'astro',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
description: ""
pubDate: {{date}}
draft: {{draft}}
tags: {{tags}}
---
''',
      ),
      // VuePress
      TemplateItem(
        id: 'builtin_vuepress_post',
        name: 'VuePress 文章模板',
        frameworkId: 'vuepress',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: {{title}}
date: {{date}}
description: ""
tags: {{tags}}
---
''',
      ),
      // Gatsby
      TemplateItem(
        id: 'builtin_gatsby_post',
        name: 'Gatsby 文章模板',
        frameworkId: 'gatsby',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: "{{date}}"
slug: "{{slug}}"
tags: {{tags}}
draft: {{draft}}
---
''',
      ),
      // Next.js
      TemplateItem(
        id: 'builtin_nextjs_post',
        name: 'Next.js 文章模板',
        frameworkId: 'nextjs',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: "{{date}}"
tags: {{tags}}
draft: {{draft}}
---
''',
      ),
      // Pelican
      // 注意: Tags/Category 为空时自动移除该行，不为空时用逗号分隔
      //       Slug 自动使用 ASCII 字符（中文标题转时间戳）
      TemplateItem(
        id: 'builtin_pelican_post',
        name: 'Pelican 文章模板',
        frameworkId: 'pelican',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''Title: {{title}}
Date: {{date}}
Tags: {{tags}}
Category: {{categories}}
Slug: {{slug}}
Status: published

''',
      ),
      // 11ty
      TemplateItem(
        id: 'builtin_11ty_post',
        name: '11ty 文章模板',
        frameworkId: '11ty',
        isPost: true,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: {{date}}
tags: {{tags}}
layout: layout.njk
---
''',
      ),
    ];
  }

  // ── 页面模板 ──
  static List<TemplateItem> pageTemplates() {
    final now = DateTime.parse(_now);
    return [
      // Hexo 页面
      TemplateItem(
        id: 'builtin_hexo_page',
        name: 'Hexo 页面模板',
        frameworkId: 'hexo',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: {{title}}
date: {{date}}
type: page
---
''',
      ),
      // Hugo 页面
      TemplateItem(
        id: 'builtin_hugo_page',
        name: 'Hugo 页面模板',
        frameworkId: 'hugo',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: {{date}}
draft: {{draft}}
type: page
---
''',
      ),
      // Jekyll 页面
      TemplateItem(
        id: 'builtin_jekyll_page',
        name: 'Jekyll 页面模板',
        frameworkId: 'jekyll',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
layout: page
title: "{{title}}"
permalink: /{{slug}}/
---
''',
      ),
      // Astro 页面
      TemplateItem(
        id: 'builtin_astro_page',
        name: 'Astro 页面模板',
        frameworkId: 'astro',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
layout: ../layouts/Page.astro
---
''',
      ),
      // VuePress 页面
      TemplateItem(
        id: 'builtin_vuepress_page',
        name: 'VuePress 页面模板',
        frameworkId: 'vuepress',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: {{title}}
sidebar: auto
---
''',
      ),
      // Gatsby 页面
      TemplateItem(
        id: 'builtin_gatsby_page',
        name: 'Gatsby 页面模板',
        frameworkId: 'gatsby',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
slug: "/{{slug}}/"
---
''',
      ),
      // Next.js 页面
      TemplateItem(
        id: 'builtin_nextjs_page',
        name: 'Next.js 页面模板',
        frameworkId: 'nextjs',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
date: "{{date}}"
---
''',
      ),
      // Pelican 页面
      TemplateItem(
        id: 'builtin_pelican_page',
        name: 'Pelican 页面模板',
        frameworkId: 'pelican',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''Title: {{title}}
Date: {{date}}
Template: page

''',
      ),
      // 11ty 页面
      TemplateItem(
        id: 'builtin_11ty_page',
        name: '11ty 页面模板',
        frameworkId: '11ty',
        isPost: false,
        isBuiltin: true,
        createdAt: now,
        frontMatter: '''---
title: "{{title}}"
layout: layout.njk
---
''',
      ),
    ];
  }

  /// 获取所有内置模板
  static List<TemplateItem> all() => [
        ...postTemplates(),
        ...pageTemplates(),
      ];
}