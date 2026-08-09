/// 应用语言支持
import 'package:flutter/widgets.dart';

enum AppLanguage {
  chinese('简体中文', 'zh-CN', 'zh'),
  english('English', 'en', 'en'),
  japanese('日本語', 'ja', 'ja'),
  korean('한국어', 'ko', 'ko'),
  ;

  final String displayName;
  final String locale;
  final String code;

  const AppLanguage(this.displayName, this.locale, this.code);

  /// 从代码获取语言
  static AppLanguage fromCode(String? code) {
    if (code == null) return chinese;
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code || lang.locale == code,
      orElse: () => chinese,
    );
  }

  /// 转换为 Flutter Locale
  Locale toLocale() => Locale(code);

  /// 获取系统支持的语言列表
  static List<AppLanguage> get supportedLanguages => [
        chinese,
        english,
        japanese,
        korean,
      ];

  /// Flutter Locale 列表
  static List<Locale> get supportedLocales =>
      supportedLanguages.map((l) => Locale(l.code)).toList();
}

/// 语言资源管理
class AppLocalizations {
  static const _translations = {
    // 中文（默认）
    'zh-CN': {
      'app_title': 'Hexo 博客管理',
      'home': '首页',
      'posts': '文章',
      'drafts': '草稿',
      'categories': '分类',
      'tags': '标签',
      'settings': '设置',
      'add_site': '添加站点',
      'edit_site': '编辑站点',
      'delete_site': '删除站点',
      'site_name': '站点名称',
      'site_url': '站点 URL',
      'preview_url': '预览 URL',
      'test_connection': '测试连接',
      'save': '保存',
      'cancel': '取消',
      'loading': '加载中...',
      'error': '错误',
      'success': '成功',
      'warning': '警告',
      'info': '信息',
      'confirm': '确认',
      'delete': '删除',
      'edit': '编辑',
      'view': '查看',
      'publish': '发布',
      'unpublish': '取消发布',
      'create_post': '创建文章',
      'edit_post': '编辑文章',
      'delete_post': '删除文章',
      'post_title': '文章标题',
      'post_content': '文章内容',
      'post_tags': '文章标签',
      'post_categories': '文章分类',
      'post_status': '文章状态',
      'post_slug': '文章别名',
      'published': '已发布',
      'draft': '草稿',
      'static_blog': '静态博客',
      'dynamic_cms': '动态 CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': '所有站点',
      'current_site': '当前站点',
      'selected_sites': '选择站点',
      'batch_publish': '批量发布',
      'batch_publish_to_all': '批量发布到所有站点',
      'batch_publish_selected': '批量发布到选定站点',
      'preview': '预览',
      'language': '语言',
      'theme': '主题',
      'about': '关于',
      'version': '版本',
      'check_for_updates': '检查更新',
      'export_data': '导出数据',
      'import_data': '导入数据',
      'reset_settings': '重置设置',
      'logout': '退出登录',
      'language_updated': '语言已更新',
      'select_language': '选择语言',
      'site_preview_url': '站点预览 URL',
      'website_name': '网站名称',
      'website_bio': '网站简介',
      'basic_info': '基本信息',
      'github_token': 'GitHub 登录令牌',
      'author': '作者',
      'contact_email': '联系邮箱',
      'repository': '仓库',
      'export_dir': '导出目录',
      'website_pages': '网站页面编辑',
      'theme_color': '主题颜色',
      'local_drafts': '本地草稿 · 离线编辑 · GitHub 发布 · 图床 · AI · RSS · 搜索 · 提交回滚',
      'not_logged_in': '尚未登录 Token',
      'token_configured': '已配置 Token',
      'saved_tokens_reuse': '保存过的 Token 可复用到多个仓库',
      'saved_tokens_count': '已保存 {count} 个 · 点此管理',
      'current_token': '当前登录令牌',
      'switched_to': '已切换到',
      'language_selector_hint': '选择应用界面显示语言',
    },
    // English
    'en': {
      'app_title': 'Hexo Blog Manager',
      'home': 'Home',
      'posts': 'Posts',
      'drafts': 'Drafts',
      'categories': 'Categories',
      'tags': 'Tags',
      'settings': 'Settings',
      'add_site': 'Add Site',
      'edit_site': 'Edit Site',
      'delete_site': 'Delete Site',
      'site_name': 'Site Name',
      'site_url': 'Site URL',
      'preview_url': 'Preview URL',
      'test_connection': 'Test Connection',
      'save': 'Save',
      'cancel': 'Cancel',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'warning': 'Warning',
      'info': 'Info',
      'confirm': 'Confirm',
      'delete': 'Delete',
      'edit': 'Edit',
      'view': 'View',
      'publish': 'Publish',
      'unpublish': 'Unpublish',
      'create_post': 'Create Post',
      'edit_post': 'Edit Post',
      'delete_post': 'Delete Post',
      'post_title': 'Post Title',
      'post_content': 'Post Content',
      'post_tags': 'Post Tags',
      'post_categories': 'Post Categories',
      'post_status': 'Post Status',
      'post_slug': 'Post Slug',
      'published': 'Published',
      'draft': 'Draft',
      'static_blog': 'Static Blog',
      'dynamic_cms': 'Dynamic CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': 'All Sites',
      'current_site': 'Current Site',
      'selected_sites': 'Selected Sites',
      'batch_publish': 'Batch Publish',
      'batch_publish_to_all': 'Batch Publish to All Sites',
      'batch_publish_selected': 'Batch Publish to Selected Sites',
      'preview': 'Preview',
      'language': 'Language',
      'theme': 'Theme',
      'about': 'About',
      'version': 'Version',
      'check_for_updates': 'Check for Updates',
      'export_data': 'Export Data',
      'import_data': 'Import Data',
      'reset_settings': 'Reset Settings',
      'logout': 'Logout',
      'language_updated': 'Language updated',
      'select_language': 'Select Language',
      'site_preview_url': 'Site Preview URL',
      'website_name': 'Site Name',
      'website_bio': 'Site Bio',
      'basic_info': 'Basic Info',
      'github_token': 'GitHub Login Token',
      'author': 'Author',
      'contact_email': 'Contact Email',
      'repository': 'Repository',
      'export_dir': 'Export Directory',
      'website_pages': 'Site Pages Editor',
      'theme_color': 'Theme Color',
      'local_drafts': 'Local drafts · Offline editing · GitHub publish · Image host · AI · RSS · Search · Commit rollback',
      'not_logged_in': 'No token yet',
      'token_configured': 'Token configured',
      'saved_tokens_reuse': 'Saved tokens can be reused across repos',
      'saved_tokens_count': '{count} saved · Tap to manage',
      'current_token': 'Current Login Token',
      'switched_to': 'Switched to',
      'language_selector_hint': 'Select app interface language',
    },
    // Japanese
    'ja': {
      'app_title': 'Hexo ブログ管理',
      'home': 'ホーム',
      'posts': '投稿',
      'drafts': '下書き',
      'categories': 'カテゴリー',
      'tags': 'タグ',
      'settings': '設定',
      'add_site': 'サイトを追加',
      'edit_site': 'サイトを編集',
      'delete_site': 'サイトを削除',
      'site_name': 'サイト名',
      'site_url': 'サイトURL',
      'preview_url': 'プレビューURL',
      'test_connection': '接続テスト',
      'save': '保存',
      'cancel': 'キャンセル',
      'loading': '読み込み中...',
      'error': 'エラー',
      'success': '成功',
      'warning': '警告',
      'info': '情報',
      'confirm': '確認',
      'delete': '削除',
      'edit': '編集',
      'view': '表示',
      'publish': '公開',
      'unpublish': '非公開',
      'create_post': '投稿を作成',
      'edit_post': '投稿を編集',
      'delete_post': '投稿を削除',
      'post_title': '投稿タイトル',
      'post_content': '投稿内容',
      'post_tags': '投稿タグ',
      'post_categories': '投稿カテゴリー',
      'post_status': '投稿ステータス',
      'post_slug': '投稿スラッグ',
      'published': '公開済み',
      'draft': '下書き',
      'static_blog': '静的ブログ',
      'dynamic_cms': '動的CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': 'すべてのサイト',
      'current_site': '現在のサイト',
      'selected_sites': '選択したサイト',
      'batch_publish': '一括公開',
      'batch_publish_to_all': 'すべてのサイトに一括公開',
      'batch_publish_selected': '選択したサイトに一括公開',
      'preview': 'プレビュー',
      'language': '言語',
      'theme': 'テーマ',
      'about': 'について',
      'version': 'バージョン',
      'check_for_updates': 'アップデートを確認',
      'export_data': 'データをエクスポート',
      'import_data': 'データをインポート',
      'reset_settings': '設定をリセット',
      'logout': 'ログアウト',
      'language_updated': '言語が更新されました',
      'select_language': '言語を選択',
      'site_preview_url': 'サイトプレビューURL',
      'website_name': 'サイト名',
      'website_bio': 'サイト紹介',
      'basic_info': '基本情報',
      'github_token': 'GitHub ログイントークン',
      'author': '作者',
      'contact_email': '連絡先メール',
      'repository': 'リポジトリ',
      'export_dir': 'エクスポートディレクトリ',
      'website_pages': 'サイトページ編集',
      'theme_color': 'テーマカラー',
      'local_drafts': 'ローカル下書き · オフライン編集 · GitHub公開 · 画像ホスト · AI · RSS · 検索 · コミットロールバック',
      'not_logged_in': 'トークン未設定',
      'token_configured': 'トークン設定済み',
      'saved_tokens_reuse': '保存済みトークンは複数リポジトリで再利用できます',
      'saved_tokens_count': '{count} 個保存済み · タップして管理',
      'current_token': '現在のログイントークン',
      'switched_to': '切り替えました',
      'language_selector_hint': 'アプリの表示言語を選択',
    },
    // Korean
    'ko': {
      'app_title': 'Hexo 블로그 관리',
      'home': '홈',
      'posts': '게시글',
      'drafts': '초안',
      'categories': '카테고리',
      'tags': '태그',
      'settings': '설정',
      'add_site': '사이트 추가',
      'edit_site': '사이트 편집',
      'delete_site': '사이트 삭제',
      'site_name': '사이트 이름',
      'site_url': '사이트 URL',
      'preview_url': '미리보기 URL',
      'test_connection': '연결 테스트',
      'save': '저장',
      'cancel': '취소',
      'loading': '로딩 중...',
      'error': '오류',
      'success': '성공',
      'warning': '경고',
      'info': '정보',
      'confirm': '확인',
      'delete': '삭제',
      'edit': '편집',
      'view': '보기',
      'publish': '게시',
      'unpublish': '게시 취소',
      'create_post': '게시글 작성',
      'edit_post': '게시글 편집',
      'delete_post': '게시글 삭제',
      'post_title': '게시글 제목',
      'post_content': '게시글 내용',
      'post_tags': '게시글 태그',
      'post_categories': '게시글 카테고리',
      'post_status': '게시글 상태',
      'post_slug': '게시글 슬러그',
      'published': '게시됨',
      'draft': '초안',
      'static_blog': '정적 블로그',
      'dynamic_cms': '동적 CMS',
      'wordpress': 'WordPress',
      'ghost': 'Ghost',
      'typecho': 'Typecho',
      'all_sites': '모든 사이트',
      'current_site': '현재 사이트',
      'selected_sites': '선택한 사이트',
      'batch_publish': '일괄 게시',
      'batch_publish_to_all': '모든 사이트에 일괄 게시',
      'batch_publish_selected': '선택한 사이트에 일괄 게시',
      'preview': '미리보기',
      'language': '언어',
      'theme': '테마',
      'about': '정보',
      'version': '버전',
      'check_for_updates': '업데이트 확인',
      'export_data': '데이터 내보내기',
      'import_data': '데이터 가져오기',
      'reset_settings': '설정 초기화',
      'logout': '로그아웃',
      'language_updated': '언어가 업데이트되었습니다',
      'select_language': '언어 선택',
      'site_preview_url': '사이트 미리보기 URL',
      'website_name': '사이트 이름',
      'website_bio': '사이트 소개',
      'basic_info': '기본 정보',
      'github_token': 'GitHub 로그인 토큰',
      'author': '작성자',
      'contact_email': '연락 이메일',
      'repository': '저장소',
      'export_dir': '내보내기 디렉터리',
      'website_pages': '사이트 페이지 편집',
      'theme_color': '테마 색상',
      'local_drafts': '로컬 초안 · 오프라인 편집 · GitHub 게시 · 이미지 호스팅 · AI · RSS · 검색 · 커밋 롤백',
      'not_logged_in': '토큰 없음',
      'token_configured': '토큰 설정됨',
      'saved_tokens_reuse': '저장된 토큰은 여러 저장소에서 재사용할 수 있습니다',
      'saved_tokens_count': '{count}개 저장됨 · 탭하여 관리',
      'current_token': '현재 로그인 토큰',
      'switched_to': '전환됨',
      'language_selector_hint': '앱 인터페이스 언어 선택',
    },
  };

