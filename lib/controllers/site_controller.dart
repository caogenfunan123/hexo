/// 站点控制器 — 统一管理桌面端和手机端的站点状态
///
/// 职责：站点管理（CRUD/切换）、站点隔离策略、仓库配置、多站点数据路由
/// 对标：Obsidian Vault 工作区隔离思想
library;

import 'package:flutter/material.dart';

/// 站点配置（轻量级，用于 Controller 状态）
class SiteConfig {
  final String id;
  final String name;
  final String repoUrl;
  final String? branch;
  final String? framework;
  final bool isDefault;
  final bool isStatic;
  final String? tokenId;

  const SiteConfig({
    required this.id,
    required this.name,
    required this.repoUrl,
    this.branch,
    this.framework,
    this.isDefault = false,
    this.isStatic = true,
    this.tokenId,
  });
}

class SiteController extends ChangeNotifier {
  // ── 站点列表 ──
  final List<SiteConfig> _staticSites = [];
  final List<SiteConfig> _dynamicSites = [];
  String? _activeSiteId;
  bool _loading = false;

  // ── Getters ──
  List<SiteConfig> get staticSites => List.unmodifiable(_staticSites);
  List<SiteConfig> get dynamicSites => List.unmodifiable(_dynamicSites);
  List<SiteConfig> get allSites => [..._staticSites, ..._dynamicSites];
  String? get activeSiteId => _activeSiteId;
  bool get loading => _loading;

  SiteConfig? get activeSite {
    if (_activeSiteId == null) return null;
    try {
      return allSites.firstWhere((s) => s.id == _activeSiteId);
    } catch (_) {
      return null;
    }
  }

  bool get hasSites => _staticSites.isNotEmpty || _dynamicSites.isNotEmpty;

  // ── 站点管理 ──
  void setSites(List<SiteConfig> staticSites, List<SiteConfig> dynamicSites) {
    _staticSites
      ..clear()
      ..addAll(staticSites);
    _dynamicSites
      ..clear()
      ..addAll(dynamicSites);
    notifyListeners();
  }

  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}