import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexo/desktop/widgets/desktop_split_editor.dart';
import 'package:hexo/widgets/debounced_markdown_preview.dart';
import 'package:hexo/widgets/markdown_preview_smooth.dart';
import 'package:hexo/widgets/unified_markdown_styles.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownPreviewSmooth（写作模式预览）', () {
    testWidgets('普通 markdown 应渲染出标题与正文', (tester) async {
      await tester.pumpWidget(_wrap(
        MarkdownPreviewSmooth(
          markdown: '# 标题甲\n\n正文段落乙，用于验证渲染。',
          baseFontSize: 16,
          lineHeight: 1.6,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('正文段落乙'), findsWidgets,
          reason: '写作模式预览应渲染出正文文字');
    });

    testWidgets('markdown 更新后（防抖 200ms）应渲染新文字', (tester) async {
      await tester.pumpWidget(_wrap(
        MarkdownPreviewSmooth(
          markdown: '第一版内容',
          baseFontSize: 16,
          lineHeight: 1.6,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(_wrap(
        MarkdownPreviewSmooth(
          markdown: '第二版内容已更新',
          baseFontSize: 16,
          lineHeight: 1.6,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('第二版内容已更新'), findsWidgets,
          reason: '打字停止 200ms 后预览应更新为新内容');
    });

    testWidgets('带代码块的 markdown 应渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        MarkdownPreviewSmooth(
          markdown: '前面文字\n\n```dart\nvoid main() {}\n```\n\n后面文字',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('前面文字'), findsWidgets);
    });
  });

  group('DebouncedMarkdownPreview（分屏预览）', () {
    testWidgets('提交后应渲染正文', (tester) async {
      final state = DebouncedMarkdownPreviewState();
      state.updateText('# 标题丙\n\n分屏正文丁，用于验证渲染。');
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            final style = createUnifiedMarkdownStyle(context: context);
            return DebouncedMarkdownPreview(
              state: state,
              isDark: false,
              styleSheet: style,
            );
          },
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('分屏正文丁'), findsWidgets,
          reason: '分屏预览应渲染出正文文字');
    });

    testWidgets('updateText 后（防抖 200ms）应渲染新文字', (tester) async {
      final state = DebouncedMarkdownPreviewState();
      state.updateText('旧内容甲');
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            final style = createUnifiedMarkdownStyle(context: context);
            return DebouncedMarkdownPreview(
              state: state,
              isDark: false,
              styleSheet: style,
            );
          },
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      state.updateText('新内容乙已实时更新');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('新内容乙已实时更新'), findsWidgets,
          reason: '打字停止 200ms 后分屏预览应实时更新');
    });
  });

  group('DesktopSplitEditor 端到端', () {
    Widget buildEditor(TextEditingController ctrl, SplitEditorMode mode) {
      return Builder(
        builder: (context) {
          final style = createUnifiedMarkdownStyle(context: context);
          return DesktopSplitEditor(
            contentController: ctrl,
            focusNode: FocusNode(),
            fontSize: 16,
            lineHeight: 1.6,
            fontFamily: 'monospace',
            isDark: false,
            colorScheme: Theme.of(context).colorScheme,
            styleSheet: style,
            initialMode: mode,
          );
        },
      );
    }

    testWidgets('previewOnly 模式应渲染内容；输入后应实时更新', (tester) async {
      final ctrl = TextEditingController(text: '初始内容壹');
      await tester.pumpWidget(_wrap(buildEditor(ctrl, SplitEditorMode.previewOnly)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('初始内容壹'), findsWidgets,
          reason: 'previewOnly 模式应显示初始内容');
      ctrl.text = '输入后的新内容贰';
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('输入后的新内容贰'), findsWidgets,
          reason: '输入停止后预览应实时更新');
    });

    testWidgets('split 模式应渲染内容且随输入更新', (tester) async {
      final ctrl = TextEditingController(text: '分栏初始内容叁');
      await tester.pumpWidget(_wrap(buildEditor(ctrl, SplitEditorMode.split)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('分栏初始内容叁'), findsWidgets,
          reason: 'split 模式左侧编辑器应显示内容');
      ctrl.text = '分栏更新内容肆';
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('分栏更新内容肆'), findsWidgets,
          reason: 'split 模式输入后右侧预览应实时更新');
    });
  });
}
