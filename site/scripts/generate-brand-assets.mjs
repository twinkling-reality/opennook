import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const publicDir = path.join(repoRoot, 'site/public');
const appIconDir = path.join(repoRoot, 'App/Assets.xcassets/AppIcon.appiconset');

// The mark's inner drawing (defs and paths), lifted from public/nook-mark.svg so
// every generated asset uses the same trace of the logo.
const markSvg = fs.readFileSync(path.join(publicDir, 'nook-mark.svg'), 'utf8');
const markViewBox = markSvg.match(/viewBox="([^"]+)"/)[1];
const markInner = markSvg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const markAspect = 1056 / 189;

const placeMark = (x, y, width) =>
  `<svg x="${x}" y="${y}" width="${width}" height="${width / markAspect}" viewBox="${markViewBox}">${markInner}</svg>`;

const ogSvg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" fill="none">
  <rect width="1200" height="630" fill="#f7f9fb"/>
  ${placeMark(360, 190, 480)}
  <text x="600" y="420" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="56" font-weight="600" fill="#131a21" letter-spacing="-1.5">OpenNook</text>
  <text x="600" y="470" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="28" font-weight="400" fill="#56616d">Notch apps for macOS</text>
</svg>
`;

// Icons sit the mark on a light tile. At icon sizes the logo's pale gradient
// all but vanishes against it, so they use the deeper stops from the first
// version of the logo, the same hues at more strength.
const deepStops = [
  ['#d6ecfd', '#8fd3fd'],
  ['#cbd6fb', '#8590fd'],
  ['#d1cdfc', '#a99efc'],
  ['#e3c9fb', '#d9a8fb'],
];
const deepInner = deepStops.reduce((inner, [pale, deep]) => inner.replace(pale, deep), markInner);

const appIconSvg = (size) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" fill="none">
  <rect width="${size}" height="${size}" rx="${size * 0.22}" fill="#f7f9fb"/>
  <rect x="${size / 64}" y="${size / 64}" width="${size - size / 32}" height="${size - size / 32}" rx="${size * 0.22 - size / 64}" stroke="#131a21" stroke-opacity="0.1" stroke-width="${size / 32}"/>
  <svg x="${size * 0.08}" y="${size / 2 - (size * 0.84) / markAspect / 2}" width="${size * 0.84}" height="${(size * 0.84) / markAspect}" viewBox="${markViewBox}">${deepInner}</svg>
</svg>
`;

async function writePng(svg, destination, width, height = width) {
  await sharp(Buffer.from(svg))
    .resize(width, height)
    .png()
    .toFile(destination);
}

fs.mkdirSync(appIconDir, { recursive: true });

const iconSizes = [
  ['icon_16.png', 16],
  ['icon_32.png', 32],
  ['icon_32@1x.png', 32],
  ['icon_64.png', 64],
  ['icon_128.png', 128],
  ['icon_256.png', 256],
  ['icon_512.png', 512],
  ['icon_1024.png', 1024],
];

for (const [filename, size] of iconSizes) {
  await writePng(appIconSvg(size), path.join(appIconDir, filename), size);
}

await writePng(ogSvg, path.join(publicDir, 'og-image.png'), 1200, 630);
await writePng(appIconSvg(180), path.join(publicDir, 'apple-touch-icon.png'), 180, 180);

fs.writeFileSync(
  path.join(appIconDir, 'Contents.json'),
  JSON.stringify(
    {
      images: [
        { size: '16x16', idiom: 'mac', filename: 'icon_16.png', scale: '1x' },
        { size: '16x16', idiom: 'mac', filename: 'icon_32.png', scale: '2x' },
        { size: '32x32', idiom: 'mac', filename: 'icon_32@1x.png', scale: '1x' },
        { size: '32x32', idiom: 'mac', filename: 'icon_64.png', scale: '2x' },
        { size: '128x128', idiom: 'mac', filename: 'icon_128.png', scale: '1x' },
        { size: '128x128', idiom: 'mac', filename: 'icon_256.png', scale: '2x' },
        { size: '256x256', idiom: 'mac', filename: 'icon_512.png', scale: '1x' },
        { size: '256x256', idiom: 'mac', filename: 'icon_1024.png', scale: '2x' },
      ],
      info: { version: 1, author: 'xcode' },
    },
    null,
    2
  )
);

console.log('Generated brand PNGs (og-image, app icon set, apple-touch-icon).');
