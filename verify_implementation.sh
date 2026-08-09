#!/bin/bash

echo "=== Hexo App 代码验证脚本 ==="
echo

# 检查必要的文件是否存在
echo "1. 检查必要的文件..."
files=(
    "lib/l10n/app_localizations.dart"
    "lib/services/static_blog_batch_publish_service.dart"
    "lib/services/template_service.dart"
    "lib/services/git_service.dart"
    "lib/models/app_settings.dart"
    "lib/screens/settings_screen.dart"
    "lib/screens/static_blog_posts_screen.dart"
    "test/test_localizations.dart"
    "test/test_batch_publish.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file 存在"
    else
        echo "✗ $file 不存在"
    fi
done

echo

# 检查 Dart 语法
echo "2. 检查 Dart 语法..."
echo "检查主要文件..."

# 检查本地化文件
if dart analyze lib/l10n/app_localizations.dart > /dev/null 2>&1; then
    echo "✓ lib/l10n/app_localizations.dart 语法正确"
else
    echo "✗ lib/l10n/app_localizations.dart 语法错误"
fi

# 检查批量发布服务
if dart analyze lib/services/static_blog_batch_publish_service.dart > /dev/null 2>&1; then
    echo "✓ lib/services/static_blog_batch_publish_service.dart 语法正确"
else
    echo "✗ lib/services/static_blog_batch_publish_service.dart 语法错误"
fi

# 检查模板服务
if dart analyze lib/services/template_service.dart > /dev/null 2>&1; then
    echo "✓ lib/services/template_service.dart 语法正确"
else
    echo "✗ lib/services/template_service.dart 语法错误"
fi

echo

# 检查功能实现
echo "3. 检查功能实现..."

# 检查本地化功能
echo "检查本地化功能..."
if grep -q "AppLanguage" lib/l10n/app_localizations.dart; then
    echo "✓ 支持多语言功能"
else
    echo "✗ 缺少多语言功能"
fi

# 检查批量发布功能
echo "检查批量发布功能..."
if grep -q "batchPublishToStaticBlogs" lib/services/static_blog_batch_publish_service.dart; then
    echo "✓ 批量发布功能存在"
else
    echo "✗ 批量发布功能缺失"
fi

# 检查设置界面更新
echo "检查设置界面更新..."
if grep -q "_updateLanguage" lib/screens/settings_screen.dart; then
    echo "✓ 设置界面支持语言选择"
else
    echo "✗ 设置界面缺少语言选择"
fi

# 检查静态博客界面更新
echo "检查静态博客界面更新..."
if grep -q "_showBatchPublishDialog" lib/screens/static_blog_posts_screen.dart; then
    echo "✓ 静态博客界面支持批量发布"
else
    echo "✗ 静态博客界面缺少批量发布"
fi

echo

# 检查测试文件
echo "4. 检查测试文件..."
if [ -f "test/test_localizations.dart" ]; then
    echo "✓ 本地化测试文件存在"
else
    echo "✗ 本地化测试文件不存在"
fi

if [ -f "test/test_batch_publish.dart" ]; then
    echo "✓ 批量发布测试文件存在"
else
    echo "✗ 批量发布测试文件不存在"
fi

echo

# 检查 AppSettings 更新
echo "5. 检查 AppSettings 更新..."
if grep -q "language.*String" lib/models/app_settings.dart; then
    echo "✓ AppSettings 支持语言设置"
else
    echo "✗ AppSettings 缺少语言设置"
fi

echo
echo "=== 验证完成 ==="