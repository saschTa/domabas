import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { ROOT, ProcessScope, runCLI } from "../shared/runtime.ts";
import type { Environment, ProcessOptions } from "../shared/runtime.ts";

const GUIDE = "docs/development/build-apps.md";
const USAGE = "Usage: task build:app -- <android|ios|macos|windows> [--release (Android)] [--simulator (iOS)]";
type AppTarget = "android" | "ios" | "macos" | "windows";

export interface AppBuild {
  target: AppTarget;
  release: boolean;
  simulator: boolean;
}

export function parseAppBuild(args: string[]): AppBuild | undefined {
  const { positionals, values } = parseArgs({ args, allowPositionals: true, options: {
    help: { type: "boolean", short: "h" },
    release: { type: "boolean", default: false },
    simulator: { type: "boolean", default: false },
  } });
  if (values.help) return;
  const target = positionals[0] === "mac" ? "macos" : positionals[0];
  if (positionals.length !== 1 || !["android", "ios", "macos", "windows"].includes(target ?? "")) throw new Error(USAGE);
  if (values.release && target !== "android") throw new Error("--release is only needed for Android. Desktop and unsigned iOS builds already use release mode.");
  if (values.simulator && target !== "ios") throw new Error("--simulator is only available for iOS.");
  return { target: target as AppTarget, release: values.release, simulator: values.simulator };
}

export function validateAppBuildHost(build: AppBuild, platform: NodeJS.Platform): void {
  if ((build.target === "macos" || build.target === "ios") && platform !== "darwin") {
    throw new Error(`${build.target} must be built on a Mac with full Xcode. See ${GUIDE}#macos-and-ios.`);
  }
  if (build.target === "windows" && platform !== "win32") {
    throw new Error(`Windows apps must be built on Windows with Visual Studio's Desktop development with C++ workload. See ${GUIDE}#windows.`);
  }
  if (!["darwin", "linux", "win32"].includes(platform)) throw new Error(`Unsupported build computer: ${platform}. See ${GUIDE}.`);
}

export function appBuildArguments(build: AppBuild): string[] {
  switch (build.target) {
    case "android": return ["build", "apk", build.release ? "--release" : "--debug", "--no-android-gradle-daemon"];
    case "ios": return ["build", "ios", ...(build.simulator ? ["--simulator", "--debug"] : ["--release", "--no-codesign"])];
    default: return ["build", build.target, "--release"];
  }
}

export function appBuildOutput(build: AppBuild, arch: string): { path: string; next: string } {
  switch (build.target) {
    case "android": return {
      path: `build/app/outputs/flutter-apk/app-${build.release ? "release" : "debug"}.apk`,
      next: "Copy this APK to your Android phone and open it to install. Both modes use this computer's development signing key. See the guide before replacing an existing installation.",
    };
    case "ios": return build.simulator ? {
      path: "build/ios/iphonesimulator/Runner.app",
      next: "This debug app is for the iOS simulator only. Open frontend/ios/Runner.xcworkspace in Xcode, choose an iPhone simulator and press Run.",
    } : {
      path: "build/ios/iphoneos/Runner.app",
      next: "This app is UNSIGNED and cannot be installed on an iPhone yet. Open frontend/ios/Runner.xcworkspace in Xcode, configure your signing team and run on your connected iPhone. See the guide for steps.",
    };
    case "macos": return {
      path: "build/macos/Build/Products/Release/domabas.app",
      next: "Open domabas.app, or copy it to Applications. This local build is not notarized for distribution.",
    };
    case "windows": return {
      path: `build/windows/${arch === "arm64" ? "arm64" : "x64"}/runner/Release/domabas.exe`,
      next: "Open domabas.exe. Keep the entire Release folder together, including its DLLs and data folder; copying only the EXE will not work.",
    };
  }
}

interface AppBuildRunner {
  run: (args: readonly string[], options?: ProcessOptions) => Promise<void>;
  capture: (args: readonly string[], options?: ProcessOptions, timeoutMs?: number) => Promise<{ code: number; stdout: string; stderr: string }>;
}

export interface AppBuildDependencies {
  runner: AppBuildRunner;
  root: string;
  platform: NodeJS.Platform;
  arch: string;
  env: Environment;
  which: (name: string) => string | null;
  exists: (path: string) => boolean;
  read: (path: string) => string;
  log: (message: string) => void;
}

