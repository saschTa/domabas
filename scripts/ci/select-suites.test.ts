import { expect, test } from "bun:test";
import { mkdtemp, mkdir, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ProcessScope, ROOT } from "../shared/runtime.ts";
import { changedCIPaths, selectCISuites } from "./select-suites.ts";
import { verifyCIResults } from "./check-results.ts";

const all = { backend: true, frontend: true, contracts: true };
const none = { backend: false, frontend: false, contracts: false };

test("PRs select complete application sides, including tests, fixtures and platform files", () => {
  for (const path of ["backend/internal/domain/document/services/document_service.go", "backend/internal/data/postgres/migrations/020_example.sql", "backend/tests/architecture/layers_test.go", "backend/testdata/document.md", "backend/.env"]) {
    expect(selectCISuites("pull_request", [path])).toEqual({ ...none, backend: true });
  }
  for (const path of ["frontend/lib/ui/glacier.dart", "frontend/lib/data/chat/repos/chat_repository.dart", "frontend/test/fixtures/sample.md", "frontend/test/ui/glacier_test.dart", "frontend/pubspec.lock", "frontend/ios/Runner/Info.plist", "frontend/widgetbook/test/catalog_test.dart"]) {
    expect(selectCISuites("pull_request", [path])).toEqual({ ...none, frontend: true });
  }
  expect(selectCISuites("pull_request", ["frontend/lib/main.dart", "backend/cmd/server/main.go"])).toEqual({ ...all, contracts: false });
});

test("contracts, generated output and generator dependencies select both application sides", () => {
  for (const path of ["contracts/backend/openapi.yaml", "contracts/backend/oapi-codegen.yaml", "backend/internal/presentation/httpapi/contract/api.gen.go", "backend/internal/presentation/httpapi/contract/generate.go", "backend/go.mod", "backend/go.sum", "frontend/openapi-generator.yaml", "frontend/packages/domabas_api/lib/api.dart"]) {
    expect(selectCISuites("pull_request", [path])).toEqual(all);
  }
});

test("only known documentation skips application suites; shared and unknown inputs select all", () => {
  expect(selectCISuites("pull_request", ["readme.md", "docs/development/testing.md", "docs/screenshots/library.png", "frontend/README.md", "frontend/widgetbook/README.md"])).toEqual(none);
  expect(selectCISuites("pull_request", [])).toEqual(none);
  for (const path of [".github/workflows/ci.yml", "Taskfile.yml", "scripts/shared/runtime.ts", "scripts/testing/fixtures/invoice.xml", "bun.lock", "package.json", ".bun-version", ".tool-versions", "compose.yaml", "infra/init/index.ts", "third_party/licenses/catalog.json", "new-component/main.go", "docs/new-script.ts"]) {
    expect(selectCISuites("pull_request", ["readme.md", path])).toEqual(all);
  }
});

test("non-PR events and unavailable changes always run the full configured checks", () => {
  for (const event of ["push", "workflow_dispatch", "merge_group", "unknown"]) {
    expect(selectCISuites(event, ["readme.md"])).toEqual(all);
  }
  expect(selectCISuites("pull_request")).toEqual(all);
});

