import { existsSync } from "node:fs";
import { appendFile, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { sha256 } from "../generation/generate-client.ts";
import { ROOT, command, required, runCLI } from "../shared/runtime.ts";

export const FLUTTER_VERSION = "3.47.4";
export const FLUTTER_COMMIT = "9584c6713b324636289d067944a46fd6b49df14b";
export const FLUTTER_SHA256 = "5b45f0ceda99b9bebdc873e7e69f6450aeb4c30f454b505e2e62fc9255a907d3";

if (import.meta.main) await runCLI(async scope => {
  if (process.platform !== "linux" || process.arch !== "x64") throw new Error("CI Flutter installation requires Linux x64.");
  const target = join(process.env.RUNNER_TOOL_CACHE ?? join(ROOT, ".tools"), "flutter", `stable-${FLUTTER_VERSION}-x64`, "flutter");
  const flutter = join(target, "bin/flutter");
  if (!existsSync(flutter)) {
    await mkdir(dirname(target), { recursive: true });
    const temporary = await mkdtemp(join(dirname(target), ".install-"));
    try {
      const archive = join(temporary, "flutter.tar.xz");
      await scope.run([command("curl"), "--fail", "--show-error", "--location", "--retry", "5", "--retry-all-errors", "--retry-max-time", "900", "--connect-timeout", "20", "--max-time", "900", "--output", archive,
        `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz`]);
      if (await sha256(archive) !== FLUTTER_SHA256) throw new Error("Flutter archive failed SHA-256 verification.");
      await scope.run([command("tar"), "-xJf", archive, "-C", temporary]);
      await rename(join(temporary, "flutter"), target);
    } finally { await rm(temporary, { recursive: true, force: true }); }
  }
  await scope.run([command("git"), "config", "--global", "--add", "safe.directory", target]);
  const commit = await scope.capture([command("git"), "-C", target, "rev-parse", "HEAD"]);
  if (commit.code || commit.stdout.trim() !== FLUTTER_COMMIT) throw new Error("Cached Flutter SDK does not match the pinned release commit.");
  await scope.run([flutter, "--version"]);
  await appendFile(required(process.env, "GITHUB_PATH"), `${target}/bin\n${target}/bin/cache/dart-sdk/bin\n`);
  await appendFile(required(process.env, "GITHUB_ENV"), `FLUTTER_ROOT=${target}\n`);
});
