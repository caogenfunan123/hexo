// 无 DOM 环境验证 editor.js 的数学占位提取/还原逻辑（与源码保持同正则）
const P = '\uE000', E = '\uE001'

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
  text = text.replace(
    /(^|[^\\$])\$([^$\n]+?)\$(?!\$)/g,
    (m, pre, latex) => {
      blocks.push({ latex, display: false })
      return `${pre}${P}${index++}${E}`
    },
  )
  return { text, blocks }
}

function mathHtml(b) {
  const enc = encodeURIComponent(b.latex)
  return b.display
    ? `<div data-math="true" data-display="true" data-latex="${enc}"></div>`
    : `<span data-math="true" data-display="false" data-latex="${enc}"></span>`
}

function restoreMath(html, blocks) {
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

const md = [
  '行内 $a_b^2+c$ 公式。',
  '',
  '$$E=mc^2$$',
  '',
  '价格 $5 和 $3 单独出现不成对，不应误伤。',
  '',
  '$$x_1 = 1$$',
].join('\n')

const { text, blocks } = extractMath(md)
console.log('blocks =', JSON.stringify(blocks))
// 模拟 marked 输出：每个占位符独占 <p>
const fakeHtml = blocks
  .map((b, i) => `<p>${P}${i}${E}</p>`)
  .join('\n')
const out = restoreMath(fakeHtml, blocks)
console.log(out)
console.log('decode check:', decodeURIComponent(
  out.match(/data-latex="([^"]+)"/)[1],
))
