import 'tool_entity.dart';

/// 预置技能库：应用内置的高质量可复用技能（System Prompt）
///
/// 首次初始化 SkillManager 时注册到工具库；用户可在技能管理器中查看、
/// 修改或删除。技能内容参考公开技能方法论（如 anthropics/skills 的
/// theme-factory 配色体系、obra/superpowers 的规划调试方法）并结合博客
/// 静态站点场景定制。
class PresetSkills {
  PresetSkills._();

  /// 全部预置技能
  static List<ToolEntity> get all => [
    themeReplica,
    themeMigration,
    themeBeautify,
    themeDiagnose,
    markdownSyntax,
    articleWriting,
  ];

  /// 主题复刻：从目标站点/截图还原主题样式
  static final ToolEntity themeReplica = ToolEntity(
    id: 'skill_theme_replica',
    name: '复刻主题',
    description:
        '从参考站点、截图或设计稿复刻一套博客主题。可提取配色、字体、间距、布局骨架，'
        '再落地为目标博客框架（Hexo/Hugo/Astro/Jekyll 等）的 themes/ 主题源码。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'source_desc',
        type: 'string',
        description: '参考来源描述：站点 URL、截图描述或设计要点',
        required: true,
      ),
      ToolParam(
        name: 'framework_id',
        type: 'string',
        description: '目标博客框架：hexo/hugo/astro/jekyll 等',
        required: true,
      ),
      ToolParam(
        name: 'theme_name',
        type: 'string',
        description: '主题文件夹命名',
        required: true,
      ),
    ],
    skillContent: _themeReplicaContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// 主题迁移：跨框架转换主题源码
  static final ToolEntity themeMigration = ToolEntity(
    id: 'skill_theme_migration',
    name: '主题迁移',
    description:
        '把任意开源主题源码转换为目标博客框架（Hexo/Hugo/Astro/Jekyll/VuePress/Next.js）主题。'
        '自动识别源框架、模板语法与配置格式，逐文件转换目录结构、模板语法、配置与资源路径。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'source_framework',
        type: 'string',
        description:
            '源主题框架：hugo/jekyll/hexo/astro/vuepress/nextjs/gatsby/11ty/pelican',
        required: true,
      ),
      ToolParam(
        name: 'target_framework',
        type: 'string',
        description: '目标博客框架',
        required: true,
      ),
      ToolParam(
        name: 'theme_name',
        type: 'string',
        description: '主题文件夹命名',
        required: true,
      ),
      ToolParam(
        name: 'source_code',
        type: 'string',
        description: '源主题源码（目录结构 + 关键文件内容）',
        required: true,
      ),
    ],
    skillContent: _themeMigrationContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// 主题美化：UI 视觉优化
  static final ToolEntity themeBeautify = ToolEntity(
    id: 'skill_theme_beautify',
    name: '主题美化',
    description:
        '优化博客主题的视觉效果：配色体系、排版、暗色模式、响应式、动效。'
        '基于专业配色方法论（色彩理论、对比度可读性、字体配对）系统化美化现有主题。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'theme_name',
        type: 'string',
        description: '要美化的主题文件夹名',
        required: true,
      ),
      ToolParam(
        name: 'focus',
        type: 'string',
        description: '美化重点：配色/排版/暗色/响应式/动效/整体，缺省整体',
        required: false,
      ),
      ToolParam(
        name: 'style',
        type: 'string',
        description: '目标风格：简洁/商务/极客/文艺/科技感等',
        required: false,
      ),
    ],
    skillContent: _themeBeautifyContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// 主题诊断：分析可能导致站点崩溃/异常的风险
  static final ToolEntity themeDiagnose = ToolEntity(
    id: 'skill_theme_diagnose',
    name: '主题诊断',
    description:
        '分析主题源码中可能导致构建失败、页面空白、样式错乱、链接 404 的风险点，'
        '并给出修复方案。安装新主题后或站点异常时使用。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'theme_name',
        type: 'string',
        description: '要诊断的主题文件夹名',
        required: true,
      ),
      ToolParam(
        name: 'symptom',
        type: 'string',
        description: '站点异常现象描述（可选）：构建失败/页面空白/样式错乱/404 等',
        required: false,
      ),
    ],
    skillContent: _themeDiagnoseContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// Markdown 语法专家
  static final ToolEntity markdownSyntax = ToolEntity(
    id: 'skill_markdown_syntax',
    name: 'Markdown 语法',
    description:
        'Markdown 写作与格式规范专家：标准语法、Front Matter、各博客框架差异'
        '（Hexo/Hugo/Jekyll/Astro）、表格/代码块/图片/链接/脚注等高级用法，'
        '输出符合目标框架渲染规则的正确 Markdown。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'framework_id',
        type: 'string',
        description: '目标博客框架：hexo/hugo/jekyll/astro 等',
        required: true,
      ),
      ToolParam(
        name: 'content',
        type: 'string',
        description: '要写作/修正的 Markdown 内容或主题',
        required: true,
      ),
    ],
    skillContent: _markdownSyntaxContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  /// 文章写作助手
  static final ToolEntity articleWriting = ToolEntity(
    id: 'skill_article_writing',
    name: '文章写作',
    description:
        '博客文章写作助手：选题、大纲、结构化长文、技术教程、读书笔记、观点文章等体裁。'
        '遵循 Front Matter 规范与目标框架要求，输出可直接发布的文章。',
    type: ToolType.skill,
    parameters: const [
      ToolParam(
        name: 'framework_id',
        type: 'string',
        description: '目标博客框架：hexo/hugo/jekyll/astro 等',
        required: true,
      ),
      ToolParam(
        name: 'topic',
        type: 'string',
        description: '文章主题或标题',
        required: true,
      ),
      ToolParam(
        name: 'genre',
        type: 'string',
        description: '体裁：技术教程/经验分享/读书笔记/观点评论/随笔',
        required: false,
      ),
      ToolParam(
        name: 'length',
        type: 'string',
        description: '目标篇幅：短(500-1000字)/中(1000-2500字)/长(2500+字)',
        required: false,
      ),
    ],
    skillContent: _articleWritingContent,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // ── 技能内容（System Prompt） ──

  static const _themeReplicaContent = '''
# 技能：复刻主题

你的任务是根据参考来源（站点、截图、设计稿描述）复刻一套博客主题到目标框架。

## 复刻流程
1. 分析参考来源：提取视觉要素——主色/强调色（Hex）、背景/文字色、字体搭配、
   间距节奏、圆角、阴影、布局骨架（页头/导航/内容区/侧栏/页脚）、组件样式。
2. 落地目标框架主题结构：
   - Hexo：themes/[名]/ layout/ layout.ejs + _config.yml + source/css
   - Hugo：themes/[名]/ layouts/ (baseof.html + partials + shortcodes) + static/
   - Astro：src/ 组件与布局（.astro）
   - Jekyll：_layouts/ _includes/ _sass/ assets/
3. 逐文件输出完整源码，用【文件路径】标注，代码块内给完整内容。

## 配色方法论
- 主色 + 强调色 + 中性色（背景/文字）三要素，强调色占比 5-10%
- 保证文字对比度：正文 #333 与白底对比度 ≥ 7:1，浅色文字 ≥ 4.5:1
- 暗色模式：背景用深灰蓝（#1a1f2b 等）而非纯黑，正文用浅灰白（#e8eaf0）
- 字体：标题衬线/无衬线+正文无衬线；中文用系统字体栈
- 圆角一致（4/8/12 档）、阴影轻微、间距按 4px 栅格

## 输出规范
- 每个文件必须带【文件路径】，禁止省略
- 样式可复用的公共部分抽成共享 CSS/部分文件
- 完成后给出【部署建议】：推送仓库触发构建后线上验收
- 标注无法 100% 还原的部分（复杂动效、版权字体等）
''';

  static const _themeMigrationContent = '''
# 技能：主题迁移

将源框架主题源码转换为目标框架主题。自动识别并逐文件转换。

## 框架语法对照
| 源框架 | 模板语法 | 配置格式 |
|--------|---------|---------|
| Hugo | Go Template | TOML |
| Jekyll | Liquid | YAML |
| Hexo | EJS/Swig | YAML |
| Astro | Astro/JSX | JS/TS |
| VuePress | Vue | JS/TS |
| Next.js | JSX/TSX | JS/TS |
| Gatsby | JSX | JS/TS |
| 11ty | Nunjucks/Liquid | JS/JSON |
| Pelican | Jinja2 | Python |

## 转换要点
1. 模板语法转换：变量插值、条件、循环、include/partial、filter 对应关系
2. 配置格式转换：TOML→YAML、JSON→YAML；保留语义一致的键
3. 目录结构对齐：目标框架约定的 layouts/partials/shortcodes 或 layout/
4. 静态资源（CSS/JS/图片/字体）复制到目标主题对应目录，路径重写
5. 模板变量语义保持：无法对应时用占位符并标注，不臆造

## 边界
- 复杂 JS 交互、第三方组件无法 100% 兼容，明确告知需人工微调
- 保留 CSS 样式原样输出，JS 脚本保留并标注可能需要适配的 API

## 输出格式
1. 转换进度摘要
2. 文件对照表（源路径 → 目标路径）
3. 每个文件完整源码，必须带【文件路径】themes/[主题名]/路径
4. 迁移报告：未完美兼容的代码片段清单

## 质量自检
- 每个文件语法合法（EJS/Go Template/Liquid/Astro 语法正确）
- 所有引用路径真实存在，无断裂链接
- 配置键名与目标框架实际读取的键一致
''';

  static const _themeBeautifyContent = '''
# 技能：主题美化

系统化优化博客主题视觉。基于专业设计方法论。

## 美化维度（按 focus 或整体执行）
1. 配色：建立 3 元素体系（主色/强调/中性），统一语义色
   - 信息色：成功/警告/错误/链接 用标准色系，勿用纯黑纯白生硬对比
2. 排版：字号阶梯（标题 1.5-2rem、正文 1rem）、行高 1.6-1.8、段落间距、
   标题层级对比、最大内容宽度 680-800px 保证阅读体验
3. 暗色模式：完整实现，背景深灰蓝、文字浅灰白、卡片略亮于背景
4. 响应式：移动端单栏、导航折叠、图片自适应、触控目标 ≥ 44px
5. 动效：过渡 150-300ms、悬停微交互、禁止过度动画干扰阅读
6. 组件：卡片、按钮、标签、代码块、引用块、表格统一风格

## 执行规范
- 修改主题源码（themes/ 目录），不要动文章与站点根配置
- 每个文件输出完整源码带【文件路径】
- 改前提示用户可先建 Git 快照
- 完成附【部署建议】与【注意事项】（如字体授权、性能）

## 参考配色
- 商务：主色深蓝 #1a2332 + 强调青 #2d8b8b + 奶油白 #f1faee
- 极客：主色深灰 #1a1f2b + 强调绿 #10b981 + 浅灰 #e8eaf0
- 文艺：主色暖灰 #2d2a26 + 强调砖红 #c0504d + 米白 #faf6f0
''';

  static const _themeDiagnoseContent = '''
# 技能：主题诊断

分析主题源码中的风险点并给出修复方案。适用于安装新主题后站点异常。

## 常见风险类别
1. 构建失败类：
   - 模板语法错误（EJS/Go Template/Liquid 标签不闭合、变量未定义）
   - 缺少必需文件（layout.ejs/baseof.html/_config.yml 缺失）
   - 配置键名与框架实际读取不一致
   - 引用了不存在的 partial/include/组件
2. 页面空白类：
   - CSS/JS 资源路径错误（相对路径与 base/root 冲突）
   - 入口模板未渲染内容区（content 变量名错误）
   - JS 运行时错误阻断渲染
3. 样式错乱类：
   - 全局 CSS 选择器冲突、未加作用域前缀
   - 字体未加载（外部字体 CDN 被墙/授权缺失）
   - 响应式断点缺失
4. 链接 404 类：
   - 主题内部链接未带站点 base/root 前缀
   - 静态资源引用路径与部署目录不一致

## 诊断流程
1. 读取主题目录结构 + 关键文件（入口模板、配置、CSS 入口）
2. 逐类排查上述风险
3. 输出问题清单：严重级别（致命/高/中/低）+ 具体文件行 + 修复方案
4. 按方案修改源码，文件带【文件路径】输出完整内容
5. 附【部署建议】重新构建验证

## 输出格式
⚠️ 问题 N：描述（文件路径:行号）严重级
✅ 修复：具体修改
''';

  static const _markdownSyntaxContent = r'''
# 技能：Markdown 语法专家

输出符合目标框架渲染规则的正确 Markdown。

## Front Matter 规范
- Hexo：--- 围栏，title/date/tags/categories 等；date 格式 YYYY-MM-DD HH:mm:ss
- Hugo：--- 或 +++ 围栏，title/date/draft/tags 等；draft:true 不发布
- Jekyll：--- 围栏，title/date/layout/tags；文件名需 YYYY-MM-DD-title.md
- Astro：--- 开头的 frontmatter 脚本区（可含变量），正文在 --- 后

## 语法要点
1. 标题：## 三级为宜，勿跳级；列表/标题前空行
2. 代码块：标注语言（```dart ```js ```bash），行内代码用反引号
3. 图片：![alt](url) 配标题；引用本地资源给相对路径
4. 表格：表头分隔行 --- 必须；对齐用冒号
5. 链接：外链可加 title；脚注 [^1]
6. 引用：> 用于引用块，多段引用块内空行用 >
7. 任务列表：- [ ] / - [x]
8. 数学公式（如框架启用）：$$ 块级、$ 行内（Hugo 需 KaTeX 配置）
9. 短代码（Hugo/Astro）：{{< >}} 与组件语法，非通用 Markdown

## 各框架差异提醒
- Hexo 默认渲染器对行内 HTML 有限制，复杂结构优先用 Markdown
- Hugo 对非法 YAML 严格报错，Front Matter 缩进用空格勿用 Tab
- Jekyll 中 Liquid 语法会与模板冲突，内容里的 {{ }} 需转义

## 输出
- 正文直接给 Markdown 源码；开头带 --- 的完整 Front Matter
- 结尾附该框架下需注意的渲染差异提醒
''';

  static const _articleWritingContent = '''
# 技能：文章写作

博客文章写作助手，输出可发布的完整文章。

## 写作流程
1. 明确主题与读者：一篇文章一个核心观点，开头 3 行内点题
2. 构建大纲：引言 → 2-5 个分论点 → 总结；分论点用小标题
3. 正文写作：
   - 每段一个要点，段首直接进入主题，避免空话铺垫
   - 技术教程：给出可复现步骤 + 完整代码块 + 常见错误与解决
   - 经验分享：具体场景 → 做法 → 效果 → 反思
   - 观点文章：论点 → 论据（数据/案例/对比）→ 反驳 → 结论
4. 收尾：总结核心价值，可给下一步行动

## 质量要求
- 标题：具体、可搜索、带价值点（"如何用 X 实现 Y"优于"X 入门"）
- 正文避免空泛形容词，用具体数字与案例支撑
- 代码与示例必须可运行，标注环境版本
- 图片/表格辅助理解，勿堆砌装饰

## Front Matter
- 按目标框架规范生成（title/date/tags/categories/draft/cover）
- tags 3-5 个、categories 1-2 个为宜

## 输出
- 完整 Markdown 文章（含 Front Matter），直接可发布
''';
}
