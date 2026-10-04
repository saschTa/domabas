import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { appBuildArguments, appBuildOutput, buildApp, parseAppBuild, validateAppBuildHost } from "./build-app.ts";
import type { AppBuildDependencies } from "./build-app.ts";

function fixture() {
  const calls: string[][] = [];
  const logs: string[] = [];
  const deps: AppBuildDependencies = {
    root: "/checkout with spaces", platform: "linux", arch: "x64", env: { PATH: "/tools" },
    which: () => "/tools/flutter", exists: () => true,
    read: path => path.endsWith(".tool-versions") ? "flutter 3.47.4-stable\n" : "locked dependencies",
    log: message => logs.push(message),
    runner: {
      capture: async () => ({ code: 0, stdout: JSON.stringify({ frameworkVersion: "3.47.4", channel: "stable" }), stderr: "" }),
      run: async (args, options) => {
        expect(options?.cwd).toBe(join(deps.root, "frontend"));
        expect(options?.env).toBe(deps.env);
        calls.push([...args]);
      },
    },
  };
  return { deps, calls, logs };
}

describe("local app builds", () => {
  test("rejects unsupported options before starting any tools", () => {
    for (const args of [[], ["invalid"], ["android", "ios"], ["android", "--simulator"], ["ios", "--release"], ["windows", "--unknown"]]) {
      expect(() => parseAppBuild(args)).toThrow();
    }
    expect(parseAppBuild(["--help"])).toBeUndefined();
    expect(parseAppBuild(["mac"])?.target).toBe("macos");
  });

  test("rejects cross-compilation before looking for Flutter", async () => {
    const { deps } = fixture();
    deps.which = () => { throw new Error("should not inspect tools"); };
    for (const target of ["ios", "macos", "windows"]) {
      await expect(buildApp(parseAppBuild([target])!, deps)).rejects.toThrow(/must be built/);
    }
    for (const platform of ["linux", "darwin", "win32"] as const) validateAppBuildHost(parseAppBuild(["android"])!, platform);
  });

  test("keeps Android debug default, disables Gradle daemon and supports explicit release", () => {
    expect(appBuildArguments(parseAppBuild(["android"])!)).toContain("--debug");
    const release = parseAppBuild(["android", "--release"])!;
    expect(appBuildArguments(release)).toContain("--release");
    expect(appBuildArguments(release)).toContain("--no-android-gradle-daemon");
    expect(appBuildOutput(release, "arm64").path).toEndWith("app-release.apk");
  });

  test("distinguishes unsigned device builds and debug simulator builds", () => {
    const device = parseAppBuild(["ios"])!;
    const simulator = parseAppBuild(["ios", "--simulator"])!;
    expect(appBuildArguments(device)).toContain("--no-codesign");
    expect(appBuildOutput(device, "arm64").next).toContain("cannot be installed");
    expect(appBuildArguments(simulator)).toContain("--debug");
    expect(appBuildArguments(simulator)).not.toContain("--release");
    expect(appBuildArguments(simulator)).not.toContain("--no-codesign");
    expect(appBuildOutput(simulator, "arm64").path).toContain("iphonesimulator");
  });

  test("resolves locked dependencies and permits mode-specific plugin regeneration during build", async () => {
    const { deps, calls, logs } = fixture();
    await buildApp(parseAppBuild(["android"])!, deps);
    expect(calls).toEqual([
      ["/tools/flutter", "pub", "get", "--enforce-lockfile"],
      ["/tools/flutter", "build", "apk", "--debug", "--no-android-gradle-daemon"],
    ]);
    expect(logs.at(-1)).toContain(join(deps.root, "frontend/build/app/outputs/flutter-apk/app-debug.apk"));
    for (const args of [["android", "--release"], ["ios"], ["ios", "--simulator"], ["macos"], ["windows"]]) {
      expect(appBuildArguments(parseAppBuild(args)!)).not.toContain("--no-pub");
    }
  });

  test("stops on missing or mismatched Flutter without resolving dependencies", async () => {
    const { deps, calls } = fixture();
    deps.which = () => null;
    await expect(buildApp(parseAppBuild(["android"])!, deps)).rejects.toThrow("not on PATH");
    deps.which = () => "flutter";
    deps.runner.capture = async () => ({ code: 0, stdout: '{"frameworkVersion":"3.0.0","channel":"stable"}', stderr: "" });
    await expect(buildApp(parseAppBuild(["android"])!, deps)).rejects.toThrow("requires Flutter 3.47.4");
    expect(calls).toHaveLength(0);
  });

  test("stops on resolution or build failures without announcing success", async () => {
    for (const failOn of ["pub", "build"]) {
      const { deps, calls, logs } = fixture();
      deps.runner.run = async args => { calls.push([...args]); if (args[1] === failOn) throw new Error("tool failed"); };
      await expect(buildApp(parseAppBuild(["android"])!, deps)).rejects.toThrow("tool failed");
      expect(calls).toHaveLength(failOn === "pub" ? 1 : 2);
      expect(logs.some(line => line.includes("Build complete"))).toBe(false);
    }
  });

  test("refuses a changed lockfile or missing artifact", async () => {
    for (const changedAfter of [1, 2]) {
      const { deps, calls, logs } = fixture();
      const read = deps.read;
      deps.read = path => path.endsWith("pubspec.lock") && calls.length >= changedAfter ? "changed" : read(path);
      await expect(buildApp(parseAppBuild(["android"])!, deps)).rejects.toThrow("changed frontend/pubspec.lock");
      expect(calls).toHaveLength(changedAfter);
      expect(logs.some(line => line.includes("Build complete"))).toBe(false);
    }
    const { deps, logs } = fixture();
    deps.exists = () => false;
    await expect(buildApp(parseAppBuild(["android"])!, deps)).rejects.toThrow("expected app is missing");
    expect(logs.some(line => line.includes("Build complete"))).toBe(false);
  });

  test("iOS rejects Command Line Tools even when DEVELOPER_DIR points to Xcode", async () => {
    const { deps, calls } = fixture();
    deps.platform = "darwin";
    deps.env.DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
    const capture = deps.runner.capture;
    deps.runner.capture = async (args, options) => {
      if (args[0] === "/usr/bin/xcode-select") {
        expect(options?.env?.DEVELOPER_DIR).toBeUndefined();
        return { code: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "" };
      }
      return capture(args, options);
    };
    deps.exists = path => path.startsWith("/Applications/Xcode.app/");
    await expect(buildApp(parseAppBuild(["ios"])!, deps)).rejects.toThrow("sudo xcode-select --switch");
    expect(calls).toHaveLength(0);
  });

  test("macOS allows a selected Xcode override and checks Xcode and SDK", async () => {
    const { deps, calls } = fixture();
    deps.platform = "darwin";
    deps.env.DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
    const capture = deps.runner.capture;
    const checks: string[][] = [];
    deps.runner.capture = async (args, options) => {
      if (!args[0]?.startsWith("/usr/bin/")) return capture(args, options);
      checks.push([...args]);
      return { code: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "" };
    };
    await buildApp(parseAppBuild(["macos"])!, deps);
    expect(checks).toContainEqual(["/usr/bin/xcodebuild", "-version"]);
    expect(checks).toContainEqual(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]);
    expect(calls.at(-1)).toContain("macos");
    deps.runner.capture = async args => args[0] === "/usr/bin/xcodebuild" ? { code: 1, stdout: "", stderr: "" } : capture(args);
    await expect(buildApp(parseAppBuild(["macos"])!, deps)).rejects.toThrow("Finish Xcode setup first");
  });
});
