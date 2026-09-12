#!/usr/bin/env python3
"""desktop_shell.dart 方法边界提取脚本（按 .monkeycode/docs/code-splitting-guide.md 方法论）
用法:
  python tools/split_helper.py inventory   # 打印 DesktopShellState 内所有方法清单
"""
import sys, re

SRC = 'lib/desktop/desktop_shell.dart'


def mask_document(text: str) -> str:
    """文档级屏蔽：把字符串字面量内容与注释替换为空格（保留换行与代码结构）。
    正确处理三引号字符串、转义、行注释、块注释，供花括号配对使用。"""
    out = []
    i, n = 0, len(text)
    state = 'code'  # code | line_comment | block_comment | sq | dq | tsq | tdq
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        three = text[i:i + 3]
        if state == 'code':
            if three == "'''":
                state = 'tsq'; out.append('   '); i += 3; continue
            if three == '"""':
                state = 'tdq'; out.append('   '); i += 3; continue
            if two == '//':
                state = 'line_comment'; out.append('  '); i += 2; continue
            if two == '/*':
                state = 'block_comment'; out.append('  '); i += 2; continue
            if c == "'":
                state = 'sq'; out.append(' '); i += 1; continue
            if c == '"':
                state = 'dq'; out.append(' '); i += 1; continue
            out.append(c); i += 1
        elif state == 'line_comment':
            if c == '\n':
                state = 'code'; out.append('\n')
            else:
                out.append(' ')
            i += 1
        elif state == 'block_comment':
            if two == '*/':
                state = 'code'; out.append('  '); i += 2
            else:
                out.append('\n' if c == '\n' else ' '); i += 1
        elif state in ('sq', 'dq'):
            close = "'" if state == 'sq' else '"'
            if c == '\\':
                out.append('  '); i += 2; continue
            if c == '\n':
                state = 'code'; out.append('\n'); i += 1; continue
            if c == close:
                state = 'code'; out.append(' '); i += 1; continue
            out.append(' '); i += 1
        else:  # tsq / tdq
            close = "'''" if state == 'tsq' else '"""'
            if three == close:
                state = 'code'; out.append('   '); i += 3; continue
            if c == '\\':
                out.append('  '); i += 2; continue
            out.append('\n' if c == '\n' else ' '); i += 1
    return ''.join(out)


def mask_lines(lines):
    return mask_document(''.join(lines)).splitlines(keepends=True)


def find_method_end(lines, start_idx):
    """在已屏蔽的行上，从声明行 start_idx 起做花括号配对，返回结束行号(含)。
    只在圆括号/方括号深度为 0 时统计花括号，避免参数默认值里的
    `{bool x = true}`、回调 tearoff `() {}` 干扰配对。"""
    depth = 0
    paren = 0
    bracket = 0
    seen_open = False
    for i in range(start_idx, len(lines)):
        s = lines[i]
        for ch in s:
            if ch == '(':
                paren += 1
            elif ch == ')':
                paren = max(0, paren - 1)
            elif ch == '[':
                bracket += 1
            elif ch == ']':
                bracket = max(0, bracket - 1)
            elif ch == '{':
                if paren == 0 and bracket == 0:
                    depth += 1; seen_open = True
            elif ch == '}':
                if paren == 0 and bracket == 0:
                    depth -= 1
                    if seen_open and depth == 0:
                        return i
        # 声明行尚未出现 { 且出现分号结尾 => 抽象/外部声明
        if not seen_open and i > start_idx and s.rstrip().endswith(';'):
            return i
    return None

# 返回类型关键字 + 方法名（允许多行参数）
DECL_RE = re.compile(
    r'^  (?:@override\s*)?'
    r'(?:static\s+)?(?:final\s+)?(?:const\s+)?'
    r'(Future<[^>]*(?:<[^>]*>)?[^>]*>|Future\b|void\b|Widget\b|bool\b|int\b|double\b|String\b|Color\b|List<[^>]*>|Map<[^>]*>|dynamic\b|[A-Z][A-Za-z0-9_<>,\s]*)\s+'
    r'(_?[A-Za-z][A-Za-z0-9_]*)\s*\('
)
EXCLUDE_PREFIX = ('await ', 'this.', 'if ', 'if(', 'return ', 'final ', 'var ', 'for ', 'while ', 'switch ', '}')

def collect_methods(masked_lines, class_start, class_end):
    methods = []
    i = class_start
    while i <= class_end:
        s = masked_lines[i]
        m = DECL_RE.match(s)
        if m:
            name = m.group(2)
            stripped = s.strip()
            if not any(stripped.startswith(p) for p in EXCLUDE_PREFIX):
                end = find_method_end(masked_lines, i)
                if end is not None and end <= class_end:
                    # 向上收集连续注释（不跨空行）
                    cstart = i
                    j = i - 1
                    while j >= 0:
                        t = masked_lines[j].strip()
                        if t.startswith('//') or t.startswith('///'):
                            cstart = j; j -= 1
                        elif t == '':
                            break
                        else:
                            break
                    methods.append((name, cstart, i, end))
                    i = end + 1
                    continue
        i += 1
    return methods


def main():
    with open(SRC, encoding='utf-8') as f:
        lines = f.readlines()
    masked = mask_lines(lines)
    cls_start = None
    for idx, l in enumerate(masked):
        if l.startswith('class DesktopShellState'):
            cls_start = idx
            break
    if cls_start is None:
        print('DesktopShellState not found'); return
    cls_end = len(lines) - 1
    for idx in range(cls_start + 1, len(masked)):
        if re.match(r'^(class |enum |mixin |abstract class )', masked[idx]):
            cls_end = idx - 1
            break
    methods = collect_methods(masked, cls_start, cls_end)
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'inventory'
    total = 0
    for name, cstart, dstart, end in methods:
        total += end - cstart + 1
        if cmd == 'inventory':
            print(f'{name}\t{cstart+1}\t{dstart+1}\t{end+1}\t{end-cstart+1}')
    print(f'# class range: {cls_start+1}..{cls_end+1}, methods: {len(methods)}, covered lines: {total}', file=sys.stderr)

if __name__ == '__main__':
    main()