  final String _locale;

  AppLocalizations(this._locale);

  /// 获取翻译文本
  String translate(String key) {
    final translations = _translations[_locale];
    if (translations != null && translations.containsKey(key)) {
      return translations[key]!;
    }
    
    // 如果找不到当前语言的翻译，尝试使用中文
    final chineseTranslations = _translations['zh-CN'];
    if (chineseTranslations != null && chineseTranslations.containsKey(key)) {
      return chineseTranslations[key]!;
    }
    
    // 如果中文也没有，返回 key
    return key;
  }

  /// 获取应用标题
  String get appTitle => translate('app_title');

  /// 获取首页文本
  String get home => translate('home');

  /// 获取文章文本
  String get posts => translate('posts');

  /// 获取草稿文本
  String get drafts => translate('drafts');

  /// 获取分类文本
  String get categories => translate('categories');

  /// 获取标签文本
  String get tags => translate('tags');

  /// 获取设置文本
  String get settings => translate('settings');

  /// 获取添加站点文本
  String get addSite => translate('add_site');

  /// 获取编辑站点文本
  String get editSite => translate('edit_site');

  /// 获取删除站点文本
  String get deleteSite => translate('delete_site');

  /// 获取站点名称文本
  String get siteName => translate('site_name');

  /// 获取站点 URL 文本
  String get siteUrl => translate('site_url');