async function checkAppleTools(build: AppBuild, deps: AppBuildDependencies): Promise<void> {
  const globalEnv = { ...deps.env, DEVELOPER_DIR: undefined };
  const selection = await deps.runner.capture(["/usr/bin/xcode-select", "-p"], { env: globalEnv });
  const developerDir = build.target === "macos" && deps.env.DEVELOPER_DIR ? deps.env.DEVELOPER_DIR : selection.stdout.trim();
  if ((selection.code && !deps.env.DEVELOPER_DIR) || !deps.exists(join(developerDir, "usr/bin/xcodebuild"))) {
    throw new Error(`Full Xcode must be selected before building ${build.target}. Install Xcode, then run in Terminal:\n  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer\n  sudo xcodebuild -runFirstLaunch\nSee ${GUIDE}#macos-and-ios. iOS native dependencies need the global selection, even with DEVELOPER_DIR set.`);
  }
  const xcode = await deps.runner.capture(["/usr/bin/xcodebuild", "-version"], { env: deps.env });
  if (xcode.code) throw new Error(`Finish Xcode setup first: open Xcode, review its license and install its requested components, then run sudo xcodebuild -runFirstLaunch. See ${GUIDE}#macos-and-ios.`);
  const sdk = build.target === "macos" ? "macosx" : build.simulator ? "iphonesimulator" : "iphoneos";
  const sdkCheck = await deps.runner.capture(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-path"], { env: deps.env });
  if (sdkCheck.code) throw new Error(`Xcode cannot find the ${sdk} SDK. Install the platform in Xcode Settings > Components and retry. See ${GUIDE}#macos-and-ios.`);
}

export async function buildApp(build: AppBuild, deps: AppBuildDependencies): Promise<void> {
  validateAppBuildHost(build, deps.platform);
  const flutter = deps.which("flutter");
  if (!flutter) throw new Error(`Flutter is not on PATH. Install the pinned Flutter SDK and reopen your terminal. See ${GUIDE}#first-time-setup.`);
  const version = await deps.runner.capture([flutter, "--version", "--machine"], { env: deps.env }, 120000);
  if (version.code) throw new Error(`Flutter could not start. Run flutter doctor -v and follow ${GUIDE}#first-time-setup.`);
  const installed = JSON.parse(version.stdout) as { frameworkVersion?: string; channel?: string };
  const pinned = /^flutter\s+(\S+)-stable$/m.exec(deps.read(join(deps.root, ".tool-versions")))?.[1];
  if (!pinned || installed.frameworkVersion !== pinned || installed.channel !== "stable") {
    throw new Error(`This checkout requires Flutter ${pinned ?? "from .tool-versions"} stable; found ${installed.frameworkVersion ?? "unknown"} (${installed.channel ?? "unknown"}). See ${GUIDE}#first-time-setup. Dependencies have not been changed.`);
  }
  if (build.target === "macos" || build.target === "ios") await checkAppleTools(build, deps);
  const frontend = join(deps.root, "frontend");
  const options = { cwd: frontend, env: deps.env };
  const lockfile = join(frontend, "pubspec.lock");
  const locked = deps.read(lockfile);
  const checkLock = () => {
    if (deps.read(lockfile) !== locked) throw new Error("The build changed frontend/pubspec.lock. Review the dependency change before using the output; no automatic upgrade is intended.");
  };
  deps.log("Step 1/2: Downloading the app's locked dependencies (no server needed)...");
  await deps.runner.run([flutter, "pub", "get", "--enforce-lockfile"], options);
  checkLock();
  deps.log(`Step 2/2: Building ${build.target}. The first build can take several minutes...`);
  await deps.runner.run([flutter, ...appBuildArguments(build)], options);
  checkLock();
  const output = appBuildOutput(build, deps.arch);
  const path = join(frontend, output.path);
  if (!deps.exists(path)) throw new Error(`Flutter finished but the expected app is missing: ${path}`);
  deps.log(`\nBuild complete: ${path}\n${output.next}\nOn first launch, enter your Domabas server's HTTP or HTTPS address.\nFull instructions: ${join(deps.root, GUIDE)}`);
}

if (import.meta.main) await runCLI(async (scope: ProcessScope) => {
  try {
    const build = parseAppBuild(Bun.argv.slice(2));
    if (!build) { console.log(`${USAGE}\n\nSetup, installation and troubleshooting: ${GUIDE}`); return; }
    await buildApp(build, {
      runner: scope, root: ROOT, platform: process.platform, arch: process.arch,
      env: process.env, which: name => Bun.which(name), exists: existsSync,
      read: path => readFileSync(path, "utf8"), log: console.log,
    });
  } catch (error) {
    console.error(`\nBuild stopped. Setup and troubleshooting: ${GUIDE}\nFor SDK diagnostics, run: flutter doctor -v`);
    throw error;
  }
}, { timeoutMs: 60 * 60 * 1000 });
