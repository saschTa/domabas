import { lstat, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { sha256 } from "../generation/generate-client.ts";
import { type Environment, required } from "../shared/runtime.ts";

export const NATIVE_TARGETS = ["android", "macos"] as const;
export type NativeTarget = typeof NATIVE_TARGETS[number];
export interface NativeReleaseContext { version: string; sha: string; buildNumber: number }
export interface NativeReleaseAsset { name: string; contentType: string; content: Blob; sha256: string }
interface NativeArtifactManifest extends NativeReleaseContext { schema: 1; target: NativeTarget; name: string; size: number; sha256: string }

export function nativeReleaseContext(env: Environment): NativeReleaseContext {
  const version = required(env, "RELEASE_VERSION"), sha = required(env, "GITHUB_SHA"), number = required(env, "GITHUB_RUN_NUMBER");
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) throw new Error("Native builds require the reserved semantic release version.");
  if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error("Native builds require the exact release commit.");
  const buildNumber = Number(number);
  if (!/^[1-9]\d*$/.test(number) || !Number.isSafeInteger(buildNumber) || buildNumber > 2100000000) throw new Error("Native build number must be a positive Android version code (at most 2100000000).");
  return { version, sha, buildNumber };
}

export function nativeArtifactName(target: NativeTarget, version: string): string {
  return `domabas-${version}-${target === "android" ? "android-preview.apk" : "macos-universal-unsigned.dmg"}`;
}

async function artifactDetails(path: string): Promise<{ size: number; sha256: string }> {
  const file = await lstat(path);
  if (!file.isFile() || file.size <= 0) throw new Error("Native artifact must be a nonempty regular file.");
  return { size: file.size, sha256: await sha256(path) };
}

export async function writeNativeManifest(directory: string, target: NativeTarget, context: NativeReleaseContext): Promise<void> {
  const name = nativeArtifactName(target, context.version);
  const manifest: NativeArtifactManifest = { schema: 1, target, ...context, name, ...await artifactDetails(join(directory, name)) };
  await mkdir(directory, { recursive: true });
  await Bun.write(join(directory, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
}

export async function loadNativeArtifacts(directory: string, context: NativeReleaseContext): Promise<NativeReleaseAsset[]> {
  const assets: NativeReleaseAsset[] = [];
  for (const target of NATIVE_TARGETS) {
    const manifest: unknown = await Bun.file(join(directory, target, "manifest.json")).json();
    const expectedName = nativeArtifactName(target, context.version);
    if (!manifest || typeof manifest !== "object") throw new Error(`Missing ${target} native manifest.`);
    const value = manifest as Partial<NativeArtifactManifest>;
    if (value.schema !== 1 || value.target !== target || value.version !== context.version || value.sha !== context.sha ||
      value.buildNumber !== context.buildNumber || value.name !== expectedName) throw new Error(`${target} artifact does not match this release, commit and build number.`);
    const path = join(directory, target, expectedName), details = await artifactDetails(path);
    if (value.size !== details.size || value.sha256 !== details.sha256) throw new Error(`${target} artifact failed size or SHA-256 verification.`);
    assets.push({ name: expectedName, contentType: target === "android" ? "application/vnd.android.package-archive" : "application/x-apple-diskimage", content: Bun.file(path), sha256: details.sha256 });
  }
  const checksums = new Blob([assets.map(asset => `${asset.sha256}  ${asset.name}\n`).join("")]);
  assets.push({ name: "SHA256SUMS.txt", contentType: "text/plain", content: checksums, sha256: new Bun.CryptoHasher("sha256").update(await checksums.arrayBuffer()).digest("hex") });
  return assets;
}
