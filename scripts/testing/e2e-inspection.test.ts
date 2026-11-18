import { afterEach, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inspectionArguments, prepareInspection, waitForInspection } from "./e2e-inspection.ts";
import { withTemporarySchema } from "./e2e.ts";
import { ProcessScope } from "../shared/runtime.ts";

const directories: string[] = [];
async function temporary(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "domabas-inspection-test-"));
  directories.push(directory);
  return directory;
}
afterEach(async () => { await Promise.all(directories.splice(0).map(directory => rm(directory, { recursive: true, force: true }))); });

test("inspection starts production main without driver or injected Flutter fixtures", () => {
  expect(inspectionArguments("flutter", "127.0.0.1", 18537, "http://127.0.0.1:18538")).toEqual([
    "flutter", "run", "--release", "--no-web-resources-cdn", "--target=lib/main.dart", "-d", "web-server",
    "--web-hostname=127.0.0.1", "--web-port=18537", "--dart-define=API_BASE_URL=http://127.0.0.1:18538",
  ]);
});

test("inspection registers through the normal API and stores only a private credential manifest", async () => {
  let request: { accountName: string; email: string; password: string } | undefined;
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch(incoming) {
    expect(new URL(incoming.url).pathname).toBe("/api/v1/auth/register");
    expect(incoming.method).toBe("POST");
    request = await incoming.json() as typeof request;
    return Response.json({ token: "must-not-be-persisted" }, { status: 201 });
  } });
  try {
    const directory = await temporary();
    const result = await prepareInspection(directory, server.url.origin, "http://127.0.0.1:18537", new AbortController().signal);
    const text = await readFile(result.manifest, "utf8");
    const manifest = JSON.parse(text);
    expect(request!.accountName).toBe("Glacier review library");
    expect(request!.email).toMatch(/^inspection-.*@example\.com$/);
    expect(request!.password.length).toBeGreaterThan(30);
    expect(manifest.email).toBe(request!.email);
    expect(manifest.password).toBe(request!.password);
    expect(manifest.stopFile).toBe(join(directory, "inspection.stop"));
    expect(text).not.toContain("must-not-be-persisted");
    if (process.platform !== "win32") expect((await stat(result.manifest)).mode & 0o777).toBe(0o600);
  } finally { server.stop(true); }
});

test("failed registration does not produce a usable credential manifest", async () => {
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response("secret server detail", { status: 503 }) });
  try {
    const directory = await temporary();
    await expect(prepareInspection(directory, server.url.origin, "http://127.0.0.1:18537", new AbortController().signal)).rejects.toThrow("registration failed (503)");
    await expect(stat(join(directory, "inspection.json"))).rejects.toThrow();
  } finally { server.stop(true); }
});

for (const end of ["stop file", "interrupt", "child exit", "deadline"] as const) {
  test(`inspection ${end} reaches owned-process and schema cleanup`, async () => {
    const directory = await temporary(), stopFile = join(directory, "stop");
    const scope = new ProcessScope();
    const child = scope.start([process.execPath, "--no-env-file", "-e", "setInterval(() => {}, 1000)"], { stdout: "ignore", stderr: "ignore" });
    const order: string[] = [];
    let failed = false;
    try {
      await withTemporarySchema(async () => { order.push("create"); }, async () => {
        const controller = new AbortController();
        let code: number | null = null;
        const timer = setTimeout(() => {
          if (end === "stop file") void writeFile(stopFile, "done");
          if (end === "interrupt") controller.abort();
          if (end === "child exit") code = 7;
        }, 10);
        try {
          await waitForInspection(stopFile, controller.signal, () => code, { intervalMs: 5, timeoutMs: end === "deadline" ? 25 : 500 });
        } finally {
          clearTimeout(timer);
          await scope.close();
          order.push("processes stopped");
        }
      }, async () => {
        expect(child.exitCode).not.toBeNull();
        order.push("drop owned schema");
      });
    } catch { failed = true; }
    finally { await scope.close(); }
    expect(failed).toBe(end !== "stop file");
    expect(order).toEqual(["create", "processes stopped", "drop owned schema"]);
  });
}
