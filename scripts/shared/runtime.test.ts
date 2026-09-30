import { afterEach, describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CommandError, ProcessScope, ROOT, binary, environment, parseEnvironment, processGroupHasLiveMembers, requireFreePort, signalProcessGroup, waitHTTP } from "./runtime.ts";

const temporary: string[] = [];
const scopes: ProcessScope[] = [];
async function directory(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "domabas-bun-test-"));
  temporary.push(path);
  return path;
}
function scope(): ProcessScope { const value = new ProcessScope(); scopes.push(value); return value; }
async function waitForFile(path: string): Promise<void> {
  const deadline = performance.now() + 10000;
  while (!existsSync(path)) {
    if (performance.now() >= deadline) throw new Error("Child process did not become ready.");
    await Bun.sleep(25);
  }
}
afterEach(async () => {
  await Promise.all(scopes.splice(0).map(value => value.close()));
  await Promise.all(temporary.splice(0).map(path => rm(path, { recursive: true, force: true })));
});

describe("environment", () => {
  test("loads literal defaults, preserves equals and empty exported overrides", async () => {
    const file = join(await directory(), ".env");
    await Bun.write(file, "# local\r\nVALUE='a=b'\r\nURL=postgres://u:p@localhost/db?sslmode=disable\nLITERAL=$VALUE\nEMPTY=default\n");
    const actual = environment({ VALUE: "exported", EMPTY: "", MISSING: undefined }, file);
    expect(actual).toEqual({ VALUE: "exported", URL: "postgres://u:p@localhost/db?sslmode=disable", LITERAL: "$VALUE", EMPTY: "" });
    expect(process.env.LITERAL).toBeUndefined();
  });
  test("rejects malformed assignments without exposing values", () => {
    expect(() => parseEnvironment("PRIVATE_SECRET")).toThrow("line 1");
  });
});

