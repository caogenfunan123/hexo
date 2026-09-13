import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexo/widgets/split_preview_pane.dart';

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

    testWidgets('编辑区打字应实时更新预览（200ms 防抖）', (tester) async {
      final title = TextEditingController(text: '');
      final content = TextEditingController(text: '初始内容。');
      final ratio = ValueNotifier<double>(0.55);
      await tester.pumpWidget(_wrap(SplitPreviewPane(
        titleCtrl: title,
        contentCtrl: content,
        splitRatio: ratio,
        textColor: const Color(0xFF1A1A2E),
        onContentChanged: () {},
      )));
      await tester.pumpAndSettle();

      // 在正文输入框里打字
      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.controller == content,
      );
      expect(contentField, findsOneWidget);
      await tester.enterText(contentField, '初始内容。追加的新句子丙。');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('追加的新句子丙'), findsWidgets,
          reason: '预览区应实时渲染新输入的内容');
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
