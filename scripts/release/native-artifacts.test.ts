import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FLUTTER_SHA256, flutterArchive } from "../ci/setup-flutter.ts";
import { nativeBuildArguments } from "./build-native.ts";
import { NATIVE_TARGETS, loadNativeArtifacts, nativeArtifactName, nativeReleaseContext, writeNativeManifest } from "./native-artifacts.ts";

const env = { RELEASE_VERSION: "v0.2.7", GITHUB_SHA: "a".repeat(40), GITHUB_RUN_NUMBER: "123" };
const context = nativeReleaseContext(env);
const directories: string[] = [];
afterEach(async () => { for (const path of directories.splice(0)) await rm(path, { force: true, recursive: true }); });

async function fixture(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "domabas-native-assets-test-"));
  directories.push(directory);
  for (const target of NATIVE_TARGETS) {
    await Bun.write(join(directory, target, nativeArtifactName(target, context.version)), `${target} fixture`);
    await writeNativeManifest(join(directory, target), target, context);
  }
  return directory;
}

test("native builds share semantic versions and positive platform build numbers", () => {
  for (const change of [{ RELEASE_VERSION: "main" }, { RELEASE_VERSION: "v1.2.3\nextra=bad" }, { GITHUB_SHA: "branch" },
    { GITHUB_RUN_NUMBER: "0" }, { GITHUB_RUN_NUMBER: "1.2" }, { GITHUB_RUN_NUMBER: "2e9" }, { GITHUB_RUN_NUMBER: "2100000001" }]) {
    expect(() => nativeReleaseContext({ ...env, ...change })).toThrow();
  }
  for (const target of NATIVE_TARGETS) {
    const args = nativeBuildArguments(target, context);
    expect(args).toContain("--build-name=0.2.7");
    expect(args).toContain("--build-number=123");
    expect(args).toContain("--release");
    expect(args).not.toContain("--no-pub");
  }
  expect(nativeBuildArguments("android", context)).toContain("--no-android-gradle-daemon");
});

test("SDK archives retain the pinned Linux checksum and reject unsupported hosts", () => {
  expect(flutterArchive("linux", "x64").sha256).toBe(FLUTTER_SHA256);
  expect(flutterArchive("darwin", "arm64")).toMatchObject({ format: "zip", sha256: "c6af6fa1d64946167b8637ba4c5a7bb3b8574729a1ebe931decd4924dbab7061" });
  expect(() => flutterArchive("darwin", "x64")).toThrow("Linux x64 or macOS arm64");
});

test("both native files are verified and listed in downloadable SHA-256 checksums", async () => {
  const assets = await loadNativeArtifacts(await fixture(), context);
  expect(assets).toHaveLength(3);
  const sums = await assets[2]!.content.text();
  expect(assets[2]!.name).toBe("SHA256SUMS.txt");
  for (const asset of assets.slice(0, 2)) {
    expect(sums).toContain(`${asset.sha256}  ${asset.name}\n`);
    expect(asset.sha256).toBe(new Bun.CryptoHasher("sha256").update(await asset.content.arrayBuffer()).digest("hex"));
  }
});

test("missing, mixed-release, renamed and corrupted downloads cannot be published", async () => {
  const directory = await fixture(), path = join(directory, "macos", "manifest.json");
  const manifest = await Bun.file(path).json();
  for (const change of [{ schema: 2 }, { target: "android" }, { version: "v0.2.8" }, { sha: "b".repeat(40) },
    { buildNumber: 124 }, { name: "../../outside.dmg" }, { size: 1 }, { sha256: "0".repeat(64) }]) {
    await Bun.write(path, JSON.stringify({ ...manifest, ...change }));
    await expect(loadNativeArtifacts(directory, context)).rejects.toThrow();
  }
  await Bun.write(path, JSON.stringify(manifest));
  const artifact = join(directory, "macos", manifest.name);
  await Bun.write(artifact, "tampered artifact");
  await expect(loadNativeArtifacts(directory, context)).rejects.toThrow("verification");
  await rm(artifact);
  await expect(loadNativeArtifacts(directory, context)).rejects.toThrow();
  await symlink(path, artifact);
  await expect(loadNativeArtifacts(directory, context)).rejects.toThrow("regular file");
  await rm(path);
  await expect(loadNativeArtifacts(directory, context)).rejects.toThrow();
});
