// 构建 WebView 所见即所得编辑器单文件 bundle：
//   node build.mjs
// 产物: ../../assets/wysiwyg/web/editor.min.js（IIFE，暴露 window.WysiwygBridge）
// 依赖先 npm install；TipTap/版本升级后重跑本脚本并提交产物。
import * as esbuild from 'esbuild'

await esbuild.build({
  entryPoints: ['editor.js'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['chrome90', 'safari14'],
  outfile: '../../assets/wysiwyg/web/editor.min.js',
  legalComments: 'none',
  logLevel: 'info',
})
console.log('editor.min.js 构建完成')
