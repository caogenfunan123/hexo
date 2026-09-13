// 手机端 WebView 真·所见即所得编辑器（TipTap/ProseMirror）
// 构建产物 assets/wysiwyg/web/editor.min.js，由 lib/widgets/wysiwyg_web_editor.dart 加载。
// 对外 API：window.WysiwygBridge.init / setMarkdown / setDark / getMarkdown
// 数据流：Dart 发 markdown → marked 转 HTML → TipTap 文档；
//        编辑 → 防抖 400ms → getHTML → turndown(GFM) 转 markdown → callHandler 回 Dart。
// 边界（v1）：数学公式/mermaid 在编辑面内保持代码文本态（由分屏预览负责渲染），
// 避免在 ProseMirror 文档下做外部 DOM 变异导致文档与视图失同步。
import { Editor } from '@tiptap/core'
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
  return marked.parse(md ?? '')
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
