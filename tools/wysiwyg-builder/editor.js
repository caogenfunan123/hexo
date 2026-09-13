// 手机端 WebView 真·所见即所得编辑器（TipTap/ProseMirror）
// 构建产物 assets/wysiwyg/web/editor.min.js，由 lib/widgets/wysiwyg_web_editor.dart 加载。
// 对外 API：window.WysiwygBridge.init / setMarkdown / setDark / getMarkdown
// 数据流：Dart 发 markdown → 占位保护数学公式 → marked 转 HTML → 还原公式节点
//        → TipTap 文档（KaTeX nodeview 渲染）；编辑 → 防抖 400ms → getHTML →
//        turndown(GFM+公式规则) 转 markdown → callHandler 回 Dart。
// 表格：markdown 表格经 marked(GFM) → TipTap Table 直接渲染为可编辑表格。
// 边界：mermaid 在编辑面内保持代码文本态（渲染由分屏预览负责）；
//       KaTeX 缺失时公式优雅降级为原文。
import { Editor } from '@tiptap/core'
import { Node } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Underline from '@tiptap/extension-underline'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Table from '@tiptap/extension-table'
import TableRow from '@tiptap/extension-table-row'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'
import Placeholder from '@tiptap/extension-placeholder'
import { marked } from 'marked'
import TurndownService from 'turndown'
import { gfm } from 'turndown-plugin-gfm'

let editor = null
let emitTimer = null
let applyingRemote = false

// ── 数学公式占位保护（移植自 MarkdownPreviewBuilder）：
// 先把 $$..$$ / $..$ 摘出来，避免 marked 把公式里的 _ * 当 Markdown 语法 ──
const P = '\uE000'
const E = '\uE001'

function extractMath(md) {
  const blocks = []
  let index = 0
  let text = (md ?? '').replace(
    /\$\$([\s\S]+?)\$\$/g,
    (m, latex) => {
      blocks.push({ latex, display: true })
      return `${P}${index++}${E}`
    },
  )
  // 无 lookbehind（Safari 14 不支持）：用捕获前缀字符的方式排除 "$$" 场景
  text = text.replace(
    /(^|[^\\$])\$([^$\n]+?)\$(?!\$)/g,
    (m, pre, latex) => {
      blocks.push({ latex, display: false })
      return `${pre}${P}${index++}${E}`
    },
  )
  return { text, blocks }
}

function mathHtml(block) {
  const enc = encodeURIComponent(block.latex)
  return block.display
    ? `<div data-math="true" data-display="true" data-latex="${enc}"></div>`
    : `<span data-math="true" data-display="false" data-latex="${enc}"></span>`
}

function restoreMath(html, blocks) {
  // display 公式独占段落时，把 <p> 整体换成块级 div（避免 div 嵌进 p 被拆散）
  html = html.replace(
    new RegExp(`<p>\\s*${P}(\\d+)${E}\\s*</p>`, 'g'),
    (m, idx) => {
      const b = blocks[+idx]
      return b && b.display ? mathHtml(b) : m
    },
  )
  return html.replace(new RegExp(`${P}(\\d+)${E}`, 'g'), (m, idx) => {
    const b = blocks[+idx]
    return b ? mathHtml(b) : m
  })
}

function renderMathNode(el, latex, display) {
  if (window.katex) {
    try {
      window.katex.render(latex, el, {
        throwOnError: false,
        displayMode: display,
      })
      return
    } catch (e) {
      /* 渲染失败回落原文 */
    }
  }
  el.textContent = latex
  el.classList.add('math-raw')
}