describe("process lifecycle", () => {
  test("accepts Darwin EPERM only after leader exit and verified group absence", async () => {
    const permission = Object.assign(new Error("permission denied"), { code: "EPERM" });
    const calls: [number, NodeJS.Signals | 0][] = [];
    const probes: number[] = [];
    const operations = {
      platform: "darwin" as NodeJS.Platform,
      kill: (pid: number, signal: NodeJS.Signals | 0) => { calls.push([pid, signal]); throw permission; },
      absent: async (pid: number) => { probes.push(pid); return true; },
      inactive: async () => { throw new Error("unexpected Linux probe"); },
    };
    for (const signal of ["SIGTERM", 0, "SIGKILL"] as const) {
      expect(await signalProcessGroup(43210, signal, () => true, operations)).toBe(false);
    }
    expect(calls).toEqual([[-43210, "SIGTERM"], [-43210, 0], [-43210, "SIGKILL"]]);
    expect(probes).toEqual([43210, 43210, 43210]);
    await expect(signalProcessGroup(43210, 0, () => false, operations)).rejects.toThrow("EPERM");
    const afterActiveLeader = probes.length;
    await expect(signalProcessGroup(43210, 0, () => true, { ...operations, platform: "linux" })).rejects.toThrow("EPERM");
    expect(probes).toHaveLength(afterActiveLeader);
    await expect(signalProcessGroup(43210, 0, () => true, { ...operations, absent: async () => false })).rejects.toThrow("EPERM");
    await expect(signalProcessGroup(43210, 0, () => true, { ...operations, absent: async () => { throw new Error("probe unavailable"); } })).rejects.toThrow("EPERM");
  });

  test("normal signals and missing groups do not need a process snapshot", async () => {
    const operations = {
      platform: "darwin" as NodeJS.Platform,
      kill: (_pid: number, _signal: NodeJS.Signals | 0) => {},
      absent: async () => { throw new Error("unexpected probe"); },
      inactive: async () => { throw new Error("unexpected Linux probe"); },
    };
    expect(await signalProcessGroup(43210, 0, () => true, operations)).toBe(true);
    operations.kill = () => { throw Object.assign(new Error("missing"), { code: "ESRCH" }); };
    expect(await signalProcessGroup(43210, "SIGTERM", () => false, operations)).toBe(false);
  });

  test("waits for both descendant exit and leader reaping after Darwin EPERM", async () => {
    let probes = 0;
    const operations = {
      platform: "darwin" as NodeJS.Platform,
      kill: () => { throw Object.assign(new Error("exiting group"), { code: "EPERM" }); },
      absent: async () => ++probes >= 2,
      inactive: async () => { throw new Error("unexpected Linux probe"); },
    };
    expect(await signalProcessGroup(43210, 0, () => probes >= 3, operations)).toBe(false);
    expect(probes).toBe(3);
  });

  test("Linux group snapshots distinguish zombies from live or stopped descendants", () => {
    expect(processGroupHasLiveMembers(" 42 Z\n 42 Z+\n 420 S\n", 42)).toBe(false);
    expect(processGroupHasLiveMembers(" 420 S\n", 42)).toBe(false);
    for (const state of ["S", "R+", "D", "T", "t", "I", "unknown"]) {
      expect(processGroupHasLiveMembers(`42 Z\n42 ${state}\n`, 42)).toBe(true);
    }
    for (const snapshot of ["", "42", "PGID STAT\n42 Z", "42 Z extra"]) {
      expect(() => processGroupHasLiveMembers(snapshot, 42)).toThrow("Cannot verify");
    }
  });

  test("Linux accepts zombie-only groups only after leader exit and a successful probe", async () => {
    const calls: (NodeJS.Signals | 0)[] = [], probes: number[] = [];
    const operations = {
      platform: "linux" as NodeJS.Platform,
      kill: (_pid: number, signal: NodeJS.Signals | 0) => { calls.push(signal); },
      absent: async () => { throw new Error("unexpected Darwin probe"); },
      inactive: async (pid: number) => { probes.push(pid); return true; },
    };
    expect(await signalProcessGroup(42, 0, () => false, operations)).toBe(true);
    expect(await signalProcessGroup(42, "SIGTERM", () => true, operations)).toBe(true);
    expect(await signalProcessGroup(42, "SIGKILL", () => true, operations)).toBe(true);
    expect(probes).toEqual([]);
    expect(await signalProcessGroup(42, 0, () => true, operations)).toBe(false);
    expect(probes).toEqual([42]);
    expect(calls).toEqual([0, "SIGTERM", "SIGKILL", 0]);
    expect(await signalProcessGroup(42, 0, () => true, { ...operations, inactive: async () => false })).toBe(true);
    expect(await signalProcessGroup(42, 0, () => true, { ...operations, inactive: async () => { throw new Error("probe failed"); } })).toBe(true);
    await expect(signalProcessGroup(42, 0, () => true, {
      ...operations, kill: () => { throw Object.assign(new Error("denied"), { code: "EPERM" }); },
    })).rejects.toThrow("EPERM");
  });

  test("preserves literal argv and reports child failure without arguments", async () => {
    const args = ["a b", "$(touch nope)", "x&y", "a=b", "single'quote", 'double"quote'];
    const result = await scope().capture([process.execPath, "-e", "console.log(JSON.stringify(process.argv.slice(1)))", ...args]);
    expect(JSON.parse(result.stdout)).toEqual(args);
    const failing = scope();
    await expect(failing.run([process.execPath, "-e", "process.exit(7)", "private-value"])).rejects.toBeInstanceOf(CommandError);
    expect(new CommandError(7, "/bin/tool").message).not.toContain("private-value");
  });

  test("interruption stops owned children", async () => {
    const current = scope();
    const child = current.start([process.execPath, "-e", "setInterval(()=>{},1000)"], { stdout: "ignore", stderr: "ignore" });
    current.interrupt();
    await current.close();
    const exitCode = await child.exited;
    expect(exitCode).not.toBe(0);
    expect(child.exitCode).toBe(exitCode);
    expect(() => current.start([process.execPath, "--version"])).toThrow("Interrupted");
  });

  test.skipIf(process.platform === "win32")("run deadline stops a hung command and its descendants without stopping unrelated children", async () => {
    const current = scope(), file = join(await directory(), "heartbeat");
    const survivor = current.start([process.execPath, "-e", "setInterval(()=>{},1000)"], { stdout: "ignore", stderr: "ignore" });
    const heartbeat = `process.on('SIGTERM',()=>{});await Bun.write(${JSON.stringify(file)},'ready');setInterval(()=>Bun.write(${JSON.stringify(file)},String(Date.now())),25)`;
    const script = `process.on('SIGTERM',()=>{});Bun.spawn([process.execPath,'-e',${JSON.stringify(heartbeat)}],{stdout:'ignore',stderr:'ignore'});setInterval(()=>{},1000)`;
    const result = current.run([process.execPath, "-e", script], { stdout: "ignore", stderr: "ignore", stopGraceMs: 50 }, 2000).then(() => undefined, error => error);
    await waitForFile(file);
    expect(await result).toMatchObject({ message: "Process timed out after 2s." });
    const content = await Bun.file(file).text();
    await Bun.sleep(100);
    expect(await Bun.file(file).text()).toBe(content);
    expect(survivor.exitCode).toBeNull();
    expect(current.children.size).toBe(1);
  });

  test("bounded run preserves successful and nonzero exits", async () => {
    const current = scope();
    await current.run([process.execPath, "-e", "process.exit(0)"], {}, 2000);
    await expect(current.run([process.execPath, "-e", "process.exit(7)"], {}, 2000)).rejects.toMatchObject({ exitCode: 7 });
    expect(current.children.size).toBe(0);
  });

  for (const operation of ["run", "capture", "capture-nonzero"] as const) {
    test.skipIf(process.platform === "win32")(`${operation} cleans descendants after a completed wrapper redirects their pipes`, async () => {
      const current = scope(), file = join(await directory(), "heartbeat");
      const heartbeat = `await Bun.write(${JSON.stringify(file)},'ready');setInterval(()=>Bun.write(${JSON.stringify(file)},String(Date.now())),25)`;
      const exitCode = operation === "capture-nonzero" ? 7 : 0;
      const script = `const c=Bun.spawn([process.execPath,'-e',${JSON.stringify(heartbeat)}],{stdout:'ignore',stderr:'ignore'});c.unref();while(!await Bun.file(${JSON.stringify(file)}).exists())await Bun.sleep(25);console.log('wrapper output');process.exit(${exitCode})`;
      const args = [process.execPath, "-e", script];
      const result = operation === "run"
        ? current.run(args, { stdout: "ignore", stderr: "ignore" })
        : current.capture(args);
      const child = [...current.children][0]!;
      try {
        const captured = await result;
        if (captured) expect(captured).toEqual({ code: exitCode, stdout: "wrapper output\n", stderr: "" });
        expect(await child.exited).toBe(exitCode);
        await current.close();
        await Bun.sleep(60);
        const content = await Bun.file(file).text();
        await Bun.sleep(100);
        expect(await Bun.file(file).text()).toBe(content);
        expect(current.children.size).toBe(0);
      } finally { await child.stop(); }
    });
  }

  for (const operation of ["run", "capture"] as const) {
    test.skipIf(process.platform === "win32")(`${operation} interruption cleans wrapper and descendants and preserves its reason`, async () => {
      const current = scope(), file = join(await directory(), "heartbeat");
      const heartbeat = `process.on('SIGTERM',()=>{});await Bun.write(${JSON.stringify(file)},'ready');setInterval(()=>Bun.write(${JSON.stringify(file)},String(Date.now())),25)`;
      const script = `Bun.spawn([process.execPath,'-e',${JSON.stringify(heartbeat)}],{stdout:'ignore',stderr:'ignore'});setInterval(()=>{},1000)`;
      const result = current[operation]([process.execPath, "-e", script], { stdout: "ignore", stderr: "ignore", stopGraceMs: 50 }).then(() => undefined, error => error);
      await waitForFile(file);
      const reason = new Error("test cancelled wrapper");
      current.interrupt(reason);
      expect(await result).toBe(reason);
      await current.close();
      await Bun.sleep(60);
      const content = await Bun.file(file).text();
      await Bun.sleep(100);
      expect(await Bun.file(file).text()).toBe(content);
      expect(current.children.size).toBe(0);
    });
  }

  test.skipIf(process.platform === "win32")("capture bounds inherited pipe lifetime after the leader exits", async () => {
    const current = scope();
    const script = `const c=Bun.spawn([process.execPath,'-e','setInterval(()=>{},1000)'],{stdout:'inherit',stderr:'inherit'});c.unref();process.exit(0)`;
    const started = performance.now();
    await expect(current.capture([process.execPath, "-e", script], {}, 150)).rejects.toThrow("timed out");
    expect(performance.now() - started).toBeLessThan(3000);
  });

  test.skipIf(process.platform === "win32")("stops descendants after their group leader exits", async () => {
    const file = join(await directory(), "heartbeat");
    const heartbeat = `await Bun.write(${JSON.stringify(file)},'ready');setInterval(()=>Bun.write(${JSON.stringify(file)},String(Date.now())),25)`;
    const script = `const c=Bun.spawn([process.execPath,'-e',${JSON.stringify(heartbeat)}],{stdout:'ignore',stderr:'ignore'});c.unref();while(!await Bun.file(${JSON.stringify(file)}).exists())await Bun.sleep(25);process.exit(0)`;
    const child = scope().start([process.execPath, "-e", script], { stdout: "ignore", stderr: "ignore" });
    expect(await child.wait(10000)).toBe(0);
    expect(existsSync(file)).toBe(true);
    await child.stop();
    await Bun.sleep(60);
    const content = await Bun.file(file).text();
    await Bun.sleep(100);
    expect(await Bun.file(file).text()).toBe(content);
  });

  test.skipIf(process.platform === "win32")("lets a child drain after its wrapper exits on TERM", async () => {
    const file = join(await directory(), "drained");
    const ready = `${file}.ready`;
    const draining = `process.on('SIGTERM',async()=>{await Bun.sleep(150);await Bun.write(${JSON.stringify(file)},'complete');process.exit(0)});await Bun.write(${JSON.stringify(ready)},'ready');setInterval(()=>{},1000)`;
    const wrapper = `Bun.spawn([process.execPath,'-e',${JSON.stringify(draining)}],{stdout:'ignore',stderr:'ignore'});setInterval(()=>{},1000)`;
    const child = scope().start([process.execPath, "-e", wrapper], { stdout: "ignore", stderr: "ignore", stopGraceMs: 5000 });
    await waitForFile(ready);
    expect(existsSync(ready)).toBe(true);
    await child.stop();
    expect(await Bun.file(file).text()).toBe("complete");
  });

  test.skipIf(process.platform === "win32")("CLI SIGTERM exits 130 and cleans a detached child", async () => {
    const dir = await directory();
    const file = join(dir, "heartbeat");
    const fixture = join(dir, "supervisor.ts");
    const heartbeat = `await Bun.write(${JSON.stringify(file)},'ready');setInterval(()=>Bun.write(${JSON.stringify(file)},String(Date.now())),25)`;
    await Bun.write(fixture, `import {runCLI} from ${JSON.stringify(join(ROOT, "scripts/shared/runtime.ts"))};await runCLI(async scope=>{await scope.start([process.execPath,'-e',${JSON.stringify(heartbeat)}],{stdout:'ignore',stderr:'ignore'}).exited;});`);
    const supervisor = scope().start([process.execPath, "--no-env-file", fixture], { stdout: "ignore", stderr: "ignore" });
    await waitForFile(file);
    expect(existsSync(file)).toBe(true);
    process.kill(supervisor.pid, "SIGTERM");
    expect(await supervisor.wait(10000)).toBe(130);
    await Bun.sleep(60);
    const content = await Bun.file(file).text();
    await Bun.sleep(100);
    expect(await Bun.file(file).text()).toBe(content);
  });

  test("CLI deadline fails and still completes harness cleanup", async () => {
    const dir = await directory(), cleaned = join(dir, "cleaned"), fixture = join(dir, "deadline.ts");
    await Bun.write(fixture, `import {runCLI,withCleanup} from ${JSON.stringify(join(ROOT, "scripts/shared/runtime.ts"))};await runCLI(scope=>withCleanup(async()=>{await scope.run([process.execPath,'-e','setInterval(()=>{},1000)']);},async()=>{await Bun.write(${JSON.stringify(cleaned)},'complete');}),{timeoutMs:500});`);
    const result = await scope().capture([process.execPath, "--no-env-file", fixture], {}, 10000);
    expect(result.code).toBe(1);
    expect(result.stderr).toContain("Command timed out after 0.5s.");
    expect(await Bun.file(cleaned).text()).toBe("complete");
  });

  test.skipIf(process.platform !== "win32")("launches a batch wrapper with spaces and metacharacter arguments", async () => {
    const dir = await directory();
    const fixture = join(dir, "wrapper with spaces.cmd");
    await Bun.write(fixture, `@echo off\r\n"${process.execPath}" -e "console.log(JSON.stringify(process.argv.slice(1)))" %*\r\n`);
    const args = ["two words", "x&y", "a=b"];
    const result = await scope().capture([fixture, ...args]);
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual(args);
  });

  test("uses platform-specific executable extensions", () => {
    expect(binary("psql", "win32")).toBe("psql.exe");
    expect(binary("psql", "linux")).toBe("psql");
  });
});

describe("readiness", () => {
  test("accepts healthy HTTP and rejects an occupied port", async () => {
    const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response("ready") });
    try {
      await waitHTTP(`http://127.0.0.1:${server.port}`, undefined, 1000);
      await expect(requireFreePort("127.0.0.1", server.port!)).rejects.toThrow("unavailable");
    } finally { await server.stop(true); }
  });
  test("fails readiness when its child exits, and honors cancellation", async () => {
    const child = scope().start([process.execPath, "-e", "process.exit(9)"], { stdout: "ignore", stderr: "ignore" });
    await child.exited;
    await expect(waitHTTP("http://127.0.0.1:1", child, 1000)).rejects.toThrow("exit 9");
    const abort = new AbortController();
    abort.abort(new Error("cancelled"));
    await expect(waitHTTP("http://127.0.0.1:1", undefined, 1000, abort.signal)).rejects.toThrow("cancelled");
  });
});
