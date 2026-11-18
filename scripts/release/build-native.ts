import { copyFile, mkdir, mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FLUTTER_COMMIT, FLUTTER_VERSION } from "../ci/setup-flutter.ts";
import { type Environment, type ProcessScope, ROOT, command, runCLI } from "../shared/runtime.ts";
import { type NativeReleaseContext, type NativeTarget, nativeArtifactName, nativeReleaseContext, writeNativeManifest } from "./native-artifacts.ts";

export function nativeBuildArguments(target: NativeTarget, context: NativeReleaseContext): string[] {
  return ["build", target === "android" ? "apk" : "macos", "--release", `--build-name=${context.version.slice(1)}`, `--build-number=${context.buildNumber}`,
    ...target === "android" ? ["--no-android-gradle-daemon"] : []];
}

export async function buildNativeRelease(scope: ProcessScope, target: NativeTarget, context: NativeReleaseContext, env: Environment, root = ROOT): Promise<void> {
  if (target === "macos" && process.platform !== "darwin") throw new Error("macOS release builds require a Mac with Xcode.");
  const git = command("git"), flutter = command("flutter"), frontend = join(root, "frontend");
  const head = await scope.capture([git, "rev-parse", "HEAD"], { cwd: root, env });
  if (head.code || head.stdout.trim() !== context.sha) throw new Error("Checkout does not match the native release commit.");
  const version = await scope.capture([flutter, "--version", "--machine"], { cwd: frontend, env }, 120000);
  if (version.code) throw new Error("Cannot verify Flutter SDK.");
  const sdk = JSON.parse(version.stdout) as { frameworkVersion: string; frameworkRevision: string };
  if (sdk.frameworkVersion !== FLUTTER_VERSION || sdk.frameworkRevision !== FLUTTER_COMMIT) throw new Error("Native builds require the pinned Flutter SDK.");
  const buildEnv = { ...env, FLUTTER_MACOS_ARM64_ONLY: "false", FLUTTER_SWIFT_PACKAGE_MANAGER: "true" };
  await scope.run([flutter, "pub", "get", "--enforce-lockfile"], { cwd: frontend, env: buildEnv });
  await scope.run([git, "diff", "--exit-code", "--", "frontend/pubspec.lock", "frontend/packages/domabas_api/pubspec.lock"], { cwd: root, env });
  const directory = join(root, ".cache/native-release", target);
  await mkdir(directory, { recursive: true });
  await rm(join(directory, "manifest.json"), { force: true });
  await scope.run([flutter, ...nativeBuildArguments(target, context)], { cwd: frontend, env: buildEnv });
  await scope.run([git, "diff", "--exit-code", "--", "frontend/pubspec.lock", "frontend/packages/domabas_api/pubspec.lock"], { cwd: root, env });
  const destination = join(directory, nativeArtifactName(target, context.version));
  if (target === "android") {
    await copyFile(join(frontend, "build/app/outputs/flutter-apk/app-release.apk"), destination);
  } else {
    const app = join(frontend, "build/macos/Build/Products/Release/domabas.app");
    const architectures = await scope.capture([command("lipo"), "-archs", join(app, "Contents/MacOS/domabas")], { env });
    if (architectures.code || !["arm64", "x86_64"].every(arch => architectures.stdout.trim().split(/\s+/).includes(arch))) throw new Error("macOS app is not a universal arm64/x86_64 build.");
    await scope.run([command("codesign"), "--verify", "--deep", "--strict", app], { env });
    const staging = await mkdtemp(join(tmpdir(), "domabas-dmg-"));
    try {
      await scope.run([command("ditto"), app, join(staging, "domabas.app")], { env });
      await symlink("/Applications", join(staging, "Applications"));
      await scope.run([command("hdiutil"), "create", "-ov", "-format", "UDZO", "-fs", "HFS+", "-volname", `Domabas ${context.version}`, "-srcfolder", staging, destination], { env });
      await scope.run([command("hdiutil"), "verify", destination], { env });
    } finally { await rm(staging, { recursive: true, force: true }); }
  }
  await writeNativeManifest(directory, target, context);
  console.log(`Built ${destination}`);
}

if (import.meta.main) await runCLI(async scope => {
  const target = Bun.argv[2];
  if (Bun.argv.length !== 3 || target !== "android" && target !== "macos") throw new Error("Usage: task release:native -- <android|macos>");
  await buildNativeRelease(scope, target, nativeReleaseContext(process.env), { ...process.env });
}, { timeoutMs: 45 * 60 * 1000 });