  /// 获取预览 URL 文本
  String get previewUrl => translate('preview_url');

  /// 获取测试连接文本
  String get testConnection => translate('test_connection');

  /// 获取保存文本
  String get save => translate('save');

  /// 获取取消文本
  String get cancel => translate('cancel');

  /// 获取加载中文本
  String get loading => translate('loading');

  /// 获取错误文本
  String get error => translate('error');

  /// 获取成功文本
  String get success => translate('success');

  /// 获取警告文本
  String get warning => translate('warning');

  /// 获取信息文本
  String get info => translate('info');

  /// 获取确认文本
  String get confirm => translate('confirm');

  /// 获取删除文本
  String get delete => translate('delete');

  /// 获取编辑文本
  String get edit => translate('edit');

  /// 获取查看文本
  String get view => translate('view');

  /// 获取发布文本
  String get publish => translate('publish');

  /// 获取取消发布文本
  String get unpublish => translate('unpublish');

  /// 获取创建文章文本
  String get createPost => translate('create_post');

  /// 获取编辑文章文本
  String get editPost => translate('edit_post');

  /// 获取删除文章文本
  String get deletePost => translate('delete_post');

  /// 获取文章标题文本
  String get postTitle => translate('post_title');

  /// 获取文章内容文本
  String get postContent => translate('post_content');

