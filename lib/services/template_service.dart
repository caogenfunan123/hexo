/// 模板服务
class TemplateService {
  /// 获取文章模板
  Future<String> getPostTemplate(String frameworkId) async {
    switch (frameworkId) {
      case 'hexo':
        return _getHexoTemplate();
      case 'hugo':
        return _getHugoTemplate();
      case 'astro':
        return _getAstroTemplate();
      case 'jekyll':
        return _getJekyllTemplate();
      case 'vuepress':
        return _getVuepressTemplate();
      case 'gatsby':
        return _getGatsbyTemplate();
      case 'nextjs':
        return _getNextjsTemplate();
      default:
        throw Exception('不支持的框架: $frameworkId');
    }
  }

  /// 获取 Hexo 模板
  String _getHexoTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
status: {{status}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 Hugo 模板
  String _getHugoTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
draft: {{#if draft}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 Astro 模板
  String _getAstroTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
draft: {{#if draft}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 Jekyll 模板
  String _getJekyllTemplate() {
    return '''---
layout: post
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
published: {{#if published}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 VuePress 模板
  String _getVuepressTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
draft: {{#if draft}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 Gatsby 模板
  String _getGatsbyTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
draft: {{#if draft}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 获取 Next.js 模板
  String _getNextjsTemplate() {
    return '''---
title: "{{title}}"
date: {{date}}
tags: [{{tags}}]
categories: [{{categories}}]
draft: {{#if draft}}true{{else}}false{{/if}}
{{#if slug}}slug: {{slug}}{{/if}}
---

{{content}}''';
  }

  /// 渲染模板
  String renderTemplate(String template, Map<String, dynamic> data) {
    var content = template;
    
    // 替换简单变量
    data.forEach((key, value) {
      if (value is List) {
        content = content.replaceAll('{{$key}}', value.join(', '));
      } else {
        content = content.replaceAll('{{$key}}', value.toString());
      }
    });
    
    // 处理条件语句
    content = _processConditionals(content, data);
    
    return content;
  }

  /// 处理条件语句
  String _processConditionals(String content, Map<String, dynamic> data) {
    // 处理 if/else 语句
    final ifRegex = RegExp(r'{{#if\s+(\w+)}}(.*?){{else}}(.*?){{/if}}', dotAll: true);
    content = content.replaceAllMapped(ifRegex, (match) {
      final key = match.group(1)!;
      final trueContent = match.group(2)!;
      final falseContent = match.group(3)!;
      
      return data[key] == true || data[key] == 'true' ? trueContent : falseContent;
    });
    
    // 处理 if 语句
    final ifOnlyRegex = RegExp(r'{{#if\s+(\w+)}}(.*?){{/if}}', dotAll: true);
    content = content.replaceAllMapped(ifOnlyRegex, (match) {
      final key = match.group(1)!;
      final content = match.group(2)!;
      
      return data[key] == true || data[key] == 'true' ? content : '';
    });
    
    return content;
  }
}