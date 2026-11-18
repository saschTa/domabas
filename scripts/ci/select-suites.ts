import { appendFile } from "node:fs/promises";
import { ROOT, command, required, runCLI, type ProcessScope } from "../shared/runtime.ts";

export type CISuiteSelection = { backend: boolean; frontend: boolean; contracts: boolean };

export function selectCISuites(event: string, paths?: readonly string[]): CISuiteSelection {
  const all = { backend: true, frontend: true, contracts: true };
  if (event !== "pull_request" || paths === undefined) return all;
  const selected = { backend: false, frontend: false, contracts: false };
  for (const path of paths) {
    if (["readme.md", "architecture.md", "PRODUCT.md", "scripts/README.md", "backend/README.md", "frontend/README.md", "frontend/widgetbook/README.md", "truenas/README.md"].includes(path) ||
      /^docs\/.*\.(md|png|jpe?g|svg|webp)$/.test(path)) continue;
    if (path.startsWith("contracts/") || path.startsWith("backend/internal/presentation/httpapi/contract/") ||
      path.startsWith("frontend/packages/domabas_api/") ||
      ["backend/go.mod", "backend/go.sum", "frontend/openapi-generator.yaml"].includes(path)) return all;
    if (path.startsWith("backend/")) selected.backend = true;
    else if (path.startsWith("frontend/")) selected.frontend = true;
    else return all;
  }
  return selected;
}

export async function changedCIPaths(scope: ProcessScope, base: string | undefined, root = ROOT): Promise<string[] | undefined> {
  if (!base || !/^[a-f0-9]{40}$/.test(base)) return undefined;
  const result = await scope.capture([command("git"), "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--"], { cwd: root });
  if (result.code || result.stdout && !result.stdout.endsWith("\0")) return undefined;
  return result.stdout.split("\0").filter(Boolean);
}

if (import.meta.main) await runCLI(async scope => {
  const event = required(process.env, "GITHUB_EVENT_NAME");
  const paths = event === "pull_request" ? await changedCIPaths(scope, process.env.CI_BASE_SHA) : undefined;
  const selected = selectCISuites(event, paths);
  const reason = event !== "pull_request" ? "Full checks for a non-PR run." : paths === undefined
    ? "Changed paths unavailable; running all suites." : `Classified ${paths.length} changed paths in the tested merge.`;
  const outputs = Object.entries(selected).map(([name, run]) => `${name}=${run}\n`).join("");
  console.log(reason);
  console.log(outputs.trim());
  await appendFile(required(process.env, "GITHUB_OUTPUT"), outputs);
  if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY,
    `## CI suite selection\n\n${reason}\n\n| Suite | Selected |\n| --- | --- |\n` +
    Object.entries(selected).map(([name, run]) => `| ${name} | ${run ? "yes" : "no"} |\n`).join(""));
});
