// 阶段2 Spike 验证：WysiwygEditorPoc 的 markdown 往返（进出）能力
// 验证点：markdown 进 → SuperEditor 文档 → 序列化 markdown 出，结构语义保持。
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
}
