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
const C = '\uE002'
const D = '\uE003'

// 把围栏代码块与行内代码段替换为占位符，避免其中的 $ 被当成公式。
// 只在 extractMath 内部使用：抽完公式后立即原样还原，marked 仍解析原始代码。
function protectCode(md, segs) {
  const protectInline = (line) => {
    let out = ''
    let i = 0
    while (i < line.length) {
      if (line[i] === '`') {
        const ticks = /^`+/.exec(line.slice(i))[0]
        const end = line.indexOf(ticks, i + ticks.length)
        if (end !== -1) {
          segs.push(line.slice(i, end + ticks.length))
          out += `${C}${segs.length - 1}${D}`
          i = end + ticks.length
          continue
        }
      }
      out += line[i]
      i++
    }
    return out
  }
  const lines = (md ?? '').split('\n')
  let inFence = false
  let fenceChar = ''
  return lines
    .map((line) => {
      if (inFence) {
        segs.push(line)
        if (new RegExp(`^\\s{0,3}\\${fenceChar}{3,}\\s*$`).test(line)) inFence = false
        return `${C}${segs.length - 1}${D}`
      }
      const open = line.match(/^\s{0,3}(`{3,}|~{3,})/)
      if (open) {
        inFence = true
        fenceChar = open[1][0]
        segs.push(line)
        return `${C}${segs.length - 1}${D}`
      }
      return protectInline(line)
    })
    .join('\n')
}

function extractMath(md) {
  const blocks = []
  const codeSegs = []
  let index = 0
  let text = protectCode(md, codeSegs)
  text = text.replace(
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
  // 公式抽取完毕，还原代码段再交给 marked
  text = text.replace(new RegExp(`${C}(\\d+)${D}`, 'g'), (m, i) => codeSegs[+i] ?? m)
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

// ── TipTap 公式节点工厂（原子节点，nodeview 用 KaTeX 渲染；KaTeX 缺失回落原文） ──
// 注意：TipTap 把扩展字段函数 bind 到 {name,options,storage,editor,parent}，
// 自定义 config 键（tag/selector）在 this 上取不到（this.selector 为 undefined，
// parseHTML 返回 [undefined] → schema 构建抛 "style" in undefined → 编辑器整体起不来）。
// 因此 tag/selector 必须用闭包捕获，不能走 this。
function createMathNode({ name, tag, selector, inline, group }) {
  return Node.create({
    name,
    inline,
    group,
    atom: true,
    selectable: true,
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
    parseHTML() {
      return [{ tag: selector }]
    },
    renderHTML({ node }) {
      return [tag, {
        'data-math': 'true',
        'data-latex': encodeURIComponent(node.attrs.latex ?? ''),
        'data-display': String(!!node.attrs.display),
      }]
    },
    addNodeView() {
      return ({ node }) => {
        const dom = document.createElement(tag)
        dom.setAttribute('data-math', 'true')
        dom.setAttribute('data-display', String(!!node.attrs.display))
        dom.classList.add(node.attrs.display ? 'math-display' : 'math-inline')
        renderMathNode(dom, node.attrs.latex ?? '', !!node.attrs.display)
        return { dom }
      }
    },
  })
}

const MathInline = createMathNode({
  name: 'mathInline',
  tag: 'span',
  selector: 'span[data-math="true"][data-display="false"]',
  inline: true,
  group: 'inline',
})

const MathDisplay = createMathNode({
  name: 'mathDisplay',
  tag: 'div',
  selector: 'div[data-math="true"][data-display="true"]',
  inline: false,
  group: 'block',
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

marked.setOptions({ gfm: true, breaks: false })

function mdToHtml(md) {
  const { text, blocks } = extractMath(md)
  const html = marked.parse(text)
  return restoreMath(html, blocks)
}

// ── HTML → markdown（占位符方案） ──
// turndown 的 forNode 对 isBlank 节点直接走内置 blankRule 返回空串，
// 自定义规则根本不会被调用——公式节点（无文本内容）与用户敲出的空段落
// 都会在每次编辑回写时被吞掉。因此先把它们替换成占位文本（非空白字符，
// isBlank 为 false），转完再还原为 markdown。
function htmlToMarkdown(html) {
  const doc = new DOMParser().parseFromString(html, 'text/html')
  const slots = []
  // 1) 公式节点 → 占位文本（display 独占段落，保持块级语义）
  doc.querySelectorAll('[data-math]').forEach((el) => {
    const idx = slots.length
    slots.push({
      latex: decodeURIComponent(el.getAttribute('data-latex') ?? ''),
      display: el.getAttribute('data-display') === 'true',
    })
    if (slots[idx].display) {
      const p = doc.createElement('p')
      p.textContent = P + idx + E
      el.replaceWith(p)
    } else {
      el.replaceWith(doc.createTextNode(P + idx + E))
    }
  })
  // 2) 空段落（含 &nbsp;，多为块级图片提升后遗留）直接删除：
  //    turndown 已在段落后输出段落分隔符，占位还原 '' 反而多出一组换行
  doc.querySelectorAll('p').forEach((el) => {
    if (el.textContent.trim() === '' && !el.querySelector('[data-math]')) {
      el.remove()
    }
  })
  // 3) 剥掉 colgroup：turndown-plugin-gfm 的表格规则遇到它直接放弃，整表退化为裸 HTML
  doc.querySelectorAll('colgroup').forEach((el) => el.remove())
  // 4) 单元格与列表项内是块级 <p>，gfm 规则只认内联内容：
  //    表格退化为裸 HTML，列表被判成松散格式（"-   " + 项内空行），先拆掉
  doc.querySelectorAll('td, th, li').forEach((el) => {
    while (el.firstElementChild && el.firstElementChild.tagName === 'P') {
      const p = el.firstElementChild
      while (p.firstChild) el.insertBefore(p.firstChild, p)
      p.remove()
    }
  })
  let md = turndown.turndown(doc.body.innerHTML)
  md = md.replace(new RegExp(`${P}(\\d+)${E}`, 'g'), (m, i) => {
    const s = slots[+i]
    if (!s) return m
    return s.display ? `$$${s.latex}$$` : `$${s.latex}$`
  })
  return md
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
  return htmlToMarkdown(editor.getHTML())
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
