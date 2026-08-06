/// 工具定义校验器：JSON Schema 格式校验 + 危险操作黑名单检测
library;

import 'dart:convert';

/// 校验结果
class ValidationResult {
  final bool pass;
  final List<String> errors;
  final String? blockedBy; // 命中危险操作黑名单的原因

  const ValidationResult({
    required this.pass,
    this.errors = const [],
    this.blockedBy,
  });

  factory ValidationResult.ok() => const ValidationResult(pass: true);

  factory ValidationResult.fail(List<String> errors, {String? blockedBy}) =>
      ValidationResult(pass: false, errors: errors, blockedBy: blockedBy);

  String get message {
    if (blockedBy != null) return '危险操作拦截: $blockedBy';
    return errors.join('; ');
  }
}

/// 两层校验：
/// 1. JSON Schema 格式校验（meta/params/action/restrict 结构合法）
/// 2. 危险操作黑名单检测（删除全部文件、清空仓库等高危动作拦截）
class ToolSchemaValidator {
  static const _allowedParamTypes = {
    'string', 'bool', 'boolean', 'int', 'integer', 'number', 'array', 'object', 'path',
  };

  static const _allowedActionTypes = {
    'file_read', 'file_write', 'mkdir', 'rm', 'git_snapshot', 'git_rollback',
    'diff', 'list_dir', 'web_search', 'web_fetch', 'cms_post', 'none',
  };

  /// 危险操作黑名单：关键词匹配（宽松，命中即拦截）
  static const List<String> _dangerKeywords = [
    'rm -rf',
    'rm -fr',
    'rm -r -f',
    'delete all',
    'drop database',
    'drop table',
    'truncate table',
    'force push',
    'git clean -f',
    'reset --hard',
    'mkfs.',
    'shutdown -r',
    'format c:',
  ];

  /// 危险操作黑名单：正则匹配（更精确）
  static final List<RegExp> _dangerPatterns = [
    RegExp(r'DELETE\s+FROM\s+\S+\s*;?\s*$', caseSensitive: false), // 无 WHERE 的 DELETE
    RegExp(r'UPDATE\s+\S+\s+SET\s+.+\s+WHERE\s+[^=]+=\s*[^=]+\s*;?\s*$', caseSensitive: false),
    RegExp(r'git\s+push\s+(-f|--force)', caseSensitive: false),
    RegExp(r'git\s+reset\s+--hard', caseSensitive: false),
    RegExp(r'rm\s+-[rf]+', caseSensitive: false),
    RegExp(r'SHUTDOWN|FORMAT\s+[A-Z]:', caseSensitive: false),
  ];

  /// 校验 MCP 定义
  ValidationResult validateMcp(Map<String, dynamic> json) {
    final errors = <String>[];

    final meta = json['meta'];
    if (meta is! Map<String, dynamic>) {
      errors.add('缺少 meta 对象');
      return ValidationResult.fail(errors);
    }

    final name = meta['name']?.toString().trim() ?? '';
    if (name.isEmpty) errors.add('meta.name 不能为空');
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      errors.add('meta.name 必须是英文小写字母开头的标识符（仅 a-z 0-9 _）');
    }
    if ((meta['description']?.toString() ?? '').isEmpty) {
      errors.add('meta.description 不能为空');
    }

    // risk_level 校验
    final riskLevel = meta['risk_level']?.toString();
    if (riskLevel != null && !{'low', 'middle', 'high'}.contains(riskLevel)) {
      errors.add('risk_level 只能是 low/middle/high');
    }

    // params 校验
    final params = json['params'];
    if (params is! List) {
      errors.add('params 必须是数组');
    } else {
      for (final p in params) {
        if (p is! Map) {
          errors.add('params 中每一项必须是对象');
          continue;
        }
        final type = p['type']?.toString();
        if (type == null || !_allowedParamTypes.contains(type)) {
          errors.add('param ${p['key']} 的 type 非法: $type（允许: string/bool/int/array/path）');
        }
      }
    }

    // action 校验
    final action = json['action'];
    if (action is Map) {
      final actionType = action['type']?.toString();
      if (actionType != null && !_allowedActionTypes.contains(actionType)) {
        errors.add('action.type 非法: $actionType');
      }
    } else if (json['type'] is String) {
      // 兼容扁平格式 type 字段
      final flatType = json['type'].toString();
      if (!_allowedActionTypes.contains(flatType) && !flatType.startsWith('http')) {
        errors.add('type 非法: $flatType');
      }
    }

    if (errors.isNotEmpty) return ValidationResult.fail(errors);

    // 格式通过后做危险操作检测
    return checkDangerousOperation(json);
  }

  /// 校验 Skill 定义
  ValidationResult validateSkill(Map<String, dynamic> json) {
    final errors = <String>[];

    final meta = json['meta'];
    if (meta is! Map<String, dynamic>) {
      errors.add('缺少 meta 对象');
      return ValidationResult.fail(errors);
    }

    final name = meta['name']?.toString().trim() ?? '';
    if (name.isEmpty) errors.add('meta.name 不能为空');
    if ((meta['description']?.toString() ?? '').isEmpty) {
      errors.add('meta.description 不能为空');
    }

    final steps = json['steps'];
    if (steps is! List || steps.isEmpty) {
      errors.add('steps 必须是包含至少一个步骤的数组');
    }

    if (errors.isNotEmpty) return ValidationResult.fail(errors);
    return checkDangerousOperation(json);
  }

  /// 危险操作黑名单检测
  /// 扫描整个定义（meta + params + action + steps + payload + 任意嵌套字段）
  ValidationResult checkDangerousOperation(Map<String, dynamic> json) {
    final text = jsonEncode(json);
    final textLower = text.toLowerCase();

    // 关键词匹配
    for (final kw in _dangerKeywords) {
      if (textLower.contains(kw.toLowerCase())) {
        return ValidationResult.fail(
          const ['命中危险操作关键词'],
          blockedBy: '工具包含高危操作（关键词 "$kw"），已拦截保存',
        );
      }
    }

    // 正则匹配
    for (final re in _dangerPatterns) {
      if (re.hasMatch(text)) {
        return ValidationResult.fail(
          const ['命中危险操作正则'],
          blockedBy: '工具包含高危操作（$re），已拦截保存',
        );
      }
    }

    // 路径黑名单：restrict.path_black_list 或 payload 中出现根路径写操作
    final restrict = json['restrict'];
    if (restrict is Map) {
      final blackList = restrict['path_black_list'];
      if (blackList is List) {
        for (final p in blackList) {
          final path = p.toString();
          if (path == '/' || path == '/bin' || path == 'C:\\') {
            return ValidationResult.fail(
              const ['路径黑名单包含系统目录'],
              blockedBy: '工具配置了对系统目录 $path 的访问权限，已拦截保存',
            );
          }
        }
      }
    }

    return ValidationResult.ok();
  }
}
