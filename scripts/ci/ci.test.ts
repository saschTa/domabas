import { expect, test } from "bun:test";
import { join } from "node:path";
import { ciSuite, runCIAnalysis, runCITests } from "./ci.ts";
import { backendUnitPackages } from "../testing/backend-database-tests.ts";
import { browserTestGroups } from "../testing/browser/browser-tests.ts";
import { ROOT } from "../shared/runtime.ts";

test("units need no infrastructure and full local validation retains integration and E2E", async () => {
  for (const suite of ["units", "full"] as const) {
    const calls: { args: string[]; cwd?: string }[] = [];
    await runCITests(suite, async (args, cwd) => { calls.push({ args, cwd }); });
    expect(calls).toContainEqual({ args: ["flutter", "test", "--no-pub"], cwd: join(ROOT, "frontend") });
    expect(calls.filter(call => call.args.includes("scripts/testing/browser/browser-tests.ts"))).toHaveLength(suite === "full" ? 1 : 0);
    if (suite === "units") {
      expect(calls).toContainEqual({ args: ["go", "test", "-race", "-count=1", "./..."], cwd: join(ROOT, "backend") });
      expect(calls).toHaveLength(2);
    } else {
      expect(calls).toContainEqual({ args: ["bun", "--no-env-file", "scripts/testing/backend-database-tests.ts", "integration", "--include-units"], cwd: undefined });
      expect(calls).toContainEqual({ args: ["bun", "--no-env-file", "scripts/testing/backend-database-tests.ts", "temporal"], cwd: undefined });
      expect(calls.some(call => call.args[0] === "go" && call.args.includes("./..."))).toBe(false);
    }
    const commands = calls.map(call => call.args.join(" "));
    expect(commands.includes("bun --no-env-file scripts/testing/backend-database-tests.ts e2e")).toBe(suite === "full");
    expect(commands.includes("bun --no-env-file scripts/testing/e2e.ts --external-services")).toBe(suite === "full");
  }
});

test("units skip analysis and generation while full local checks preserve them", async () => {
  for (const suite of ["units", "full"] as const) {
    const calls: string[] = [];
    await runCIAnalysis(suite, async args => { calls.push(args.join(" ")); }, async () => { calls.push("gofmt"); });
    if (suite === "units") expect(calls).toEqual([]);
    else {
      expect(calls).toContain("bun --no-env-file run typecheck");
      expect(calls).toContain("bun --no-env-file scripts/generation/check-generated.ts");
      expect(calls).toContain("bun --no-env-file scripts/generation/generate-database.ts --check");
      expect(calls).toContain("gofmt");
      expect(calls).toContain("go vet ./...");
      expect(calls).toContain("flutter analyze --no-pub --fatal-infos");
    }
  }
});

test("full local validation includes new packages and defers all data units to integration", () => {
  const packages = ["example/backend/cmd/server", "example/backend/internal/newdomain", "example/backend/internal/data", "example/backend/internal/data/document/repos", "example/backend/internal/database", "example/backend/tests/architecture"];
  expect(backendUnitPackages(packages.join("\n"))).toEqual([packages[0]!, packages[1]!, packages[4]!, packages[5]!]);
  expect(() => backendUnitPackages("")).toThrow("no backend unit packages");
});

test("combined browser selection retains every focused test file exactly once", async () => {
  const files = Object.values(browserTestGroups).flat();
  const aggregate = await Bun.file(join(ROOT, "frontend/test/browser_suite.dart")).text();
  const imports = [...aggregate.matchAll(/^import '(.+_test\.dart)' as (\w+);$/gm)];
  expect(files).toHaveLength(9);
  expect(new Set(files).size).toBe(files.length);
  expect(imports.map(match => `test/${match[1]}`).sort()).toEqual([...files].sort());
  for (const match of imports) expect(aggregate.match(new RegExp(`group\\('[^']+', ${match[2]}\\.main\\);`, "g"))).toHaveLength(1);
  for (const file of files) expect(await Bun.file(join(ROOT, "frontend", file)).exists()).toBe(true);
});

test("CI defaults to units and rejects unknown suites", () => {
  expect(ciSuite()).toBe("units");
  expect(() => ciSuite("baseline")).toThrow("units or full");
});

test("a failing backend suite stops later tests in either mode", async () => {
  for (const suite of ["units", "full"] as const) {
    const calls: string[] = [], failure = new Error("backend assertion failed");
    await expect(runCITests(suite, async args => {
      calls.push(args.join(" "));
      throw failure;
    })).rejects.toBe(failure);
    expect(calls).toHaveLength(1);
    expect(calls[0]).toContain(suite === "units" ? "go test -race" : "integration");
  }
});

