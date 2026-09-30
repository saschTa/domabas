import { afterEach, describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { lstat, mkdir, mkdtemp, readlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { archivePath, browserExecutables, browserTarget, extractZip } from "./browser/browser-tools.ts";
import { changedFiles, snapshot } from "../generation/check-generated.ts";
import { composeDatabaseURL, portValue, schemaURL, withTemporarySchema } from "./e2e.ts";
import { replaceDirectory } from "../generation/generate-client.ts";

const temporary: string[] = [];
async function directory(): Promise<string> { const dir = await mkdtemp(join(tmpdir(), "domabas-tooling-test-")); temporary.push(dir); return dir; }
afterEach(async () => { await Promise.all(temporary.splice(0).map(path => rm(path, { recursive: true, force: true }))); });

function zip(entries: { name: string; data: string; mode?: number }[]): Buffer {
  const files: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name), data = Buffer.from(entry.data), crc = Bun.hash.crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(name.length, 26);
    files.push(local, name, data);
    const record = Buffer.alloc(46);
    record.writeUInt32LE(0x02014b50, 0); record.writeUInt16LE(0x0314, 4); record.writeUInt16LE(20, 6);
    record.writeUInt32LE(crc, 16); record.writeUInt32LE(data.length, 20); record.writeUInt32LE(data.length, 24);
    record.writeUInt16LE(name.length, 28); record.writeUInt32LE(((entry.mode ?? 0o100644) << 16) >>> 0, 38); record.writeUInt32LE(offset, 42);
    central.push(record, name); offset += local.length + name.length + data.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...files, directory, end]);
}

describe("browser archive", () => {
  test("rejects traversal, absolute paths, drive paths and backslashes", async () => {
    const root = await directory();
    for (const entry of ["../outside", "/outside", "C:/outside", "a\\outside", "dir/../../outside"]) {
      expect(() => archivePath(root, entry)).toThrow("Unsafe");
    }
    const archive = join(root, "bad.zip");
    await Bun.write(archive, zip([{ name: "../outside", data: "bad" }]));
    await expect(extractZip(archive, join(root, "output"))).rejects.toThrow();
    expect(existsSync(join(root, "outside"))).toBe(false);
  });
  test("extracts executable files and refuses existing destinations", async () => {
    const root = await directory(), archive = join(root, "browser.zip"), output = join(root, "output");
    await Bun.write(archive, zip([{ name: "browser/tool", data: "executable", mode: 0o100755 }]));
    await extractZip(archive, output);
    expect(await Bun.file(join(output, "browser/tool")).text()).toBe("executable");
    if (process.platform !== "win32") expect((await lstat(join(output, "browser/tool"))).mode & 0o777).toBe(0o755);
    await expect(extractZip(archive, output)).rejects.toThrow("empty");
  });
  test.skipIf(process.platform === "win32")("preserves contained framework symlinks and rejects escaping targets", async () => {
    const root = await directory(), archive = join(root, "links.zip"), output = join(root, "output");
    await Bun.write(archive, zip([
      { name: "app/Versions/1/binary", data: "tool", mode: 0o100755 },
      { name: "app/Versions/Current", data: "1", mode: 0o120777 },
      { name: "app/binary", data: "Versions/Current/binary", mode: 0o120777 },
    ]));
    await extractZip(archive, output);
    expect(await readlink(join(output, "app/Versions/Current"))).toBe("1");
    expect(await Bun.file(join(output, "app/binary")).text()).toBe("tool");
    await Bun.write(archive, zip([{ name: "escape", data: "../outside", mode: 0o120777 }]));
    await expect(extractZip(archive, join(root, "bad"))).rejects.toThrow("Unsafe");
  });
  test("selects matching browser and driver for Windows", () => {
    const target = browserTarget("win32", "x64");
    const binaries = browserExecutables("tools", target, "win32");
    expect(binaries.chrome).toEndWith("chrome.exe");
    expect(binaries.driver).toEndWith("chromedriver.exe");
    expect(() => browserTarget("freebsd", "x64")).toThrow("No pinned browser");
  });
});

describe("generation", () => {
  test("replacement removes stale generated files and restores old output on failure", async () => {
    const root = await directory(), target = join(root, "target"), source = join(root, "source");
    await mkdir(target); await mkdir(source);
    await Bun.write(join(target, "stale"), "old"); await Bun.write(join(source, "new"), "new");
    await replaceDirectory(source, target);
    expect(existsSync(join(target, "stale"))).toBe(false);
    await expect(replaceDirectory(join(root, "missing"), target)).rejects.toThrow();
    expect(await Bun.file(join(target, "new")).text()).toBe("new");
  });
  test("drift includes added/removed/changed files and excludes Dart cache", async () => {
    const root = await directory(), generated = join(root, "frontend/packages/domabas_api");
    await mkdir(generated, { recursive: true });
    await Bun.write(join(generated, "removed.dart"), "old");
    await Bun.write(join(generated, "changed.dart"), "old");
    const before = await snapshot(root);
    await rm(join(generated, "removed.dart"));
    await Bun.write(join(generated, "changed.dart"), "new");
    await Bun.write(join(generated, "added.dart"), "new");
    await Bun.write(join(generated, "pubspec.lock"), "ignored");
    await Bun.write(join(generated, ".dart_tool/package_config.json"), "ignored");
    expect(changedFiles(before, await snapshot(root))).toEqual(["added.dart", "changed.dart", "removed.dart"].map(name => `frontend/packages/domabas_api/${name}`));
  });
});

describe("database isolation", () => {
  test("accepts explicit E2E ports and rejects invalid overrides", () => {
    expect(portValue(undefined, 18080)).toBe(18080);
    expect(portValue("39123", 18080)).toBe(39123);
    for (const value of ["", "0", "65536", "3.5", "NaN"]) expect(() => portValue(value, 18080)).toThrow("E2E port");
  });
  test("Compose SQL uses the internal port and refuses remote rewrites", () => {
    expect(composeDatabaseURL("postgres://u:p@localhost:54329/db?sslmode=disable")).toBe("postgres://u:p@127.0.0.1:5432/db?sslmode=disable");
    expect(() => composeDatabaseURL("postgres://u:p@remote/db")).toThrow("Install psql");
  });
  test("replaces search_path while retaining other database URL options", () => {
    const url = new URL(schemaURL("postgres://u:p@localhost/db?sslmode=require&search_path=public&application_name=test", "e2e_unique"));
    expect(url.searchParams.get("search_path")).toBe("e2e_unique");
    expect(url.searchParams.get("sslmode")).toBe("require");
    expect(url.searchParams.get("application_name")).toBe("test");
  });
  test("always drops its schema and preserves the original test error", async () => {
    const calls: string[] = [], failure = new Error("test failed"), reported: unknown[] = [];
    await expect(withTemporarySchema(async () => { calls.push("create"); }, async () => { calls.push("test"); throw failure; }, async () => { calls.push("drop"); throw new Error("cleanup failed"); }, error => reported.push(error))).rejects.toBe(failure);
    expect(calls).toEqual(["create", "test", "drop"]);
    expect(reported).toHaveLength(1);
  });
  test("attempts cleanup even when CREATE was interrupted", async () => {
    let dropped = false;
    await expect(withTemporarySchema(async () => { throw new Error("interrupted"); }, async () => {}, async () => { dropped = true; })).rejects.toThrow("interrupted");
    expect(dropped).toBe(true);
  });
});
