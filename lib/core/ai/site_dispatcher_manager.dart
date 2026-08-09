import 'ai_model_manager.dart';
import 'ai_request_dispatcher.dart';
import '../../services/ai_service.dart';

/// 按站点持有 AiRequestDispatcher 实例的管理器。
///
/// 解决全局单例串场问题：每个站点拥有独立的上下文（_chatHistory），
/// 切换站点后获取对应实例，互不污染。
class SiteDispatcherManager {
  final AiService _aiService;
  final AiModelManager _modelManager;
  final Map<String, AiRequestDispatcher> _instances = {};

  SiteDispatcherManager(this._aiService, this._modelManager);

  /// 获取指定站点的调度器实例（不存在则创建）
  AiRequestDispatcher forSite(String siteId) {
    final key = siteId.isEmpty ? '__global__' : siteId;
    return _instances.putIfAbsent(
        key, () => AiRequestDispatcher(_aiService, _modelManager));
  }

  /// 获取全局调度器（无站点上下文时使用）
  AiRequestDispatcher get global => forSite('');

  /// 释放站点上下文（站点删除/退出时调用）
  void disposeSite(String siteId) {
    if (siteId.isEmpty) return;
    _instances.remove(siteId)?.cancelCurrent();
  }

  /// 全部释放
  void disposeAll() {
    for (final d in _instances.values) {
      d.cancelCurrent();
    }
    _instances.clear();
  }
}
