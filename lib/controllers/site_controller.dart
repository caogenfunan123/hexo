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

  // ── 站点切换回调（由外部注入） ──
  Future<void> Function(String siteId)? onSiteSwitch;
  VoidCallback? onSitesChanged;

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

  void addStaticSite(SiteConfig site) {
    _staticSites.add(site);
    onSitesChanged?.call();
    notifyListeners();
  }

  void addDynamicSite(SiteConfig site) {
    _dynamicSites.add(site);
    onSitesChanged?.call();
    notifyListeners();
  }

  void updateSite(SiteConfig updated) {
    final staticIndex = _staticSites.indexWhere((s) => s.id == updated.id);
    if (staticIndex >= 0) {
      _staticSites[staticIndex] = updated;
    } else {
      final dynamicIndex = _dynamicSites.indexWhere((s) => s.id == updated.id);
      if (dynamicIndex >= 0) {
        _dynamicSites[dynamicIndex] = updated;
      }
    }
    onSitesChanged?.call();
    notifyListeners();
  }

  void removeSite(String siteId) {
    _staticSites.removeWhere((s) => s.id == siteId);
    _dynamicSites.removeWhere((s) => s.id == siteId);
    if (_activeSiteId == siteId) {
      _activeSiteId = allSites.isNotEmpty ? allSites.first.id : null;
    }
    onSitesChanged?.call();
    notifyListeners();
  }

  void setDefaultSite(String siteId) {
    // 遍历静态站点列表
    for (int i = 0; i < _staticSites.length; i++) {
      final site = _staticSites[i];
      _staticSites[i] = SiteConfig(
        id: site.id,
        name: site.name,
        repoUrl: site.repoUrl,
        branch: site.branch,
        framework: site.framework,
        isDefault: site.id == siteId,
        isStatic: site.isStatic,
        tokenId: site.tokenId,
      );
    }
    // 动态站点不支持设为默认
    notifyListeners();
  }

  // ── 站点切换 ──
  Future<void> switchSite(String siteId) async {
    if (_activeSiteId == siteId) return;
    _loading = true;
    notifyListeners();

    _activeSiteId = siteId;
    await onSiteSwitch?.call(siteId);

    _loading = false;
    notifyListeners();
  }

  void setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}