import { join } from "node:path";
import { parseArgs } from "node:util";
import { ROOT, command, environment, required, runCLI } from "../shared/runtime.ts";

export function backendUnitPackages(output: string): string[] {
  const packages = output.trim().split(/\s+/).filter(name => name && !name.includes("/internal/data/") && !name.endsWith("/internal/data"));
  if (!packages.length) throw new Error("Go package discovery returned no backend unit packages.");
  return packages;
}

if (import.meta.main) await runCLI(async scope => {
  const { values, positionals } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true, options: { help: { type: "boolean", short: "h" }, "include-units": { type: "boolean", default: false } } });
  if (values.help) { console.log("Usage: bun scripts/testing/backend-database-tests.ts <integration|temporal|e2e> [--include-units] (integration only)"); return; }
  const suite = positionals[0];
  if (positionals.length !== 1 || !["integration", "temporal", "e2e"].includes(suite!)) throw new Error("Usage: bun scripts/testing/backend-database-tests.ts <integration|temporal|e2e>");
  const env = environment();
  env.TEST_DATABASE_URL ||= required(env, "DATABASE_URL");
  if (suite !== "integration") required(env, "DOCUMENT_PROCESSOR_URL");
  if (values["include-units"]) {
    if (suite !== "integration") throw new Error("--include-units requires the integration suite.");
    const packages = await scope.capture([command("go"), "list", "./..."], { cwd: join(ROOT, "backend"), env });
    if (packages.code) throw new Error(`Go package discovery failed: ${packages.stderr}`);
    await scope.run([command("go"), "test", "-race", "-count=1", ...backendUnitPackages(packages.stdout)], { cwd: join(ROOT, "backend"), env });
  }
  const target = suite === "integration" ? "./internal/data/..." : `./tests/${suite}`;
  const timeout = suite === "e2e" ? ["-timeout=20m"] : [];
  await scope.run([command("go"), "test", "-race", "-count=1", "-p=1", ...timeout, `-tags=${suite}`, target], { cwd: join(ROOT, "backend"), env });
});
