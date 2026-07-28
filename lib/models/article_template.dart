class ArticleTemplate {
  final String id;
  final String name;
  final String description;
  final String content; // Markdown 模板内容，支持 {{title}} {{date}} {{tags}}
  final List<String> defaultTags;
  final List<String> defaultCategories;
  final DateTime createdAt;

  const ArticleTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    this.defaultTags = const [],
    this.defaultCategories = const [],
    required this.createdAt,
  });

  ArticleTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? content,
    List<String>? defaultTags,
    List<String>? defaultCategories,
    DateTime? createdAt,
  }) {
    return ArticleTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      defaultTags: defaultTags ?? this.defaultTags,
      defaultCategories: defaultCategories ?? this.defaultCategories,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'content': content,
        'defaultTags': defaultTags,
        'defaultCategories': defaultCategories,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ArticleTemplate.fromJson(Map<String, dynamic> j) => ArticleTemplate(
        id: j['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: j['name']?.toString() ?? '新模板',
        description: j['description']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        defaultTags: (j['defaultTags'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        defaultCategories: (j['defaultCategories'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  /// 根据标题和标签解析模板变量
  String render({
    String title = '未命名',
    String tags = '',
    String categories = '',
  }) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    return content
        .replaceAll('{{title}}', title)
        .replaceAll('{{date}}', date)
        .replaceAll('{{tags}}', tags)
        .replaceAll('{{categories}}', categories);
  }
}

/// 预设模板
class PresetTemplates {
  static List<ArticleTemplate> build() {
    final now = DateTime.now();
    return [
      ArticleTemplate(
        id: 'tech',
        name: '技术文章',
        description: '适合写技术教程、问题排查',
        defaultTags: ['技术', '教程'],
        content: '''## 背景

介绍一下为什么要写这篇文章，遇到了什么问题。

## 解决方案

### 步骤一

详细描述第一步。

### 步骤二

详细描述第二步。

```bash
# 示例命令
echo "hello"
```

## 总结

总结要点和注意事项。

## 参考

- [链接](https://)''',
        createdAt: now,
      ),
      ArticleTemplate(
        id: 'weekly',
        name: '周记',
        description: '一周的总结与思考',
        defaultTags: ['周记', '生活'],
        content: '''## 本周回顾

### 工作/学习

这周做了什么...

### 生活

生活中的点滴...

## 思考与感悟

> 引用一段话

个人的感悟...

## 下周计划

- [ ] 待办事项一
- [ ] 待办事项二
''',
        createdAt: now,
      ),
      ArticleTemplate(
        id: 'review',
        name: '书评/影评',
        description: '书籍或电影的评论',
        content: '''## 基本信息

- 书名/片名：
- 作者/导演：
- 阅读/观看日期：

## 内容概要

简单介绍内容（避免剧透）。

## 亮点

1. 第一点
2. 第二点

## 不足之处

1. 第一点

## 总体评价

⭐ 评分：/10

总结评价。
''',
        createdAt: now,
      ),
      ArticleTemplate(
        id: 'project',
        name: '项目复盘',
        description: '项目经验总结',
        defaultTags: ['项目', '复盘'],
        content: '''## 项目背景

- 项目名称：
- 时间周期：
- 我的角色：

## 目标与成果

| 目标 | 完成情况 |
|------|----------|
| 目标1 | ✅ / ❌ |

## 踩过的坑

### 坑一：问题描述

**原因**：

**解决**：

## 收获与成长

1. 技术方面
2. 协作方面

## 下一步

后续计划...
''',
        createdAt: now,
      ),
      ArticleTemplate(
        id: 'tutorial',
        name: '教程指南',
        description: '面向初学者的分步教程',
        defaultTags: ['教程', '入门'],
        content: '''## 目标读者

这篇文章适合...

## 前置准备

- 环境要求
- 需要的工具

## 正文

### 1. 第一步

详细说明...

### 2. 第二步

详细说明...

## 常见问题

### Q: 问题一
A: 答案

## 延伸阅读

- [链接](https://)
''',
        createdAt: now,
      ),
    ];
  }
}
