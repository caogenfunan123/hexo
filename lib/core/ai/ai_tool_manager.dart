/// AI 工具管理器：令牌脱敏读取 → 工具定义双重校验 → 持久化 → 当前会话即时加载
library;

import '../../models/blog_site_config.dart';
import '../../models/repo_config.dart';
import '../site_manager.dart';
import '../tools/tool_entity.dart';
import '../tools/tool_schema_validator.dart';
import '../tools/toolbox_repository.dart';
import 'token_vault.dart';

/// AI 创建工具的结果
class AiToolCreateResult {
  final bool success;
  final ToolEntity? tool;
  final ValidationResult? validation;
  final String? error;
  final String? siteId;

  const AiToolCreateResult({
    required this.success,
    this.tool,
    this.validation,
    this.error,
    this.siteId,
  });

  String get message {
    if (success) {
      return '工具 "${tool?.name}" 已保存到工具库';
    }
    if (validation != null) {
      return '校验未通过: ${validation!.message}';
    }
    return error ?? '未知错误';
  }
}

/// 工具创建链路中枢
class AiToolManager {
  final TokenVault _vault;
  final ToolSchemaValidator _validator;
  final ToolBoxRepository _repository;

  AiToolManager({
    TokenVault? vault,
    ToolSchemaValidator? validator,
    ToolBoxRepository? repository,
  })  : _vault = vault ?? TokenVault(),
        _validator = validator ?? ToolSchemaValidator(),
        _repository = repository ?? ToolBoxRepository();

  /// 从当前站点配置提取脱敏凭据（供 AI 上下文注入）
  SiteCredentials resolveCredentials(SiteManager siteManager) {
    final identity = siteManager.currentSiteIdentity;
    if (identity == null) {
      return const SiteCredentials(kind: 'unknown');
    }
    if (identity.isStatic) {
      final repo = siteManager.currentStaticRepo;
      if (repo != null) return _vault.fromRepo(repo);
    }
    final config = siteManager.currentDynamicConfig;
    if (config != null) return _vault.fromBlogSite(config);
    return const SiteCredentials(kind: 'unknown');
  }

  /// 从静态仓库配置解析脱敏凭据
  SiteCredentials credentialsFromRepo(RepoConfig repo) => _vault.fromRepo(repo);

  /// 从动态 CMS 站点配置解析脱敏凭据
  SiteCredentials credentialsFromBlogSite(BlogSiteConfig site) =>
      _vault.fromBlogSite(site);

  /// 校验并保存 AI 生成的工具定义
  ///
  /// [definition] 为 AI 输出的 JSON 工具定义
  /// [siteId] 当前站点 ID（站点私有工具归属）
  /// [allowAutoSave] 设置页总开关；关闭时仅校验不落库
  Future<AiToolCreateResult> createToolFromAi(
    Map<String, dynamic> definition, {
    required String siteId,
    required bool allowAutoSave,
    String? siteName,
  }) async {
    // 提取类型（mcp / skill）
    final isSkill = definition['steps'] is List && (definition['steps'] as List).isNotEmpty;
    final meta = definition['meta'] as Map<String, dynamic>?;

    // 双重校验
    final validation = isSkill
        ? _validator.validateSkill(definition)
        : _validator.validateMcp(definition);

    if (!validation.pass) {
      return AiToolCreateResult(
        success: false,
        validation: validation,
        siteId: siteId,
      );
    }

    // 作用域：默认全局公用；AI 显式标记 site_private 时为站点私有
    final scopeRaw = meta?['scope']?.toString() ?? meta?['global_available']?.toString();
    final isPrivate = scopeRaw == 'site_private' || scopeRaw == 'false' || scopeRaw == 'site';
    final scope = isPrivate ? ToolScope.sitePrivate : ToolScope.global;
    final riskLevel = meta?['risk_level']?.toString() ?? 'middle';

    // 自动保存总开关：关闭时仅返回校验通过的定义，不落库
    if (!allowAutoSave) {
      return AiToolCreateResult(
        success: false,
        error: 'AI 自动保存工具已关闭（可在设置中开启），已通过校验但未保存',
        siteId: siteId,
      );
    }

    try {
      final ToolEntity tool;
      if (isSkill) {
        tool = await _repository.createSkillFromAi(
          definition,
          scope: scope,
          siteId: isPrivate ? siteId : null,
          riskLevel: riskLevel,
          siteName: siteName,
        );
      } else {
        tool = await _repository.createMcpFromAi(
          definition,
          scope: scope,
          siteId: isPrivate ? siteId : null,
          riskLevel: riskLevel,
          siteName: siteName,
        );
      }
      return AiToolCreateResult(
        success: true,
        tool: tool,
        siteId: siteId,
      );
    } catch (e) {
      return AiToolCreateResult(
        success: false,
        error: '保存工具失败: $e',
        siteId: siteId,
      );
    }
  }
}
