import { expect, test } from "bun:test";
import { imageFindings, imageScanArguments, imageScanSummary, type TrivyReport } from "./scan-image.ts";

const imageID = `sha256:${"a".repeat(64)}`;
const report = (severity: string): TrivyReport => ({
  SchemaVersion: 2, ArtifactType: "container_image", Metadata: { ImageID: imageID, OS: { Family: "alpine" } },
  Results: [{ Target: "Alpine", Vulnerabilities: [{ VulnerabilityID: "CVE-EXAMPLE", PkgName: "fixture", InstalledVersion: "1.0", Severity: severity }] }],
});

test("image scanning reports every severity and includes unfixed critical findings", () => {
  for (const severity of ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]) {
    const findings = imageFindings(report(severity), imageID);
    expect(findings.some(finding => finding.severity === "CRITICAL")).toBe(severity === "CRITICAL");
    expect(findings[0]!.fixedVersion).toBe("Not available");
    expect(imageScanSummary("fixture", imageID, findings)).toContain(`${severity}: 1`);
    expect(imageScanSummary("fixture", imageID, findings)).toContain("CVE-EXAMPLE");
  }
  const clean = report("LOW"); clean.Results = [{ Target: "Alpine" }];
  expect(imageFindings(clean, imageID)).toEqual([]);
});

test("missing or malformed reports and wrong image identity cannot pass", () => {
  for (const change of [
    { SchemaVersion: 3 }, { ArtifactType: "filesystem" },
    { Metadata: { ImageID: `sha256:${"b".repeat(64)}`, OS: { Family: "alpine" } } },
    { Metadata: { ImageID: imageID } }, { Results: undefined },
  ]) expect(() => imageFindings({ ...report("LOW"), ...change }, imageID)).toThrow(/Trivy/);
  expect(() => imageFindings(report("UNRECOGNIZED"), imageID)).toThrow("malformed");
});

test("scans only an immutable local image and prevents implicit filtering", () => {
  const args = imageScanArguments(imageID, "report.json", "config.yaml", "empty-ignore");
  expect(args.at(-1)).toBe(imageID);
  expect(args).toContain("docker");
  expect(args).toContain("vuln");
  expect(args).toContain("os,library");
  expect(args).toContain("UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL");
  expect(args).toContain("--ignore-unfixed=false");
  expect(args).not.toContain("--skip-db-update");
  for (const reference of ["nginx:latest", "sha256:123", "--skip-db-update"]) expect(() => imageScanArguments(reference, "report", "config", "ignore")).toThrow("full local");
});

test("summaries prioritize critical findings and keep the full report discoverable", () => {
  const mixed = report("LOW");
  mixed.Results![0]!.Vulnerabilities = Array.from({ length: 105 }, (_, index) => ({ VulnerabilityID: `CVE-${index}`, PkgName: "fixture", InstalledVersion: "1", Severity: index === 104 ? "CRITICAL" : "LOW" }));
  const findings = imageFindings(mixed, imageID);
  expect(findings[0]!.severity).toBe("CRITICAL");
  const summary = imageScanSummary("backend", imageID, findings);
  expect(summary).toContain("CRITICAL: 1");
  expect(summary).toContain("CVE-104");
  expect(summary).toContain("Showing 100 of 105");
  expect(summary).toContain(".cache/image-scans/backend.json");
});