  /// 获取文章标签文本
  String get postTags => translate('post_tags');

  /// 获取文章分类文本
  String get postCategories => translate('post_categories');

  /// 获取文章状态文本
  String get postStatus => translate('post_status');

  /// 获取文章别名文本
  String get postSlug => translate('post_slug');

  /// 获取已发布文本
  String get published => translate('published');

  /// 获取草稿文本
  String get draft => translate('draft');

  /// 获取静态博客文本
  String get staticBlog => translate('static_blog');

  /// 获取动态 CMS 文本
  String get dynamicCms => translate('dynamic_cms');

  /// 获取 WordPress 文本
  String get wordpress => translate('wordpress');

  /// 获取 Ghost 文本
  String get ghost => translate('ghost');

  /// 获取 Typecho 文本
  String get typecho => translate('typecho');

  /// 获取所有站点文本
  String get allSites => translate('all_sites');

  /// 获取当前站点文本
  String get currentSite => translate('current_site');

  /// 获取选择站点文本
  String get selectedSites => translate('selected_sites');

  /// 获取批量发布文本
  String get batchPublish => translate('batch_publish');

  /// 获取批量发布到所有站点文本
  String get batchPublishToAll => translate('batch_publish_to_all');

  /// 获取批量发布到选定站点文本
  String get batchPublishSelected => translate('batch_publish_selected');

