import { required, runCLI } from "../shared/runtime.ts";
import type { CISuiteSelection } from "./select-suites.ts";

type CIJobResult = { result?: string; outputs?: Record<string, string> };

export function verifyCIResults(needs: Record<string, CIJobResult>): void {
  if (needs.changes?.result !== "success") throw new Error("Tooling and suite selection did not succeed.");
  const outputs = needs.changes.outputs ?? {};
  for (const suite of ["backend", "frontend", "contracts"]) {
    if (!["true", "false"].includes(outputs[suite] ?? "")) throw new Error(`Missing or invalid ${suite} suite selection.`);
  }
  const suites: Record<string, keyof CISuiteSelection> = {
    backend: "backend", integration: "backend", frontend: "frontend", widgetbook: "frontend", contracts: "contracts",
  };
  for (const [job, suite] of Object.entries(suites)) {
    const result = needs[job]?.result;
    if (result === "success" || outputs[suite] === "false" && result === "skipped") continue;
    throw new Error(`${job} did not succeed (selected=${outputs[suite]}, result=${result ?? "missing"}).`);
  }
}

if (import.meta.main) await runCLI(async () => {
  verifyCIResults(JSON.parse(required(process.env, "CI_NEEDS")) as Record<string, CIJobResult>);
  console.log("All selected CI suites passed.");
});
