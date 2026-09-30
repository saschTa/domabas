import { appendFile, chmod, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { sha256 } from "../generation/generate-client.ts";
import { ROOT, runCLI } from "../shared/runtime.ts";

export const OSV_VERSION = "v2.6.0";
const binaries: Record<string, string> = {
  linux_amd64: "ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108",
  darwin_arm64: "98c460dcd37de25819babd757d04542045b6243113e209edcd4d89fedb0256b4",
};
export const DEPENDENCY_SCAN_ARGS = ["scan", "source", "--lockfile=backend/go.mod", "--lockfile=frontend/pubspec.lock", "--lockfile=bun.lock", "--no-call-analysis=go", "--no-call-analysis=rust", "--format=json"];
interface OSVReport {
  results: { packages: {
    package: { name: string; version: string };
    groups: { ids: string[]; max_severity: string }[];
    vulnerabilities: { id: string; database_specific?: { severity?: string } }[];
  }[] }[];
}
export interface DependencyFinding { name: string; version: string; ids: string[]; score: string; critical: boolean }

export function dependencyFindings(report: OSVReport): DependencyFinding[] {
  if (!Array.isArray(report.results)) throw new Error("OSV report has no results array.");
  return report.results.flatMap(result => result.packages.flatMap(pkg => {
    if (pkg.vulnerabilities.length && !pkg.groups.length) throw new Error("OSV report has ungrouped vulnerabilities.");
    return pkg.groups.map(group => {
      const score = group.max_severity;
      if (score && (!Number.isFinite(Number(score)) || Number(score) < 0 || Number(score) > 10)) throw new Error("Invalid OSV severity score.");
      const critical = Number(score) >= 9 || pkg.vulnerabilities.some(vulnerability => group.ids.includes(vulnerability.id) && vulnerability.database_specific?.severity?.toUpperCase() === "CRITICAL");
      return { name: pkg.package.name, version: pkg.package.version, ids: group.ids, score: score || "Unknown", critical };
    });
  }));
}

export function dependencyReport(findings: DependencyFinding[]): string {
  const cell = (value: string) => value.replaceAll("|", "\\|").replaceAll("\n", " ").replaceAll("<", "&lt;");
  return [
    "## Dependency vulnerabilities",
    "Only critical findings (CVSS ≥ 9.0 or an explicit critical rating) block releases. Other and unscored findings are reported for review. Scan errors also fail the check.",
    `Found ${findings.length} advisory groups, including ${findings.filter(finding => finding.critical).length} critical.`,
    "| Package | Version | CVSS | Blocks release | Advisories |\n| --- | --- | --- | --- | --- |\n" + findings.map(finding =>
      `| ${cell(finding.name)} | ${cell(finding.version)} | ${cell(finding.score)} | ${finding.critical ? "Yes" : "No"} | ${finding.ids.map(id => `[${cell(id)}](https://osv.dev/${encodeURIComponent(id)})`).join(", ")} |`).join("\n"),
    "Coverage: locked Go, Dart and Bun dependencies; no call analysis or container OS/native-library scan.",
  ].join("\n\n") + "\n";
}

if (import.meta.main) await runCLI(async scope => {
  const platform = `${process.platform}_${process.arch === "x64" ? "amd64" : process.arch}`;
  const checksum = binaries[platform];
  if (!checksum) throw new Error("Dependency scanning currently supports Linux x64 and macOS arm64.");
  const directory = join(ROOT, ".cache", "osv-scanner", OSV_VERSION, platform);
  const executable = join(directory, "osv-scanner"), report = join(directory, "report.json");
  await mkdir(directory, { recursive: true });
  if (!await Bun.file(executable).exists()) {
    const response = await fetch(`https://github.com/google/osv-scanner/releases/download/${OSV_VERSION}/osv-scanner_${platform}`, {
      signal: AbortSignal.any([scope.signal, AbortSignal.timeout(120000)]),
    });
    if (!response.ok) throw new Error(`OSV download failed: HTTP ${response.status}.`);
    await Bun.write(executable, await response.arrayBuffer());
  }
  if (await sha256(executable) !== checksum) throw new Error("OSV binary failed SHA-256 verification.");
  await chmod(executable, 0o755);
  await rm(report, { force: true });
  const started = performance.now();
  const result = await scope.capture([executable, ...DEPENDENCY_SCAN_ARGS, `--output-file=${report}`], {}, 5 * 60 * 1000);
  if (result.code !== 0 && result.code !== 1) throw new Error(`OSV scan failed (${result.code}): ${result.stderr}`);
  const findings = dependencyFindings(await Bun.file(report).json() as OSVReport);
  if (result.code === 1 && !findings.length) throw new Error("OSV reported findings but returned an empty report.");
  const markdown = dependencyReport(findings);
  console.log(markdown);
  if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY, markdown);
  console.log(`Dependency scan finished in ${((performance.now() - started) / 1000).toFixed(1)}s.`);
  if (findings.some(finding => finding.critical)) throw new Error("OSV found critical vulnerable dependencies; review the report before releasing.");
}, { timeoutMs: 8 * 60 * 1000 });
