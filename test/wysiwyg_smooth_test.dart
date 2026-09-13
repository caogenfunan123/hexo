import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexo/widgets/wysiwyg_smooth_editor.dart';

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

  group('WysiwygSmoothEditor（手机端实验所见即所得）', () {
    testWidgets('formatted 模式应渲染 markdown 内容', (tester) async {
      final ctrl = TextEditingController(text: '# 标题甲\n\n段落乙的内容。');
      await tester.pumpWidget(_wrap(WysiwygSmoothEditor(controller: ctrl)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '构建不应抛异常');
      expect(find.textContaining('标题甲'), findsWidgets,
          reason: '标题块应渲染');
      expect(find.textContaining('段落乙'), findsWidgets,
          reason: '正文块应渲染');
    });

    testWidgets('点击正文块应进入编辑并写回 controller', (tester) async {
      final ctrl = TextEditingController(text: '段落乙的内容。');
      await tester.pumpWidget(_wrap(WysiwygSmoothEditor(controller: ctrl)));
      await tester.pumpAndSettle();

      // 点击正文块 → 进入块编辑（出现 TextField）
      await tester.tap(find.textContaining('段落乙').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsWidgets, reason: '点击块后应出现可编辑输入框');

      // 在块编辑器里输入 → 应实时写回外部 contentCtrl
      await tester.enterText(fields.last, '段落乙已修改。');
      await tester.pump(const Duration(milliseconds: 300));
      expect(ctrl.text, contains('段落乙已修改'),
          reason: '块内编辑应写回 contentCtrl（自动保存链路依赖）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('外部程序化改动应同步进编辑器', (tester) async {
      final ctrl = TextEditingController(text: '初始内容甲。');
      await tester.pumpWidget(_wrap(WysiwygSmoothEditor(controller: ctrl)));
      await tester.pumpAndSettle();

      // 模拟 AI 改写/图床插入：外部写 contentCtrl
      ctrl.text = '外部写入的新内容乙。';
      await tester.pumpAndSettle();
      expect(find.textContaining('外部写入的新内容乙'), findsWidgets,
          reason: '外部改动应渲染进所见即所得视图');
      expect(tester.takeException(), isNull);
    });

    testWidgets('frontmatter 块不应导致崩溃', (tester) async {
      final ctrl = TextEditingController(
        text: '---\ntitle: 测试\n---\n\n正文内容。',
      );
      await tester.pumpWidget(_wrap(WysiwygSmoothEditor(controller: ctrl)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'frontmatter 不应导致构建异常');
      expect(find.textContaining('正文内容'), findsWidgets);
    });
  });
}
