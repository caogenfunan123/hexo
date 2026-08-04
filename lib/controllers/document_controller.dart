/// 文档控制器 — 纯数据层，管理文章内容和元数据
///
/// 对标：VS Code TextModel（数据与视图分离）
/// 参考：super_editor 的 Document（纯数据，不包含选择/光标等 UI 状态）
///
/// 职责：
/// - 文章内容（标题、正文、标签、分类、封面）的 TextEditingController
/// - Article 数据模型（currentArticle）
/// - 草稿列表和模板列表
/// - 从控制器收集 Article 数据（collectArticle）
/// - FocusNode 管理
///
/// 反职责（不归此类管）：
/// - 光标位置、选择状态 → EditorController（对标 super_editor Composer）
/// - 标签页管理 → EditorController
/// - 编辑器外观设置（字体、主题） → EditorController
/// - 保存队列 → EditorController
library;

import 'package:flutter/material.dart';

import '../models/article_type.dart';
import '../models/article.dart';
import '../models/template_item.dart';

class DocumentController extends ChangeNotifier {
  // ── TextEditingController（Flutter Widget 桥接层） ──
  TextEditingController _titleCtrl = TextEditingController();
  TextEditingController _contentCtrl = TextEditingController();
  TextEditingController _tagsCtrl = TextEditingController();
  TextEditingController _categoriesCtrl = TextEditingController();
  TextEditingController _coverCtrl = TextEditingController();
  final FocusNode _contentFocus = FocusNode();

  // ── 文章数据模型 ──
  Article _currentArticle = Article(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    title: '', content: '',
    createdAt: DateTime.now(), updatedAt: DateTime.now(),
    isDraft: true, articleType: ArticleType.post,
  );

  // ── 文章元数据 ──
  ArticleType _articleType = ArticleType.post;
  String? _selectedTemplateId;
  String? _editorRepoId;

  // ── 草稿和模板 ──
  final List<Article> _drafts = [];
  final List<TemplateItem> _templates = [];

  // ── 保存状态 ──
  String _lastSavedContent = '';
  bool _hasUnsavedChanges = false;

  // ── Getters: TextEditingController ──
  TextEditingController get titleCtrl => _titleCtrl;
  TextEditingController get contentCtrl => _contentCtrl;
  TextEditingController get tagsCtrl => _tagsCtrl;
  TextEditingController get categoriesCtrl => _categoriesCtrl;
  TextEditingController get coverCtrl => _coverCtrl;
  FocusNode get contentFocus => _contentFocus;

  // ── Getters: 文章数据 ──
  Article get currentArticle => _currentArticle;

  // ── Getters: 元数据 ──
  ArticleType get articleType => _articleType;
  String? get selectedTemplateId => _selectedTemplateId;
  String? get editorRepoId => _editorRepoId;

  // ── Getters: 草稿和模板 ──
  List<Article> get drafts => List.unmodifiable(_drafts);
  List<TemplateItem> get templates => List.unmodifiable(_templates);

  // ── Getters: 保存状态 ──
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  String get lastSavedContent => _lastSavedContent;

  // ── 文章类型 ──
  void setArticleType(ArticleType type) {
    _articleType = type;
    notifyListeners();
  }

  // ── 模板 ──
  void setSelectedTemplateId(String? id) {
    _selectedTemplateId = id;
    notifyListeners();
  }

  // ── 仓库 ──
  void setEditorRepoId(String? id) {
    _editorRepoId = id;
    notifyListeners();
  }

  // ── 设置完整文章数据（同步所有 TextEditingController） ──
  void setCurrentArticle(Article article) {
    _currentArticle = article;
    _titleCtrl.text = article.title;
    _contentCtrl.text = article.content;
    _tagsCtrl.text = article.tags.join(', ');
    _categoriesCtrl.text = article.categories.join(', ');
    _coverCtrl.text = article.cover ?? '';
    _articleType = article.articleType;
    _selectedTemplateId = article.templateId;
    _editorRepoId = article.repoId;
    _lastSavedContent = article.content;
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  /// 更新 TextEditingController 引用（用于切换草稿等场景）
  void updateContentControllers({
    TextEditingController? title,
    TextEditingController? content,
    TextEditingController? tags,
    TextEditingController? categories,
    TextEditingController? cover,
  }) {
    if (title != null) _titleCtrl = title;
    if (content != null) _contentCtrl = content;
    if (tags != null) _tagsCtrl = tags;
    if (categories != null) _categoriesCtrl = categories;
    if (cover != null) _coverCtrl = cover;
    notifyListeners();
  }

  /// 从当前 TextEditingController 文本收集 Article 数据
  Article collectArticle({bool draft = true}) {
    return _currentArticle.copyWith(
      title: _titleCtrl.text,
      content: _contentCtrl.text,
      tags: _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      categories: _categoriesCtrl.text.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
      cover: _coverCtrl.text.isNotEmpty ? _coverCtrl.text : null,
      updatedAt: DateTime.now(),
      isDraft: draft,
      published: !draft,
      articleType: _articleType,
      templateId: _selectedTemplateId,
      repoId: _editorRepoId,
    );
  }

  // ── 草稿管理 ──
  void setDrafts(List<Article> drafts) {
    _drafts
      ..clear()
      ..addAll(drafts);
    notifyListeners();
  }

  // ── 模板管理 ──
  void setTemplates(List<TemplateItem> templates) {
    _templates
      ..clear()
      ..addAll(templates);
    notifyListeners();
  }

  // ── 保存状态 ──
  void markSaved() {
    _hasUnsavedChanges = false;
    _lastSavedContent = _contentCtrl.text;
    notifyListeners();
  }

  void markUnsaved() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  // ── 清理 ──
  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    _categoriesCtrl.dispose();
    _coverCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }
}