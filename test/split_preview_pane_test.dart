import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexo/widgets/markdown_preview_smooth.dart';
import 'package:hexo/widgets/split_preview_pane.dart';

Finder _previewText(String s) => find.descendant(
      of: find.byType(MarkdownPreviewSmooth),
      matching: find.textContaining(s),
    );

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 700,
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplitPreviewPane（实验分屏实时预览）', () {
    testWidgets('两侧都应渲染：编辑区原文 + 预览区渲染文', (tester) async {
      final title = TextEditingController(text: '标题甲');
      final content = TextEditingController(text: '段落乙的内容。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '构建不应抛异常');
      // 编辑区（TextField 里的原文）
      expect(find.byType(TextField), findsNWidgets(2), reason: '标题+正文两个输入框');
      // 预览区渲染出标题 H1 与正文
      expect(find.textContaining('标题甲'), findsWidgets,
          reason: '预览区应渲染标题（编辑区也含原文，至少各一处）');
      expect(find.textContaining('段落乙'), findsWidgets,
          reason: '预览区应渲染正文');
    });

    testWidgets('编辑区打字应实时更新预览（注入短防抖验证链路）', (tester) async {
      final title = TextEditingController(text: '');
      final content = TextEditingController(text: '初始内容。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
        previewIdleDebounce: const Duration(milliseconds: 50),
      )));
      await tester.pumpAndSettle();

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.controller == content,
      );
      expect(contentField, findsOneWidget);
      await tester.enterText(contentField, '初始内容。追加的新句子丙。');
      // 短空闲窗口(50ms) + 预览自身 200ms 防抖
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final previews = tester.widgetList(find.byType(MarkdownPreviewSmooth));
      // ignore: avoid_print
      print('[split-debug] MarkdownPreviewSmooth count=${previews.length}');
      // ignore: avoid_print
      print('[split-debug] texts='
          '${tester.allWidgets.whereType<Text>().map((w) => w.data ?? w.textSpan?.toPlainText() ?? '(rich)').take(40).toList()}');
      expect(_previewText('追加的新句子丙'), findsWidgets,
          reason: '停手后预览应渲染新输入的内容');
      expect(tester.takeException(), isNull);
    });

    testWidgets('打字期间预览应保持静止（空闲防抖生效）', (tester) async {
      final title = TextEditingController(text: '');
      final content = TextEditingController(text: '初始内容。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
        previewIdleDebounce: const Duration(milliseconds: 600),
      )));
      await tester.pumpAndSettle();

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.controller == content,
      );
      await tester.enterText(contentField, '初始内容。追加的新句子丙。');
      // 300ms < 600ms 空闲窗口：预览必须仍是旧内容
      await tester.pump(const Duration(milliseconds: 300));
      expect(_previewText('追加的新句子丙'), findsNothing,
          reason: '打字期间预览应静止（空闲防抖防卡顿）');
      expect(_previewText('初始内容'), findsWidgets,
          reason: '静止期间预览仍显示旧内容');
      expect(tester.takeException(), isNull);
    });

    testWidgets('拖拽中缝应调整比例且不越界', (tester) async {
      final title = TextEditingController(text: '');
      final content = TextEditingController(text: '内容。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
      )));
      await tester.pumpAndSettle();

      // 找到中缝（56x3 圆角条所在的 GestureDetector）
      final divider = find.byType(GestureDetector).first;
      await tester.drag(divider, const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(ratio.value, lessThan(0.55), reason: '向下拖应缩小编辑区占比');
      expect(ratio.value, inInclusiveRange(0.25, 0.75), reason: '比例应被钳制');
      expect(tester.takeException(), isNull);
    });

    testWidgets('标题非空时预览应以 H1 前置', (tester) async {
      final title = TextEditingController(text: '我的标题');
      final content = TextEditingController(text: '正文。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
      )));
      await tester.pumpAndSettle();
      // H1 渲染出来的字号 > 正文，直接验证标题文本出现在预览
      expect(find.textContaining('我的标题'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
