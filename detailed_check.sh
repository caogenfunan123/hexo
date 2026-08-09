#!/bin/bash

echo "=== 详细代码检查脚本 ==="
echo

# 检查是否有语法错误
echo "1. 检查语法错误..."

# 检查是否有未闭合的括号
echo "检查未闭合的括号..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        # 检查大括号
        open_braces=$(grep -o '{' "$file" | wc -l)
        close_braces=$(grep -o '}' "$file" | wc -l)
        if [ "$open_braces" -ne "$close_braces" ]; then
            echo "✗ $file: 大括号不匹配 ($open_braces 开启, $close_braces 关闭)"
        fi
        
        # 检查小括号
        open_parens=$(grep -o '(' "$file" | wc -l)
        close_parens=$(grep -o ')' "$file" | wc -l)
        if [ "$open_parens" -ne "$close_parens" ]; then
            echo "✗ $file: 小括号不匹配 ($open_parens 开启, $close_parens 关闭)"
        fi
        
        # 检查方括号
        open_brackets=$(grep -o '\[' "$file" | wc -l)
        close_brackets=$(grep -o '\]' "$file" | wc -l)
        if [ "$open_brackets" -ne "$close_brackets" ]; then
            echo "✗ $file: 方括号不匹配 ($open_brackets 开启, $close_brackets 关闭)"
        fi
    fi
done

echo

# 检查是否有导入问题
echo "2. 检查导入问题..."

# 检查是否有循环导入
echo "检查循环导入..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        # 检查是否有重复的导入
        duplicate_imports=$(grep -n "^import" "$file" | sort | uniq -d)
        if [ -n "$duplicate_imports" ]; then
            echo "✗ $file: 发现重复导入"
            echo "$duplicate_imports"
        fi
        
        # 检查是否有未使用的导入
        unused_imports=$(grep -n "^import" "$file" | grep -v "flutter/material.dart" | grep -v "dart:core" | grep -v "dart:async" | head -3)
        if [ -n "$unused_imports" ]; then
            echo "⚠ $file: 可能未使用的导入"
            echo "$unused_imports"
        fi
    fi
done

echo

# 检查是否有类型错误
echo "3. 检查类型错误..."

# 检查是否有 null 操作
echo "检查 null 操作..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        null_operations=$(grep -n "null!" "$file" | head -3)
        if [ -n "$null_operations" ]; then
            echo "⚠ $file: 发现可能的空安全操作"
            echo "$null_operations"
        fi
        
        # 检查是否有未处理的 null
        null_checks=$(grep -n "if.*!= null" "$file" | head -3)
        if [ -n "$null_checks" ]; then
            echo "⚠ $file: 发现可能的 null 检查"
            echo "$null_checks"
        fi
    fi
done

echo

# 检查是否有异步问题
echo "4. 检查异步问题..."

# 检查是否有 async 函数没有 await
echo "检查 async 函数..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        async_functions=$(grep -n "async.*{" "$file" | head -5)
        if [ -n "$async_functions" ]; then
            echo "⚠ $file: 发现 async 函数"
            echo "$async_functions"
        fi
        
        # 检查是否有 Future 没有 await
        futures=$(grep -n "Future<" "$file" | head -3)
        if [ -n "$futures" ]; then
            echo "⚠ $file: 发现 Future 类型"
            echo "$futures"
        fi
    fi
done

echo

# 检查是否有变量问题
echo "5. 检查变量问题..."

# 检查是否有未使用的变量
echo "检查未使用的变量..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        # 检查是否有未使用的 final 变量
        unused_final=$(grep -n "final.*=" "$file" | grep -v "const" | head -3)
        if [ -n "$unused_final" ]; then
            echo "⚠ $file: 可能未使用的 final 变量"
            echo "$unused_final"
        fi
        
        # 检查是否有未使用的 const 变量
        unused_const=$(grep -n "const.*=" "$file" | head -3)
        if [ -n "$unused_const" ]; then
            echo "⚠ $file: 可能未使用的 const 变量"
            echo "$unused_const"
        fi
    fi
done

echo

# 检查是否有方法问题
echo "6. 检查方法问题..."

# 检查是否有未使用的方法
echo "检查未使用的方法..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        # 检查是否有私有方法未使用
        private_methods=$(grep -n "_.*(" "$file" | grep -v "class" | head -3)
        if [ -n "$private_methods" ]; then
            echo "⚠ $file: 发现私有方法"
            echo "$private_methods"
        fi
        
        # 检查是否有公共方法未使用
        public_methods=$(grep -n "^[[:space:]]*.*[[:space:]]*(" "$file" | grep -v "_" | head -3)
        if [ -n "$public_methods" ]; then
            echo "⚠ $file: 发现公共方法"
            echo "$public_methods"
        fi
    fi
done

echo

# 检查是否有类问题
echo "7. 检查类问题..."

# 检查是否有未使用的类
echo "检查未使用的类..."
for file in lib/**/*.dart; do
    if [ -f "$file" ]; then
        # 检查是否有私有类未使用
        private_classes=$(grep -n "class _.*" "$file" | head -3)
        if [ -n "$private_classes" ]; then
            echo "⚠ $file: 发现私有类"
            echo "$private_classes"
        fi
        
        # 检查是否有公共类未使用
        public_classes=$(grep -n "class [A-Z]" "$file" | head -3)
        if [ -n "$public_classes" ]; then
            echo "⚠ $file: 发现公共类"
            echo "$public_classes"
        fi
    fi
done

echo

# 检查是否有文件问题
echo "8. 检查文件问题..."

# 检查是否有空的文件
echo "检查空的文件..."
empty_files=$(find lib -name "*.dart" -size 0)
if [ -n "$empty_files" ]; then
    echo "✗ 发现空的文件:"
    echo "$empty_files"
else
    echo "✓ 没有空的文件"
fi

# 检查是否有过大的文件
echo "检查过大的文件..."
large_files=$(find lib -name "*.dart" -size 100k)
if [ -n "$large_files" ]; then
    echo "⚠ 发现过大的文件 (>100KB):"
    echo "$large_files"
else
    echo "✓ 没有过大的文件"
fi

echo

# 检查是否有其他问题
echo "9. 检查其他问题..."

# 检查是否有 TODO 注释
echo "检查 TODO 注释..."
todo_comments=$(grep -n "TODO\|FIXME\|HACK" lib/**/*.dart | head -5)
if [ -n "$todo_comments" ]; then
    echo "⚠ 发现 TODO 注释:"
    echo "$todo_comments"
else
    echo "✓ 没有发现 TODO 注释"
fi

# 检查是否有调试代码
echo "检查调试代码..."
debug_code=$(grep -n "print\|debugPrint\|console.log" lib/**/*.dart | head -3)
if [ -n "$debug_code" ]; then
    echo "⚠ 发现调试代码:"
    echo "$debug_code"
else
    echo "✓ 没有发现调试代码"
fi

echo
echo "=== 检查完成 ==="