import 'package:flutter_test/flutter_test.dart';
import 'package:hexo_app/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations Tests', () {
    test('Should return correct display name for languages', () {
      expect(AppLocalizations.fromCode('zh-CN')?.displayName, '简体中文');
      expect(AppLocalizations.fromCode('en')?.displayName, 'English');
      expect(AppLocalizations.fromCode('ja')?.displayName, '日本語');
      expect(AppLocalizations.fromCode('ko')?.displayName, '한국어');
      expect(AppLocalizations.fromCode(null)?.displayName, '简体中文');
    });

    test('Should return fallback to Chinese for unknown language codes', () {
      expect(AppLocalizations.fromCode('unknown')?.displayName, '简体中文');
    });

    test('Should provide translations for all supported languages', () {
      final languages = ['zh-CN', 'en', 'ja', 'ko'];
      
      for (final lang in languages) {
        final localizations = AppLocalizations(lang);
        expect(localizations.appTitle, isNotNull);
        expect(localizations.home, isNotNull);
        expect(localizations.posts, isNotNull);
        expect(localizations.settings, isNotNull);
      }
    });

    test('Should return key when translation is missing', () {
      final localizations = AppLocalizations('unknown');
      expect(localizations.translate('nonexistent_key'), 'nonexistent_key');
    });

    test('Should have all required translations', () {
      final localizations = AppLocalizations('zh-CN');
      final requiredKeys = [
        'app_title',
        'home',
        'posts',
        'drafts',
        'categories',
        'tags',
        'settings',
        'add_site',
        'edit_site',
        'delete_site',
        'site_name',
        'site_url',
        'preview_url',
        'test_connection',
        'save',
        'cancel',
        'loading',
        'error',
        'success',
        'warning',
        'info',
        'confirm',
        'delete',
        'edit',
        'view',
        'publish',
        'unpublish',
        'create_post',
        'edit_post',
        'delete_post',
        'post_title',
        'post_content',
        'post_tags',
        'post_categories',
        'post_status',
        'post_slug',
        'published',
        'draft',
        'static_blog',
        'dynamic_cms',
        'wordpress',
        'ghost',
        'typecho',
        'all_sites',
        'current_site',
        'selected_sites',
        'batch_publish',
        'batch_publish_to_all',
        'batch_publish_selected',
        'preview',
        'language',
        'theme',
        'about',
        'version',
        'check_for_updates',
        'export_data',
        'import_data',
        'reset_settings',
        'logout',
      ];

      for (final key in requiredKeys) {
        expect(localizations.translate(key), isNotNull);
        expect(localizations.translate(key), isNot(''));
      }
    });
  });
}