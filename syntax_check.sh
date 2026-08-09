#!/bin/bash

echo "=== 代码语法检查脚本 ==="
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
    "lib/screens/blog_site_editor_screen.dart"
    "lib/core/site_manager.dart"
    "lib/core/repository/static_blog_repository.dart"
    "lib/core/repository/typecho_fastapi_adapter.dart"
    "lib/core/repository/typecho_restful_adapter.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file 存在"
    else
        echo "✗ $file 不存在"
    fi
done

echo

# 检查常见的语法问题
echo "2. 检查常见语法问题..."

# 检查是否有未闭合的括号
echo "检查未闭合的括号..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查大括号
        open_braces=$(grep -o '{' "$file" | wc -l)
        close_braces=$(grep -o '}' "$file" | wc -l)
        if [ "$open_braces" -ne "$close_braces" ]; then
            echo "✗ $file: 大括号不匹配 ($open_braces 开启, $close_braces 关闭)"
        else
            echo "✓ $file: 大括号匹配"
        fi
        
        # 检查小括号
        open_parens=$(grep -o '(' "$file" | wc -l)
        close_parens=$(grep -o ')' "$file" | wc -l)
        if [ "$open_parens" -ne "$close_parens" ]; then
            echo "✗ $file: 小括号不匹配 ($open_parens 开启, $close_parens 关闭)"
        else
            echo "✓ $file: 小括号匹配"
        fi
    fi
done

echo

# 检查是否有重复的导入
echo "3. 检查重复导入..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查重复的 import 语句
        duplicate_imports=$(grep -n "^import" "$file" | sort | uniq -d)
        if [ -n "$duplicate_imports" ]; then
            echo "✗ $file: 发现重复导入"
            echo "$duplicate_imports"
        else
            echo "✓ $file: 无重复导入"
        fi
    fi
done

echo

# 检查是否有语法错误
echo "4. 检查语法错误..."

# 检查是否有分号缺失
echo "检查分号缺失..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查函数定义后的分号
        missing_semicolons=$(grep -n "^[[:space:]]*.*[[:space:]]*{$" "$file" | head -5)
        if [ -n "$missing_semicolons" ]; then
            echo "⚠ $file: 可能缺少分号的代码行"
            echo "$missing_semicolons"
        fi
    fi
done

echo

# 检查是否有未使用的变量
echo "5. 检查未使用的变量..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查是否有未使用的变量（简单检查）
        unused_vars=$(grep -n "^[[:space:]]*.*[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=" "$file" | grep -v "final\|const\|static" | head -3)
        if [ -n "$unused_vars" ]; then
            echo "⚠ $file: 可能未使用的变量"
            echo "$unused_vars"
        fi
    fi
done

echo

# 检查是否有类型错误
echo "6. 检查类型错误..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查是否有明显的类型错误
        type_errors=$(grep -n "null!" "$file" | head -3)
        if [ -n "$type_errors" ]; then
            echo "⚠ $file: 发现可能的空安全操作"
            echo "$type_errors"
        fi
    fi
done

echo

# 检查是否有异步操作错误
echo "7. 检查异步操作错误..."
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        # 检查是否有异步操作但没有 await
        async_issues=$(grep -n "async.*{" "$file" -A 5 | grep -E "^[[:space:]]*.*\..*[^a]wait" | head -3)
        if [ -n "$async_issues" ]; then
            echo "⚠ $file: 可能的异步操作问题"
            echo "$async_issues"
        fi
    fi
done

echo
echo "=== 检查完成 ==="