test("GitHub PRs use read-only fast checks and isolated PostgreSQL; only main can publish", async () => {
  type Step = { run?: string; uses?: string; with?: Record<string, unknown>; env?: Record<string, string> };
  type Job = { if?: string; needs?: string[]; "runs-on": string; "timeout-minutes": number; permissions?: Record<string, string>; steps: Step[]; concurrency?: { queue: string; "cancel-in-progress": boolean }; services?: Record<string, { image: string }> };
  const workflow = Bun.YAML.parse(await Bun.file(join(ROOT, ".github/workflows/ci.yml")).text()) as {
    on: { push: { branches: string[] }; pull_request: unknown; workflow_dispatch: unknown };
    permissions: Record<string, string>;
    concurrency: { group: string; "cancel-in-progress": string };
    jobs: Record<string, Job>;
  };
  expect(workflow.on.push.branches).toEqual(["main"]);
  expect(workflow.on).toHaveProperty("pull_request");
  expect(workflow.on).not.toHaveProperty("pull_request_target");
  expect(workflow.permissions).toEqual({ contents: "read" });
  for (const job of Object.values(workflow.jobs)) {
    expect(job["runs-on"]).toBe("ubuntu-latest");
    expect(job["timeout-minutes"]).toBeGreaterThan(0);
    for (const step of job.steps) if (step.uses) {
      expect(step.uses).toMatch(/@[a-f0-9]{40}$/);
      if (step.uses.startsWith("actions/checkout@")) expect(step.with?.["persist-credentials"]).toBe(false);
    }
  }
  expect(workflow.jobs.checks!.steps.some(step => step.run === "task check")).toBe(true);
  const integration = workflow.jobs.integration!;
  expect(integration.steps.some(step => step.run === "task ci:database")).toBe(true);
  expect(integration.steps.some(step => step.run === "task test:integration")).toBe(true);
  expect(integration.steps.some(step => step.run === "task generate:db:check")).toBe(true);
  const compose = Bun.YAML.parse(await Bun.file(join(ROOT, "compose.yaml")).text()) as { services: { postgres: { image: string } } };
  expect(integration.services!.postgres!.image).toBe(compose.services.postgres.image);
  const release = workflow.jobs.release!;
  expect(release.needs).toEqual(["checks", "integration", "dependencies"]);
  expect(release.permissions).toEqual({ contents: "write", packages: "write", "pull-requests": "read" });
  expect(release.concurrency?.queue).toBe("max");
  expect(release.concurrency?.["cancel-in-progress"]).toBe(false);
  for (const [event_name, ref, expected] of [
    ["pull_request", "refs/heads/main", false], ["push", "refs/heads/main", true],
    ["push", "refs/heads/feature", false], ["workflow_dispatch", "refs/heads/main", false],
  ] as const) {
    const select = new Function("github", "return (" + release.if + ");");
    expect(select({ event_name, ref })).toBe(expected);
  }
  expect(workflow.jobs.dependencies!.steps.some(step => step.run === "task security:dependencies")).toBe(true);
  expect(workflow.concurrency.group).toContain("github.run_id");
  expect(workflow.concurrency["cancel-in-progress"]).toContain("github.event_name == 'pull_request'");
  for (const job of Object.values(workflow.jobs)) for (const step of job.steps) {
    expect(step.run ?? "").not.toMatch(/build:(android|ios|linux|macos|windows)|build (apk|appbundle|ios|linux|macos|windows)/);
    if (step.env?.GITHUB_TOKEN) expect(job).toBe(release);
  }
});

test("main publication retains image reports and a refreshable database even on scan failures", async () => {
  const workflow = Bun.YAML.parse(await Bun.file(join(ROOT, ".github/workflows/ci.yml")).text()) as {
    jobs: { release: { steps: { name?: string; uses?: string; if?: string; with?: Record<string, unknown> }[] } };
  };
  const steps = workflow.jobs.release.steps;
  const reports = steps.find(step => step.uses?.startsWith("actions/upload-artifact@"))!;
  expect(reports.if).toBe("always()");
  expect(reports.with?.path).toBe(".cache/image-scans/*.json");
  expect(reports.with?.["include-hidden-files"]).toBe(true);
  expect(reports.with?.["retention-days"]).toBe(14);
  const save = steps.find(step => step.uses?.startsWith("actions/cache/save@"))!;
  expect(save.if).toContain("always()");
  expect(save.if).toContain("metadata.json");
  expect(save.with?.path).toBe(".cache/trivy/db");
  expect(steps.some(step => step.uses?.startsWith("actions/cache/restore@"))).toBe(true);
});
