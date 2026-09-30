import { appendFile, copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { sha256 } from "../generation/generate-client.ts";
import { ROOT, type Environment, type ProcessScope, command, runCLI, withCleanup } from "../shared/runtime.ts";

export const TRIVY_VERSION = "0.74.0";
const archives: Record<string, { platform: string; sha256: string }> = {
  linux_x64: { platform: "Linux-64bit", sha256: "2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a" },
  darwin_arm64: { platform: "macOS-ARM64", sha256: "1caada5e0e2091909357c7525d3aa76f4b660b13821bc143b190c7483e31cc11" },
};
const severities = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"] as const;
type ImageSeverity = typeof severities[number];
export interface ImageFinding { target: string; package: string; version: string; fixedVersion: string; id: string; severity: ImageSeverity }
export interface TrivyReport {
  SchemaVersion: number;
  ArtifactType: string;
  Metadata: { ImageID: string; OS?: { Family: string } };
  Results?: { Target: string; Vulnerabilities?: { VulnerabilityID: string; PkgName: string; InstalledVersion: string; FixedVersion?: string; Severity: string }[] }[];
}

export function imageFindings(report: TrivyReport, imageID: string): ImageFinding[] {
  if (report.SchemaVersion !== 2 || report.ArtifactType !== "container_image" || report.Metadata?.ImageID !== imageID) throw new Error("Trivy report does not identify the exact scanned image.");
  if (!report.Metadata.OS?.Family || !Array.isArray(report.Results)) throw new Error("Trivy did not report an image OS and scan results.");
  return report.Results.flatMap(result => (result.Vulnerabilities ?? []).map(vulnerability => {
    if (!severities.includes(vulnerability.Severity as ImageSeverity) || !vulnerability.VulnerabilityID || !vulnerability.PkgName) throw new Error("Trivy returned malformed vulnerability data.");
    return { target: result.Target, package: vulnerability.PkgName, version: vulnerability.InstalledVersion, fixedVersion: vulnerability.FixedVersion || "Not available", id: vulnerability.VulnerabilityID, severity: vulnerability.Severity as ImageSeverity };
  })).sort((a, b) => severities.indexOf(a.severity) - severities.indexOf(b.severity));
}

export function imageScanSummary(name: string, imageID: string, findings: ImageFinding[]): string {
  const cell = (value: string) => value.replaceAll("|", "\\|").replaceAll("\n", " ").replaceAll("<", "&lt;");
  const counts = severities.map(severity => `${severity}: ${findings.filter(finding => finding.severity === severity).length}`).join(", ");
  return [
    `## Image vulnerabilities: ${name}`,
    `Scanned local image \`${imageID}\` with Trivy ${TRIVY_VERSION}. Only CRITICAL findings block publication; scanner errors also fail the gate. Unfixed vulnerabilities are included.`,
    counts,
    "| Package | Installed | Fixed | Severity | Advisory |\n| --- | --- | --- | --- | --- |\n" + findings.slice(0, 100).map(finding => `| ${cell(finding.package)} | ${cell(finding.version)} | ${cell(finding.fixedVersion)} | ${finding.severity} | ${cell(finding.id)} |`).join("\n"),
    `Showing ${Math.min(findings.length, 100)} of ${findings.length} findings. The full JSON report is saved in .cache/image-scans/${name}.json and uploaded by the main release job.`,
    "Coverage depends on package metadata and scanner support. Custom statically linked OCR code and compiled Flutter web dependencies are not fully covered; the OSV source scan remains required.",
  ].join("\n\n") + "\n";
}

export function imageScanArguments(imageID: string, report: string, configuration: string, ignorefile: string): string[] {
  if (!/^sha256:[a-f0-9]{64}$/.test(imageID)) throw new Error("Image scanning requires a full local sha256 image ID.");
  return ["image", "--image-src", "docker", "--scanners", "vuln", "--pkg-types", "os,library", "--severity", "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL",
    "--ignore-unfixed=false", "--exit-code", "0", "--format", "json", "--output", report, "--timeout", "10m",
    "--cache-dir", join(ROOT, ".cache/trivy"), "--config", configuration, "--ignorefile", ignorefile, imageID];
}

export async function scanImage(scope: ProcessScope, imageID: string, name: string, environment: Environment = process.env): Promise<void> {
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(name)) throw new Error("Image report name must contain only lowercase letters, digits and hyphens.");
  if (!/^sha256:[a-f0-9]{64}$/.test(imageID)) throw new Error("Image scanning requires a full local sha256 image ID.");
  const pin = archives[`${process.platform}_${process.arch}`];
  if (!pin) throw new Error("Image scanning currently supports Linux x64 and macOS arm64.");
  const temporary = await mkdtemp(join(tmpdir(), "domabas-trivy-"));
  const env = Object.fromEntries(Object.entries(environment).filter(([key]) => !key.startsWith("TRIVY_") && key !== "GITHUB_TOKEN"));
  await withCleanup(async () => {
    const filename = `trivy_${TRIVY_VERSION}_${pin.platform}.tar.gz`;
    const directory = join(ROOT, ".cache/trivy-downloads"), archive = join(directory, filename);
    await mkdir(directory, { recursive: true });
    if (!await Bun.file(archive).exists()) {
      const response = await fetch(`https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${filename}`, {
        signal: AbortSignal.any([scope.signal, AbortSignal.timeout(120000)]),
      });
      if (!response.ok) throw new Error(`Trivy download failed: HTTP ${response.status}.`);
      const downloaded = join(temporary, filename);
      await Bun.write(downloaded, await response.arrayBuffer());
      if (await sha256(downloaded) !== pin.sha256) throw new Error("Trivy archive failed SHA-256 verification.");
      await copyFile(downloaded, archive);
    }
    if (await sha256(archive) !== pin.sha256) throw new Error("Trivy archive failed SHA-256 verification.");
    await scope.run([command("tar"), "-xzf", archive, "-C", temporary, "trivy"], { env });
    const report = join(ROOT, ".cache/image-scans", `${name}.json`);
    await mkdir(join(ROOT, ".cache/image-scans"), { recursive: true });
    await rm(report, { force: true });
    const configuration = join(temporary, "trivy.yaml"), ignorefile = join(temporary, "empty-ignore");
    await Bun.write(configuration, "{}\n");
    await Bun.write(ignorefile, "");
    const started = performance.now();
    const result = await scope.capture([join(temporary, "trivy"), ...imageScanArguments(imageID, report, configuration, ignorefile)], { env }, 11 * 60 * 1000);
    if (result.code) throw new Error(`Trivy scan failed (${result.code}): ${result.stderr}`);
    const findings = imageFindings(await Bun.file(report).json() as TrivyReport, imageID);
    const summary = imageScanSummary(name, imageID, findings);
    console.log(summary);
    if (environment.GITHUB_STEP_SUMMARY) await appendFile(environment.GITHUB_STEP_SUMMARY, summary);
    console.log(`Image scan ${name} finished in ${((performance.now() - started) / 1000).toFixed(1)}s.`);
    if (findings.some(finding => finding.severity === "CRITICAL")) throw new Error(`Trivy found critical vulnerabilities in ${name}; no release images will be pushed.`);
  }, async () => { await rm(temporary, { recursive: true, force: true }); });
}

if (import.meta.main) await runCLI(async scope => {
  const { values, positionals } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true, options: { name: { type: "string", default: "image" } } });
  if (positionals.length !== 1) throw new Error("Usage: task security:image -- sha256:<local-image-id> [--name <report-name>]");
  await scanImage(scope, positionals[0]!, values.name);
}, { timeoutMs: 15 * 60 * 1000 });