test("Git selection includes deletions, both sides of renames, unusual paths and large changes", async () => {
  const root = await mkdtemp(join(tmpdir(), "domabas-ci-selection-"));
  const scope = new ProcessScope();
  const git = async (...args: string[]) => scope.run(["git", ...args], { cwd: root, stdout: "ignore", stderr: "ignore" });
  try {
    await git("init", "--initial-branch=main");
    await mkdir(join(root, "frontend"));
    await mkdir(join(root, "backend"));
    await writeFile(join(root, "frontend/old.dart"), "rename fixture\n");
    await writeFile(join(root, "backend/deleted.go"), "delete fixture\n");
    await git("add", ".");
    await git("-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "commit", "-m", "base");
    const base = (await scope.capture(["git", "rev-parse", "HEAD"], { cwd: root })).stdout.trim();
    await rename(join(root, "frontend/old.dart"), join(root, "backend/new.go"));
    await rm(join(root, "backend/deleted.go"));
    const unusual = "frontend/space and\nnewline.dart";
    await writeFile(join(root, unusual), "fixture\n");
    await Promise.all(Array.from({ length: 310 }, (_, index) => writeFile(join(root, `frontend/test-${index}.dart`), "fixture\n")));
    await git("add", ".");
    await git("-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "commit", "-m", "head");
    const paths = await changedCIPaths(scope, base, root);
    expect(paths).toHaveLength(314);
    expect(paths).toContain("frontend/old.dart");
    expect(paths).toContain("backend/new.go");
    expect(paths).toContain("backend/deleted.go");
    expect(paths).toContain(unusual);
    expect(selectCISuites("pull_request", paths)).toEqual({ ...all, contracts: false });
    expect(await changedCIPaths(scope, "f".repeat(40), root)).toBeUndefined();
    expect(await changedCIPaths(scope, undefined, root)).toBeUndefined();
    expect(await changedCIPaths(scope, "--invalid-revision", root)).toBeUndefined();
    const head = (await scope.capture(["git", "rev-parse", "HEAD"], { cwd: root })).stdout.trim();
    await git("checkout", "-b", "target", base);
    await writeFile(join(root, "target-only.txt"), "base branch change\n");
    await git("add", ".");
    await git("-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "commit", "-m", "target");
    const target = (await scope.capture(["git", "rev-parse", "HEAD"], { cwd: root })).stdout.trim();
    await git("-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "merge", "--no-ff", head, "-m", "tested merge");
    expect(await changedCIPaths(scope, target, root)).toEqual(paths);
  } finally {
    await scope.close();
    await rm(root, { recursive: true, force: true });
  }
});

test("workflow conditions and aggregate gate agree for docs, either application, shared changes and main", async () => {
  type Job = { if?: string; needs?: string | string[] };
  const workflow = Bun.YAML.parse(await Bun.file(join(ROOT, ".github/workflows/ci.yml")).text()) as { jobs: Record<string, Job> };
  const jobs = ["backend", "frontend", "widgetbook", "contracts", "integration"];
  expect(workflow.jobs.checks!.needs).toEqual(["changes", ...jobs]);
  expect(workflow.jobs.checks!.if).toContain("always()");
  for (const [event_name, ref, expected] of [
    ["pull_request", "refs/pull/1/merge", true], ["push", "refs/heads/main", true],
    ["workflow_dispatch", "refs/heads/main", false], ["workflow_dispatch", "refs/heads/feature", true],
  ] as const) {
    const github = { event_name, ref };
    expect(new Function("github", `return (${workflow.jobs.changes!.if});`)(github)).toBe(expected);
    expect(new Function("github", "always", `return (${workflow.jobs.checks!.if});`)(github, () => true)).toBe(expected);
  }
  for (const [event, paths, expected] of [
    ["pull_request", ["readme.md"], []],
    ["pull_request", ["backend/cmd/server/main.go"], ["backend", "integration"]],
    ["pull_request", ["frontend/lib/main.dart"], ["frontend", "widgetbook"]],
    ["pull_request", ["contracts/backend/openapi.yaml"], jobs],
    ["push", ["readme.md"], jobs],
    ["workflow_dispatch", [], jobs],
  ] as const) {
    const outputs = Object.fromEntries(Object.entries(selectCISuites(event, paths)).map(([suite, run]) => [suite, String(run)]));
    const needs: Record<string, { result: string; outputs?: Record<string, string> }> = { changes: { result: "success", outputs } };
    const selected = jobs.filter(job => {
      expect(workflow.jobs[job]!.needs).toBe("changes");
      const run = new Function("needs", `return (${workflow.jobs[job]!.if});`)(needs) as boolean;
      needs[job] = { result: run ? "success" : "skipped" };
      return run;
    });
    expect(selected).toEqual([...expected]);
    expect(() => verifyCIResults(needs)).not.toThrow();
    for (const job of selected) for (const result of ["failure", "cancelled", "skipped", "missing"]) {
      expect(() => verifyCIResults({ ...needs, [job]: { result } })).toThrow(job);
    }
    for (const result of ["failure", "cancelled", "skipped"]) {
      expect(() => verifyCIResults({ ...needs, changes: { result, outputs } })).toThrow("Tooling");
    }
    expect(() => verifyCIResults({ ...needs, changes: { result: "success", outputs: {} } })).toThrow("selection");
  }
});

test("the split fast suites retain every task check command", async () => {
  type Task = { dir?: string; cmds?: (string | { task: string })[] };
  const { tasks } = Bun.YAML.parse(await Bun.file(join(ROOT, "Taskfile.yml")).text()) as { tasks: Record<string, Task> };
  const commands = (name: string): string[] => tasks[name]!.cmds!.flatMap(cmd => typeof cmd === "string" ? [`${tasks[name]!.dir ?? "."}: ${cmd}`] : commands(cmd.task));
  expect(["check:tooling", "check:backend", "check:frontend", "generate:check", "widgetbook:check"].flatMap(commands).sort()).toEqual(commands("check").sort());
});

test("manual main releases schedule only publication and reuse checks from the main push", async () => {
  const workflow = Bun.YAML.parse(await Bun.file(join(ROOT, ".github/workflows/ci.yml")).text()) as { jobs: Record<string, { if: string }> };
  const github = { event_name: "workflow_dispatch", ref: "refs/heads/main" };
  const needs = { changes: { result: "skipped", outputs: {} }, release_prepare: { outputs: { publish: "true" } } };
  const selected = Object.entries(workflow.jobs).filter(([, job]) => new Function("github", "needs", "always", `return (${job.if});`)(github, needs, () => true)).map(([name]) => name);
  expect(selected).toEqual(["release_prepare", "release_native", "release"]);
  needs.release_prepare.outputs.publish = "false";
  for (const name of ["release_native", "release"]) expect(new Function("needs", `return (${workflow.jobs[name]!.if});`)(needs)).toBe(false);
});
