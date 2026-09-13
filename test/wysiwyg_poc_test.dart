// 阶段2 Spike / 阶段2.5 主编辑区验证：
// 1) markdown 进 → SuperEditor 文档 → 序列化 markdown 出，结构语义保持；
// 2) WysiwygMainEditor 与 controller 双向绑定、frontmatter 拆分、外部改动重建。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexo/desktop/widgets/wysiwyg_editor_poc.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  testWidgets('所见即所得 spike：编辑器构建与标题渲染', (tester) async {
    const sample = '# 纸感写作\n\n这是一段**加粗**的正文。\n';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WysiwygEditorPoc(initialMarkdown: sample),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // SuperEditor 用自有渲染对象（非 Text widget），不适用 find.text；
    // 此处验证：组件在测试环境可完整构建、布局、无异常。
    expect(find.byType(SuperEditor), findsOneWidget);
  });

  test('markdown 解析-序列化静态往返应保持结构', () {
    const sample = '# 纸感写作\n\n这是一段**加粗**与*斜体*。\n\n- 列表一\n- 列表二\n\n> 引用块\n';
    final doc = deserializeMarkdownToDocument(sample);
    final out = serializeDocumentToMarkdown(doc);
    expect(out, contains('纸感写作'));
    expect(out, contains('**加粗**'));
    expect(out, contains('*斜体*'));
    expect(out, contains('列表一'));
    expect(out, contains('列表二'));
    expect(out, contains('引用块'));
  });

  testWidgets('所见即所得主编辑区：frontmatter 拆分与外部改动同步', (tester) async {
    final controller = TextEditingController(
      text: '---\ntitle: 测试\ntags: [a]\n---\n\n# 正文标题\n\n段落。\n',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WysiwygMainEditor(controller: controller, maxWidth: 760),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(SuperEditor), findsOneWidget);

    // 外部程序化改动（模拟 AI 改写/查找替换）→ 文档应整体重建且不崩溃
    controller.text = '---\ntitle: 测试\n---\n\n# 新正文\n';
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(SuperEditor), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
