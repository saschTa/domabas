import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import { generateClient, sha256 } from "./generate-client.ts";
import { ROOT, command, runCLI } from "../shared/runtime.ts";

export async function snapshot(root = ROOT): Promise<Map<string, string>> {
  const paths = [join(root, "backend/internal/presentation/httpapi/contract/api.gen.go")];
  async function walk(directory: string): Promise<void> {
    if (!existsSync(directory)) return;
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.name === ".dart_tool" || entry.name === "pubspec.lock") continue;
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile()) paths.push(path);
    }
  }
  await walk(join(root, "frontend/packages/domabas_api"));
  const result = new Map<string, string>();
  for (const path of paths) {
    if (existsSync(path)) result.set(relative(root, path).split(sep).join("/"), await sha256(path));
  }
  return result;
}

export function changedFiles(before: Map<string, string>, after: Map<string, string>): string[] {
  return [...new Set([...before.keys(), ...after.keys()])].filter(path => before.get(path) !== after.get(path)).sort();
}

if (import.meta.main) await runCLI(async scope => {
  const before = await snapshot();
  await scope.run([command("go"), "generate", "./..."], { cwd: join(ROOT, "backend") });
  await generateClient(scope);
  const changed = changedFiles(before, await snapshot());
  if (changed.length) throw new Error(`Generated contract files had drifted. Review and commit task generate output:\n${changed.join("\n")}`);
  console.log("Generated Go and Dart API code matches the canonical contract.");
});
