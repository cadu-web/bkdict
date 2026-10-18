// Rasteriza os ícones a partir dos SVGs em Resources/Icons. Rode à mão quando um SVG mudar:
//   npm i --no-save sharp && node scripts/gen-icons.mjs
import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import sharp from 'sharp'

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const icones = resolve(raiz, 'Resources/Icons')

const SAIDAS = [
  ['app-icon.svg', 'Resources/AppIcon-1024.png', 1024],
  ['app-icon-windows.svg', 'Resources/AppIcon-windows-1024.png', 1024],
  ['menubar-icon.svg', 'Resources/MenuBarIcon.png', 18],
  ['menubar-icon.svg', 'Resources/MenuBarIcon@2x.png', 36],
]

for (const [fonte, saida, lado] of SAIDAS) {
  const svg = readFileSync(resolve(icones, fonte))
  // density na proporção do viewBox: senão o sharp rasteriza no tamanho do viewBox e amplia o bitmap.
  const largura = Number(/viewBox="[\d.]+ [\d.]+ ([\d.]+)/.exec(svg.toString())[1])
  await sharp(svg, { density: 72 * (lado / largura) })
    .resize(lado, lado, { fit: 'fill' })
    .png({ compressionLevel: 9 })
    .toFile(resolve(raiz, saida))
  console.log(`${saida} — ${lado}×${lado}`)
}
