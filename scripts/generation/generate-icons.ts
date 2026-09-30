import { mkdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import sharp from "sharp";
import { ROOT, runCLI } from "../shared/runtime.ts";

const paper = "#FFFDF7";
export const iconSizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];

export function windowsIcon(frames: { size: number; png: Buffer }[]): Buffer {
  const header = Buffer.alloc(6 + frames.length * 16);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(frames.length, 4);
  let offset = header.length;
  for (const [index, frame] of frames.entries()) {
    const entry = 6 + index * 16;
    header[entry] = frame.size === 256 ? 0 : frame.size;
    header[entry + 1] = header[entry]!;
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(frame.png.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += frame.png.length;
  }
  return Buffer.concat([header, ...frames.map(frame => frame.png)]);
}

export async function generateIcons(root = ROOT): Promise<Map<string, Buffer>> {
  const source = await readFile(join(root, "frontend/assets/branding/domabas-mark.svg"), "utf8");
  const group = /<g fill="(#[A-Fa-f0-9]{6})" fill-rule="evenodd">([\s\S]*?)<\/g>/.exec(source);
  if (!group || !source.includes('viewBox="0 0 128 128"')) throw new Error("Expected the 128px Filed Paper SVG master.");
  const rust = group[1]!;
  const paths = [...group[2]!.matchAll(/<path d="([^"]+)"\s*\/>/g)].map(match => match[1]!);
  if (paths.length !== 2 || group[2]!.replace(/<path d="[^"]+"\s*\/>/g, "").trim()) {
    throw new Error("Filed Paper must contain exactly two filled paths.");
  }
  const output = new Map<string, Buffer>();
  const add = (path: string, content: string | Buffer) => output.set(path, Buffer.isBuffer(content) ? content : Buffer.from(content));
  const glyph = (color: string) => `<g fill="${color}" fill-rule="evenodd">${paths.map(path => `<path d="${path}"/>`).join("")}</g>`;
  const svg = (content: string) => `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><title>Domabas — Filed Paper</title>${content}</svg>\n`;
  const background = (rounded: boolean) => `<rect width="128" height="128" rx="${rounded ? 28 : 0}" fill="${rust}"/>`;
  const scale = (content: string, factor: number) => `<g transform="translate(${64 * (1 - factor)} ${64 * (1 - factor)}) scale(${factor})">${content}</g>`;
  const square = svg(background(false) + glyph(paper));
  const rounded = svg(background(true) + glyph(paper));
  const desktop = svg(scale(background(true) + glyph(paper), 0.8));
  const maskable = svg(background(false) + scale(glyph(paper), 0.88));
  const mark = svg(glyph(rust));
  const render = async (art: string, size: number, opaque = false): Promise<Buffer> => {
    let image = sharp(Buffer.from(art), { density: 72 * size / 128 }).resize(size, size);
    if (opaque) image = image.removeAlpha();
    return image.png({ compressionLevel: 9 }).toBuffer();
  };

  add("frontend/assets/branding/domabas-app.svg", square);
  add("frontend/assets/branding/domabas-mark.png", await render(mark, 256));
  add("frontend/web/favicon.svg", rounded);
  add("frontend/web/favicon.png", await render(rounded, 32));
  add("frontend/web/icons/apple-touch-icon.png", await render(square, 180, true));
  for (const size of [192, 512]) {
    add(`frontend/web/icons/Icon-${size}.png`, await render(rounded, size));
    add(`frontend/web/icons/Icon-maskable-${size}.png`, await render(maskable, size, true));
  }

  const ios = "frontend/ios/Runner/Assets.xcassets/AppIcon.appiconset";
  const catalog: { images: { filename: string; size: string; scale: string }[] } = JSON.parse(await readFile(join(root, ios, "Contents.json"), "utf8"));
  for (const entry of catalog.images) {
    const size = Number.parseFloat(entry.size) * Number.parseFloat(entry.scale);
    if (!Number.isInteger(size) || size < 1 || size > 1024) throw new Error(`Invalid Apple icon size: ${entry.filename}`);
    add(`${ios}/${entry.filename}`, await render(square, size, true));
  }
  for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
    add(`frontend/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${size}.png`, await render(desktop, size));
  }
  const frames = [];
  for (const size of iconSizes) frames.push({ size, png: await render(rounded, size) });
  add("frontend/windows/runner/resources/app_icon.ico", windowsIcon(frames));
  add("frontend/linux/runner/resources/app_icon.png", await render(rounded, 256));

  const android = "frontend/android/app/src/main/res";
  for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
    add(`${android}/mipmap-${density}/ic_launcher.png`, await render(rounded, size));
  }
  const vectorPaths = paths.map(path => `    <path android:fillColor="${paper}" android:fillType="evenOdd" android:pathData="${path}"/>`).join("\n");
  add(`${android}/drawable/ic_launcher_foreground.xml`, `<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="128" android:viewportHeight="128">
  <group android:scaleX="0.72" android:scaleY="0.72" android:translateX="17.92" android:translateY="17.92">
${vectorPaths}
  </group>
</vector>
`);
  add(`${android}/values/icon_colors.xml`, `<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="ic_launcher_background">${rust}</color>
</resources>
`);
  for (const api of [26, 33]) {
    add(`${android}/mipmap-anydpi-v${api}/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
${api >= 33 ? '  <monochrome android:drawable="@drawable/ic_launcher_foreground"/>\n' : ""}</adaptive-icon>
`);
  }
  return output;
}

if (import.meta.main) await runCLI(async scope => {
  const args = Bun.argv.slice(2);
  if (args.some(arg => arg !== "--check")) throw new Error("Usage: task generate:icons [-- --check]");
  const check = args.includes("--check");
  const outputs = await generateIcons();
  const different: string[] = [];
  for (const [relative, content] of outputs) {
    scope.signal.throwIfAborted();
    const path = join(ROOT, relative);
    if (check) {
      const current = await Bun.file(path).exists() ? await readFile(path) : null;
      if (!current?.equals(content)) different.push(relative);
    } else {
      await mkdir(dirname(path), { recursive: true });
      await Bun.write(path, content);
    }
  }
  if (different.length) throw new Error(`Run task generate:icons; generated icons differ:\n${different.join("\n")}`);
  console.log(`${check ? "Verified" : "Generated"} ${outputs.size} Filed Paper icon assets.`);
});
