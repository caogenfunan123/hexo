import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexo/desktop/widgets/desktop_split_editor.dart';
import 'package:hexo/widgets/debounced_markdown_preview.dart';
import 'package:hexo/widgets/markdown_preview_smooth.dart';

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
        DebouncedMarkdownPreview(state: state, isDark: false),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('分屏正文丁'), findsWidgets,
          reason: '分屏预览应渲染出正文文字');
    });

    testWidgets('updateText 后（防抖 200ms）应渲染新文字', (tester) async {
      final state = DebouncedMarkdownPreviewState();
      state.updateText('旧内容甲');
      await tester.pumpWidget(_wrap(
        DebouncedMarkdownPreview(state: state, isDark: false),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      state.updateText('新内容乙已实时更新');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('新内容乙已实时更新'), findsWidgets,
          reason: '打字停止 200ms 后分屏预览应实时更新');
    });

    testWidgets('表格 markdown 应渲染出表头与单元格', (tester) async {
      final state = DebouncedMarkdownPreviewState();
      state.updateText('| 名称 | 数量 |\n| --- | --- |\n| 苹果 | 3 |');
      await tester.pumpWidget(_wrap(
        DebouncedMarkdownPreview(state: state, isDark: false),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('名称'), findsWidgets,
          reason: '表格表头应渲染');
      expect(find.textContaining('苹果'), findsWidgets,
          reason: '表格单元格应渲染');
      expect(tester.takeException(), isNull, reason: '表格渲染不应抛异常');
    });
  });

  group('DesktopSplitEditor 端到端', () {
    Widget buildEditor(TextEditingController ctrl, SplitEditorMode mode) {
      return Builder(
        builder: (context) {
          return DesktopSplitEditor(
            contentController: ctrl,
            focusNode: FocusNode(),
            fontSize: 16,
            lineHeight: 1.6,
            fontFamily: 'monospace',
            isDark: false,
            colorScheme: Theme.of(context).colorScheme,
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

    testWidgets('split 模式带代码块内容应渲染（高亮构建器路径）', (tester) async {
      final ctrl = TextEditingController(text: '代码前文字\n\n```dart\nvoid main() { print(1); }\n```\n\n代码后文字');
      await tester.pumpWidget(_wrap(buildEditor(ctrl, SplitEditorMode.split)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('代码前文字'), findsWidgets,
          reason: 'split 模式含代码块时正文应正常渲染');
      expect(tester.takeException(), isNull,
          reason: '含代码块渲染不应抛出布局异常');
    });

    testWidgets('previewOnly 超长文档应走截断分支且不崩溃', (tester) async {
      final longText = '超长段落测试。\n' * 12000;  // 约 8.4 万字符 > 60000
      final state = DebouncedMarkdownPreviewState();
      state.updateText(longText);
      // 按真实布局：预览永远套在 SingleChildScrollView 内（有界盒子会溢出）
      await tester.pumpWidget(_wrap(
        SingleChildScrollView(
          child: DebouncedMarkdownPreview(state: state, isDark: false),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull,
          reason: '超长文档截断渲染不应抛异常');
      expect(find.textContaining('预览已折叠'), findsWidgets,
          reason: '超 60000 字符应显示截断提示');
    });

    testWidgets('sourceOnly 模式应渲染编辑器且可输入', (tester) async {
      final ctrl = TextEditingController(text: '源码模式内容戊');
      await tester.pumpWidget(_wrap(buildEditor(ctrl, SplitEditorMode.sourceOnly)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'sourceOnly 渲染不应抛异常');
      expect(find.textContaining('源码模式内容戊'), findsOneWidget);
      ctrl.text = '源码模式更新己';
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('源码模式更新己'), findsOneWidget);
    });
  });
}
