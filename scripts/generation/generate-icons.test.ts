import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import sharp from "sharp";
import { ROOT } from "../shared/runtime.ts";

test("Apple catalogs reference icons of the declared sizes and iOS has no alpha channel", async () => {
  for (const platform of ["ios", "macos"]) {
    const root = join(ROOT, "frontend", platform, "Runner/Assets.xcassets/AppIcon.appiconset");
    const catalog = await Bun.file(join(root, "Contents.json")).json();
    for (const entry of catalog.images) {
      const image = await sharp(await readFile(join(root, entry.filename))).metadata();
      const size = Number.parseFloat(entry.size) * Number.parseFloat(entry.scale);
      expect([image.width, image.height]).toEqual([size, size]);
      if (platform === "ios") expect(image.hasAlpha).toBe(false);
    }
  }
  const touch = await sharp(await readFile(join(ROOT, "frontend/web/icons/apple-touch-icon.png"))).metadata();
  expect([touch.width, touch.height, touch.hasAlpha]).toEqual([180, 180, false]);
});

test("PWA maskable icons keep all foreground pixels inside the minimum safe circle", async () => {
  for (const size of [192, 512]) {
    const file = await readFile(join(ROOT, `frontend/web/icons/Icon-maskable-${size}.png`));
    expect((await sharp(file).metadata()).hasAlpha).toBe(false);
    const { data, info } = await sharp(file).raw().toBuffer({ resolveWithObject: true });
    let foregroundPixels = 0;
    let greatestRadius = 0;
    for (let y = 0; y < info.height; y++) {
      for (let x = 0; x < info.width; x++) {
        const offset = (y * info.width + x) * info.channels;
        if (Math.abs(data[offset]! - 173) + Math.abs(data[offset + 1]! - 68) + Math.abs(data[offset + 2]! - 51) < 8) continue;
        foregroundPixels++;
        greatestRadius = Math.max(greatestRadius, Math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2));
      }
    }
    expect(foregroundPixels).toBeGreaterThan(size * size * 0.1);
    expect(greatestRadius).toBeLessThanOrEqual(size * 0.4);
  }
});

test("Windows ICO directories point to complete decodable PNG frames at every shell size", async () => {
  const ico = await readFile(join(ROOT, "frontend/windows/runner/resources/app_icon.ico"));
  const sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
  expect(ico.readUInt16LE(0)).toBe(0);
  expect(ico.readUInt16LE(2)).toBe(1);
  expect(ico.readUInt16LE(4)).toBe(sizes.length);
  let expectedOffset = 6 + sizes.length * 16;
  for (const [index, size] of sizes.entries()) {
    const entry = 6 + index * 16;
    expect(ico[entry] || 256).toBe(size);
    expect(ico[entry + 1] || 256).toBe(size);
    const length = ico.readUInt32LE(entry + 8);
    const offset = ico.readUInt32LE(entry + 12);
    expect(offset).toBe(expectedOffset);
    const frame = ico.subarray(offset, offset + length);
    const metadata = await sharp(frame).metadata();
    expect([metadata.format, metadata.width, metadata.height, metadata.hasAlpha]).toEqual(["png", size, size, true]);
    await sharp(frame).raw().toBuffer();
    expectedOffset += length;
  }
  expect(expectedOffset).toBe(ico.length);
});