  /// 获取预览文本
  String get preview => translate('preview');

  /// 获取语言文本
  String get language => translate('language');

  /// 获取主题文本
  String get theme => translate('theme');

  /// 获取关于文本
  String get about => translate('about');

  /// 获取版本文本
  String get version => translate('version');

  /// 获取检查更新文本
  String get checkForUpdates => translate('check_for_updates');

  /// 获取导出数据文本
  String get exportData => translate('export_data');

  /// 获取导入数据文本
  String get importData => translate('import_data');

  /// 获取重置设置文本
  String get resetSettings => translate('reset_settings');

  /// 获取退出登录文本
  String get logout => translate('logout');

  /// 获取语言已更新文本
  String get languageUpdated => translate('language_updated');

  /// 获取选择语言文本
  String get selectLanguage => translate('select_language');

  /// 获取站点预览URL文本
  String get sitePreviewUrl => translate('site_preview_url');

  /// 获取网站名称文本
  String get websiteName => translate('website_name');

  /// 获取网站简介文本
  String get websiteBio => translate('website_bio');

  /// 获取基本信息文本
  String get basicInfo => translate('basic_info');

  /// 获取GitHub令牌文本
  String get githubToken => translate('github_token');

  /// 获取作者文本
  String get author => translate('author');

  /// 获取联系邮箱文本
  String get contactEmail => translate('contact_email');

  /// 获取仓库文本
  String get repository => translate('repository');

  /// 获取导出目录文本
  String get exportDir => translate('export_dir');

  /// 获取网站页面编辑文本
  String get websitePages => translate('website_pages');

  /// 获取主题颜色文本
  String get themeColor => translate('theme_color');

  /// 获取本地功能描述文本
  String get localDrafts => translate('local_drafts');

  /// 获取未登录文本
  String get notLoggedIn => translate('not_logged_in');

  /// 获取已配置文本
  String get tokenConfigured => translate('token_configured');

  /// 获取保存令牌复用文本
  String get savedTokensReuse => translate('saved_tokens_reuse');

  /// 获取已保存令牌数量文本
  String savedTokensCount(int count) => translate('saved_tokens_count').replaceAll('{count}', '$count');

  /// 获取当前令牌文本
  String get currentToken => translate('current_token');

  /// 获取已切换文本
  String get switchedTo => translate('switched_to');

  /// 获取语言选择提示文本
  String get languageSelectorHint => translate('language_selector_hint');

  /// 创建本地化实例
  static AppLocalizations? of(String locale) {
    return AppLocalizations(locale);
  }

  /// 从 BuildContext 获取当前语言的本地化实例
  /// 需在 MaterialApp 配置 [delegate] 后使用
  static AppLocalizations ofContext(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations('zh-CN');
  }

  /// 当前语言代码
  String get locale => _locale;

  /// MaterialApp 本地化代理
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// 应用支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];
}

/// 本地化代理，负责按系统/应用语言加载对应翻译
class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLanguage.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final lang = AppLanguage.fromCode(locale.languageCode);
    return AppLocalizations(lang.locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}