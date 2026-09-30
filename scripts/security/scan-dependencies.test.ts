import { expect, test } from "bun:test";
import { dependencyFindings, dependencyReport } from "./scan-dependencies.ts";

const report = (score: string, severity?: string) => ({ results: [{ packages: [{
  package: { name: "example/package", version: "1.0.0" },
  groups: [{ ids: ["EXAMPLE-1", "ALIAS-1"], max_severity: score }],
  vulnerabilities: [{ id: "EXAMPLE-1", database_specific: { severity } }],
}] }] });

test("only critical ratings block; high, medium, low and unknown stay visible", () => {
  for (const score of ["9", "9.1", "10"]) expect(dependencyFindings(report(score))[0]!.critical).toBe(true);
  for (const score of ["8.9", "7.0", "4.0", "0", ""]) {
    const findings = dependencyFindings(report(score));
    expect(findings[0]!.critical).toBe(false);
    expect(dependencyReport(findings)).toContain("EXAMPLE-1");
    expect(dependencyReport(findings)).toContain("including 0 critical");
  }
  expect(dependencyFindings(report("", "CRITICAL"))[0]!.critical).toBe(true);
  expect(dependencyFindings(report("", "HIGH"))[0]!.critical).toBe(false);
});

test("aliases stay grouped and malformed severity data cannot silently pass", () => {
  expect(dependencyFindings(report("9.1"))).toHaveLength(1);
  expect(dependencyFindings({ results: [] })).toEqual([]);
  for (const score of ["NaN", "critical", "-1", "11"]) expect(() => dependencyFindings(report(score))).toThrow("severity");
  const missingGroups = report("9.1"); missingGroups.results[0]!.packages[0]!.groups = [];
  expect(() => dependencyFindings(missingGroups)).toThrow("ungrouped");
});