// ── TipTap 公式节点（原子节点，nodeview 用 KaTeX 渲染；KaTeX 缺失回落原文） ──
const MathBase = {
  addAttributes() {
    return {
      latex: {
        default: '',
        parseHTML: (el) => decodeURIComponent(el.getAttribute('data-latex') ?? ''),
        renderHTML: (attrs) => ({ 'data-latex': encodeURIComponent(attrs.latex ?? '') }),
      },
      display: {
        default: false,
        parseHTML: (el) => el.getAttribute('data-display') === 'true',
        renderHTML: () => ({}),
      },
    }
  },
  atom: true,
  selectable: true,
  parseHTML() {
    return [this.selector]
  },
  renderHTML({ node }) {
    return [this.tag, {
      'data-math': 'true',
      'data-latex': encodeURIComponent(node.attrs.latex ?? ''),
      'data-display': String(!!node.attrs.display),
    }]
  },
  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement(this.tag)
      dom.setAttribute('data-math', 'true')
      dom.setAttribute('data-display', String(!!node.attrs.display))
      dom.classList.add(node.attrs.display ? 'math-display' : 'math-inline')
      renderMathNode(dom, node.attrs.latex ?? '', !!node.attrs.display)
      return { dom }
    }
  },
}

const MathInline = Node.create({
  ...MathBase,
  name: 'mathInline',
  inline: true,
  group: 'inline',
  tag: 'span',
  selector: 'span[data-math="true"][data-display="false"]',
})

const MathDisplay = Node.create({
  ...MathBase,
  name: 'mathDisplay',
  inline: false,
  group: 'block',
  tag: 'div',
  selector: 'div[data-math="true"][data-display="true"]',
})

const turndown = new TurndownService({
  headingStyle: 'atx',
  codeBlockStyle: 'fenced',
  bulletListMarker: '-',
  emDelimiter: '*',
})
turndown.use(gfm)
// 硬换行保留为两个空格+换行（marked 默认可回解析）
turndown.addRule('hardBreak', {
  filter: (node) => node.nodeName === 'BR',
  replacement: () => '  \n',
})
// 公式节点回转 markdown
turndown.addRule('mathNode', {
  filter: (node) =>
    node.nodeType === 1 && node.hasAttribute && node.hasAttribute('data-math'),
  replacement: (content, node) => {
    const latex = decodeURIComponent(node.getAttribute('data-latex') ?? '')
    if (!latex) return ''
    const display = node.getAttribute('data-display') === 'true'
    return display ? `\n$$${latex}$$\n` : `$${latex}$`
  },
})

marked.setOptions({ gfm: true, breaks: false })

function mdToHtml(md) {
  const { text, blocks } = extractMath(md)
  const html = marked.parse(text)
  return restoreMath(html, blocks)
}

function emitMarkdown() {
  if (!editor || applyingRemote) return
  const md = getMarkdown()
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('wysiwygMarkdown', md)
  }
}

function scheduleEmit() {
  if (applyingRemote) return
  clearTimeout(emitTimer)
  emitTimer = setTimeout(emitMarkdown, 400)
}

function getMarkdown() {
  if (!editor) return ''
  return turndown.turndown(editor.getHTML())
}

window.WysiwygBridge = {
  init({ content = '', dark = false } = {}) {
    dark = !!dark
    document.body.classList.toggle('dark', dark)
    if (editor) {
      editor.destroy()
      editor = null
    }
    editor = new Editor({
      element: document.getElementById('editor'),
      extensions: [
        StarterKit.configure({
          heading: { levels: [1, 2, 3, 4, 5, 6] },
        }),
        Underline,
        Link.configure({ openOnClick: false, autolink: true }),
        Image.configure({ inline: false }),
        Table.configure({ resizable: false }),
        TableRow,
        TableHeader,
        TableCell,
        TaskList,
        TaskItem.configure({ nested: true }),
        MathInline,
        MathDisplay,
        Placeholder.configure({ placeholder: '开始写作，支持 Markdown 语法...' }),
      ],
      content: mdToHtml(content),
      onUpdate: () => scheduleEmit(),
    })
    // 首帧内容即认为已同步，避免 Dart 端误判外部改动
    applyingRemote = true
    setTimeout(() => { applyingRemote = false }, 300)
    return true
  },

  setMarkdown(md) {
    if (!editor) return false
    applyingRemote = true
    try {
      editor.commands.setContent(mdToHtml(md), false)
    } finally {
      // 下一帧再解除保护：确保 setContent 引发的 onUpdate 已被吞掉
      setTimeout(() => { applyingRemote = false }, 60)
    }
    return true
  },

  setDark(d) {
    dark = !!d
    document.body.classList.toggle('dark', dark)
    return true
  },

  getMarkdown,
}
