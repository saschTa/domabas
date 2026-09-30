import { createWriteStream, existsSync } from "node:fs";
import { chmod, lstat, mkdir, mkdtemp, readdir, realpath, rename, rm, symlink } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pipeline } from "node:stream/promises";
import { openPromise } from "yauzl";
import { replaceDirectory } from "../../generation/generate-client.ts";
import { ROOT, binary, download, runCLI } from "../../shared/runtime.ts";

export const VERSION = "153.0.8010.47";
const MARKER = "bun-zip-v1\n";

export function browserTarget(platform = process.platform, arch = process.arch): string {
  const targets: Record<string, string> = { "darwin-arm64": "mac-arm64", "darwin-x64": "mac-x64",
    "linux-x64": "linux64", "linux-arm64": "linux-arm64", "win32-x64": "win64" };
  const target = targets[`${platform}-${arch}`];
  if (!target) throw new Error(`No pinned browser configured for ${platform}/${arch}.`);
  return target;
}

export function archivePath(directory: string, name: string): string {
  if (!name || name.includes("\\") || name.includes("\0") || /^[A-Za-z]:/.test(name) || isAbsolute(name) || name.split("/").includes("..")) {
    throw new Error(`Unsafe browser archive entry: ${name}`);
  }
  const destination = resolve(directory, name);
  const rel = relative(resolve(directory), destination);
  if (!rel || rel.startsWith(`..${sep}`) || rel === ".." || isAbsolute(rel)) throw new Error(`Unsafe browser archive entry: ${name}`);
  return destination;
}

export async function extractZip(archive: string, directory: string): Promise<void> {
  await mkdir(directory, { recursive: true });
  if ((await lstat(directory)).isSymbolicLink()) throw new Error("Archive destination cannot be a symbolic link.");
  if ((await readdir(directory)).length) throw new Error("Archive destination must be empty.");
  directory = await realpath(directory);
  const zip = await openPromise(archive, { strictFileNames: true });
  const links: { path: string; target: string }[] = [];
  const entries = new Set<string>();
  try {
    for await (const entry of zip.eachEntry()) {
      const destination = archivePath(directory, entry.fileName);
      if (entries.has(destination)) throw new Error(`Duplicate browser archive entry: ${entry.fileName}`);
      entries.add(destination);
      const mode = entry.externalFileAttributes >>> 16;
      const kind = mode & 0o170000;
      if (kind && ![0o100000, 0o040000, 0o120000].includes(kind)) throw new Error("Unsupported browser archive file type.");
      if (entry.fileName.endsWith("/")) {
        await mkdir(destination, { recursive: true });
        continue;
      }
      await mkdir(dirname(destination), { recursive: true });
      const stream = await zip.openReadStreamPromise(entry);
      if (kind === 0o120000) {
        if (entry.uncompressedSize > 4096) throw new Error("Invalid browser archive symbolic link.");
        const chunks: Buffer[] = [];
        for await (const chunk of stream) chunks.push(Buffer.from(chunk));
        const target = Buffer.concat(chunks).toString("utf8");
        if (!target || isAbsolute(target) || target.includes("\\") || target.includes("\0") || /^[A-Za-z]:/.test(target)) throw new Error("Unsafe browser archive symbolic link.");
        const resolved = resolve(dirname(destination), target);
        archivePath(directory, relative(directory, resolved).split(sep).join("/"));
        links.push({ path: destination, target });
      } else {
        // Exclusive creation prevents overwriting an existing file or following a symlink.
        await pipeline(stream, createWriteStream(destination, { flags: "wx", mode: mode & 0o777 || 0o644 }));
        if (process.platform !== "win32" && mode) await chmod(destination, mode & 0o777);
      }
    }
    for (const link of links) {
      if (process.platform === "win32") throw new Error("Unexpected symbolic link in Windows browser archive.");
      await symlink(link.target, link.path);
    }
    // Real resolution catches chained links and broken/cyclic link targets.
    for (const link of links) archivePath(directory, relative(directory, await realpath(link.path)).split(sep).join("/"));
  } finally { zip.close(); }
}

export function browserExecutables(directory: string, target: string, platform = process.platform): { chrome: string; driver: string } {
  return {
    chrome: platform === "darwin"
      ? join(directory, `chrome-${target}`, "Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing")
      : join(directory, `chrome-${target}`, binary("chrome", platform)),
    driver: join(directory, `chromedriver-${target}`, binary("chromedriver", platform)),
  };
}

export async function install(signal?: AbortSignal): Promise<{ chrome: string; driver: string }> {
  const target = browserTarget();
  const directory = join(ROOT, ".tools/chrome", VERSION);
  const executables = browserExecutables(directory, target);
  await mkdir(directory, { recursive: true });
  for (const name of ["chrome", "chromedriver"] as const) {
    signal?.throwIfAborted();
    const packageName = `${name}-${target}`;
    const marker = join(directory, `.${packageName}.complete`);
    const executable = name === "chrome" ? executables.chrome : executables.driver;
    if (existsSync(marker) && existsSync(executable) && await Bun.file(marker).text() === MARKER) {
      const mode = (await lstat(executable)).mode;
      if (process.platform === "win32" || (mode & 0o111)) continue;
    }
    const temporary = await mkdtemp(join(directory, ".download-"));
    try {
      const archive = join(temporary, `${packageName}.zip`);
      console.log(`Downloading ${name} ${VERSION} (${target})...`);
      await download(`https://storage.googleapis.com/chrome-for-testing-public/${VERSION}/${target}/${packageName}.zip`, archive, signal);
      const output = join(temporary, "extracted");
      await extractZip(archive, output);
      signal?.throwIfAborted();
      const stagedExecutables = browserExecutables(output, target);
      const stagedExecutable = name === "chrome" ? stagedExecutables.chrome : stagedExecutables.driver;
      if (!existsSync(stagedExecutable)) throw new Error(`Browser download is missing its ${name} executable.`);
      const stagedFile = await lstat(stagedExecutable);
      if (!stagedFile.isFile() || (process.platform !== "win32" && !(stagedFile.mode & 0o111))) {
        throw new Error(`Browser download contains an invalid ${name} executable.`);
      }
      await replaceDirectory(join(output, packageName), join(directory, packageName));
      const stagedMarker = join(temporary, "complete");
      await Bun.write(stagedMarker, MARKER);
      await rename(stagedMarker, marker);
    } finally { await rm(temporary, { recursive: true, force: true }); }
  }
  return executables;
}

if (import.meta.main) await runCLI(async scope => {
  const { chrome, driver } = await install(scope.signal);
  console.log(chrome);
  console.log(driver);
});
