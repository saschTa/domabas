import { readFileSync } from "node:fs";
import { createServer } from "node:net";
import { basename, join, resolve } from "node:path";
import { Readable } from "node:stream";
import crossSpawn from "cross-spawn";

export const ROOT = resolve(import.meta.dir, "../..");
export type Environment = Record<string, string | undefined>;

export function parseEnvironment(text: string): Environment {
  const values: Environment = {};
  for (const [index, original] of text.split(/\r?\n/).entries()) {
    const line = original.trim();
    if (!line || line.startsWith("#")) continue;
    const match = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!match) throw new Error(`Invalid environment assignment on line ${index + 1}.`);
    let value = match[2]!;
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[match[1]!] = value;
  }
  return values;
}

export function environment(overrides: Environment = process.env, file = join(ROOT, "backend/.env")): Environment {
  const values = parseEnvironment(readFileSync(file, "utf8"));
  for (const [name, value] of Object.entries(overrides)) {
    if (value !== undefined) values[name] = value;
  }
  return values;
}

export function required(values: Environment, name: string): string {
  const value = values[name];
  if (!value) throw new Error(`Required environment variable ${name} is missing.`);
  return value;
}

export function binary(name: string, platform = process.platform): string {
  return platform === "win32" ? `${name}.exe` : name;
}

export function command(name: string): string {
  const executable = Bun.which(name);
  if (!executable) throw new Error(`Required command '${name}' is missing from PATH. See docs/development/index.md.`);
  return executable;
}

export interface ProcessOptions {
  cwd?: string;
  env?: Environment;
  stdin?: "inherit" | "ignore";
  stdout?: "inherit" | "pipe" | "ignore" | number;
  stderr?: "inherit" | "pipe" | "ignore" | number;
  stopGraceMs?: number;
}

export class CommandError extends Error {
  constructor(readonly exitCode: number, executable: string) {
    super(`${basename(executable)} exited with status ${exitCode}.`);
  }
}

function missingProcess(error: unknown): boolean {
  return (error as NodeJS.ErrnoException).code === "ESRCH";
}

async function processGroupAbsent(pid: number): Promise<boolean> {
  const snapshot = Bun.spawn(["/bin/ps", "-axo", "pgid="], { stdout: "pipe", stderr: "ignore", timeout: 1000 });
  const [code, output] = await Promise.all([snapshot.exited, new Response(snapshot.stdout).text()]);
  const groups = output.trim().split(/\s+/);
  if (code !== 0 || !groups.every(group => /^[1-9]\d*$/.test(group))) throw new Error("Cannot verify the owned process group.");
  return !groups.includes(String(pid));
}

export function processGroupHasLiveMembers(output: string, pid: number): boolean {
  const members = output.trim().split(/\r?\n/).map(line => {
    const match = /^\s*(\d+)\s+(\S+)\s*$/.exec(line);
    if (!match) throw new Error("Cannot verify the owned process group states.");
    return { group: Number(match[1]), state: match[2]! };
  });
  return members.some(member => member.group === pid && !/^Z[+<Nsl]*$/.test(member.state));
}

async function processGroupInactive(pid: number): Promise<boolean> {
  const snapshot = Bun.spawn(["/bin/ps", "-axo", "pgid=,stat="], { stdout: "pipe", stderr: "ignore", timeout: 1000 });
  const [code, output] = await Promise.all([snapshot.exited, new Response(snapshot.stdout).text()]);
  if (code !== 0) throw new Error("Cannot verify the owned process group states.");
  return !processGroupHasLiveMembers(output, pid);
}

interface GroupSignalOperations {
  platform: NodeJS.Platform;
  kill: (pid: number, signal: NodeJS.Signals | 0) => unknown;
  absent: (pid: number) => Promise<boolean>;
  inactive: (pid: number) => Promise<boolean>;
}

export async function signalProcessGroup(
  pid: number, signal: NodeJS.Signals | 0, leaderExited: () => boolean,
  operations: GroupSignalOperations = { platform: process.platform, kill: process.kill, absent: processGroupAbsent, inactive: processGroupInactive },
): Promise<boolean> {
  try { operations.kill(-pid, signal); }
  catch (error) {
    if (missingProcess(error)) return false;
    if (operations.platform === "darwin" && (error as NodeJS.ErrnoException).code === "EPERM") {
      const deadline = performance.now() + 500;
      do {
        try { if (await operations.absent(pid) && leaderExited()) return false; } catch { break; }
        if (performance.now() >= deadline) break;
        await Bun.sleep(Math.min(25, Math.max(0, deadline - performance.now())));
      } while (performance.now() < deadline);
    }
    throw new Error(`Cannot signal owned process group ${pid} with ${signal}: ${(error as NodeJS.ErrnoException).code ?? "unknown error"}.`, { cause: error });
  }
  if (operations.platform === "linux" && signal === 0 && leaderExited()) {
    try { if (await operations.inactive(pid)) return false; } catch {}
  }
  return true;
}

export class ManagedProcess {
  readonly process: {
    pid: number;
    exitCode: number | null;
    exited: Promise<number>;
    stdout: ReadableStream | null;
    stderr: ReadableStream | null;
  };
  private stopping?: Promise<void>;
  private readonly stopGraceMs: number;

  constructor(args: readonly string[], options: ProcessOptions = {}) {
    this.stopGraceMs = options.stopGraceMs ?? 8000;
    if (!args[0]) throw new Error("Cannot run an empty command.");
    const settings = {
      cwd: options.cwd ?? ROOT,
      env: options.env ?? process.env,
      detached: true,
      stdin: options.stdin ?? "ignore",
      stdout: options.stdout ?? "inherit",
      stderr: options.stderr ?? "inherit",
    };
    if (process.platform === "win32" && /\.(bat|cmd)$/i.test(args[0])) {
      // Keep Flutter's bootstrap wrapper; cross-spawn handles Windows batch quoting.
      const child = crossSpawn(args[0], args.slice(1), {
        cwd: settings.cwd, env: settings.env, detached: true,
        stdio: [settings.stdin, settings.stdout, settings.stderr],
      });
      const exited = new Promise<number>((resolveExit, reject) => {
        child.once("error", reject);
        child.once("close", (code, signal) => resolveExit(code ?? (signal ? 130 : 1)));
      });
      this.process = {
        pid: child.pid ?? 0,
        get exitCode() { return child.exitCode ?? (child.signalCode ? 130 : null); },
        exited,
        stdout: child.stdout ? Readable.toWeb(child.stdout) as unknown as ReadableStream : null,
        stderr: child.stderr ? Readable.toWeb(child.stderr) as unknown as ReadableStream : null,
      };
    } else {
      const child = Bun.spawn([...args], settings);
      let settledExitCode: number | null = null;
      const exited = child.exited.then(code => { settledExitCode = code; return code; });
      this.process = {
        pid: child.pid,
        get exitCode() { return child.exitCode ?? settledExitCode; },
        exited,
        stdout: child.stdout instanceof ReadableStream ? child.stdout : null,
        stderr: child.stderr instanceof ReadableStream ? child.stderr : null,
      };
    }
  }

  get pid(): number { return this.process.pid; }
  get exitCode(): number | null { return this.process.exitCode; }
  get exited(): Promise<number> { return this.process.exited; }

  async wait(timeoutMs?: number): Promise<number> {
    if (timeoutMs === undefined) return this.exited;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        this.exited,
        new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(`Process timed out after ${timeoutMs / 1000}s.`)), timeoutMs); }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }

  stop(graceMs = this.stopGraceMs): Promise<void> {
    return this.stopping ??= this.stopGroup(graceMs);
  }

  private signalGroup(signal: NodeJS.Signals | 0): Promise<boolean> {
    return signalProcessGroup(this.pid, signal, () => this.exitCode !== null);
  }

  private async stopGroup(graceMs: number): Promise<void> {
    if (process.platform === "win32") {
      if (this.exitCode === null) {
        const killer = Bun.spawn([command("taskkill"), "/T", "/F", "/PID", String(this.pid)], { stdout: "ignore", stderr: "ignore" });
        await killer.exited;
      }
      return;
    }
    // Air/Flutter can outlive an exited group leader, so always address its group.
    if (!await this.signalGroup("SIGTERM")) { await this.exited; return; }
    // A wrapper (go tool/Air) can exit before its service finishes draining.
    // Give the whole owned group its grace period, not only the group leader.
    const deadline = performance.now() + graceMs;
    while (performance.now() < deadline) {
      if (!await this.signalGroup(0)) { await this.exited; return; }
      await Bun.sleep(Math.min(25, Math.max(0, deadline - performance.now())));
    }
    await this.signalGroup("SIGKILL");
    await this.exited;
  }
}

export class ProcessScope {
  readonly controller = new AbortController();
  readonly children = new Set<ManagedProcess>();
  get signal(): AbortSignal { return this.controller.signal; }

  start(args: readonly string[], options: ProcessOptions = {}): ManagedProcess {
    this.signal.throwIfAborted();
    const child = new ManagedProcess(args, options);
    this.children.add(child);
    return child;
  }

  async run(args: readonly string[], options: ProcessOptions = {}, timeoutMs?: number): Promise<void> {
    const child = this.start(args, options);
    await withCleanup(async () => {
      const code = await child.wait(timeoutMs);
      this.signal.throwIfAborted();
      if (code) throw new CommandError(code, args[0]!);
    }, async () => {
      await child.stop();
      this.children.delete(child);
    });
  }

  async capture(args: readonly string[], options: ProcessOptions = {}, timeoutMs = 10000): Promise<{ code: number; stdout: string; stderr: string }> {
    const child = this.start(args, { ...options, stdout: "pipe", stderr: "pipe" });
    let timer: ReturnType<typeof setTimeout> | undefined;
    return withCleanup(async () => {
      const output = Promise.all([
        child.exited,
        new Response(child.process.stdout as ReadableStream).text(),
        new Response(child.process.stderr as ReadableStream).text(),
      ]);
      // Descendants can retain pipes after their leader exits; bound the complete capture.
      const [code, stdout, stderr] = await Promise.race([
        output,
        new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(`Process timed out after ${timeoutMs / 1000}s.`)), timeoutMs); }),
      ]);
      this.signal.throwIfAborted();
      return { code, stdout, stderr };
    }, async () => {
      clearTimeout(timer);
      await child.stop();
      this.children.delete(child);
    });
  }

  interrupt(reason = new Error("Interrupted.")): void {
    this.controller.abort(reason);
    for (const child of this.children) void child.stop().catch(() => {});
  }

  async close(): Promise<void> {
    const results = await Promise.allSettled([...this.children].reverse().map(child => child.stop()));
    const failed = results.find(result => result.status === "rejected");
    if (failed?.status === "rejected") throw failed.reason;
  }
}

export async function withCleanup<T>(
  work: () => Promise<T>, cleanup: () => Promise<void>,
  reportCleanup: (error: unknown) => void = error => console.error(`Cleanup failed: ${error instanceof Error ? error.message : String(error)}`),
): Promise<T> {
  let failed = false;
  try { return await work(); }
  catch (error) { failed = true; throw error; }
  finally {
    try { await cleanup(); }
    catch (error) { if (failed) reportCleanup(error); else throw error; }
  }
}

export async function runCLI(action: (scope: ProcessScope) => Promise<void | number>, options: { timeoutMs?: number } = {}): Promise<void> {
  const scope = new ProcessScope();
  const interrupt = () => scope.interrupt();
  process.on("SIGINT", interrupt);
  process.on("SIGTERM", interrupt);
  let timedOut = false;
  const timer = options.timeoutMs === undefined ? undefined : setTimeout(() => {
    if (scope.signal.aborted) return;
    timedOut = true;
    const error = new Error(`Command timed out after ${options.timeoutMs! / 1000}s.`);
    console.error(error.message);
    scope.interrupt(error);
  }, options.timeoutMs);
  let failure: unknown;
  try {
    process.exitCode = (await action(scope)) ?? 0;
  } catch (error) {
    failure = error;
    process.exitCode = scope.signal.aborted ? 130 : error instanceof CommandError ? error.exitCode : 1;
    if (!scope.signal.aborted) console.error(error instanceof Error ? error.message : String(error));
  } finally {
    try { await scope.close(); } catch (error) {
      console.error(`Process cleanup failed: ${error instanceof Error ? error.message : String(error)}`);
      if (!failure) process.exitCode = 1;
    }
    clearTimeout(timer);
    if (scope.signal.aborted) process.exitCode = timedOut ? 1 : 130;
    process.off("SIGINT", interrupt);
    process.off("SIGTERM", interrupt);
  }
}

export async function waitHTTP(url: string, child?: ManagedProcess, timeoutMs = 90000, signal?: AbortSignal): Promise<void> {
  const deadline = performance.now() + timeoutMs;
  while (performance.now() < deadline) {
    signal?.throwIfAborted();
    if (child && child.exitCode !== null) throw new Error(`Process exited before ${url} was ready (exit ${child.exitCode}).`);
    try {
      const timeout = AbortSignal.timeout(Math.min(1000, Math.max(1, deadline - performance.now())));
      const response = await fetch(url, { signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
      await response.body?.cancel();
      if (response.status === 200) return;
    } catch { signal?.throwIfAborted(); }
    await Bun.sleep(Math.min(250, Math.max(0, deadline - performance.now())));
  }
  throw new Error(`Timed out waiting for ${url}.`);
}

export async function requireFreePort(host: string, port: number): Promise<void> {
  await new Promise<void>((resolvePromise, reject) => {
    const server = createServer();
    server.once("error", () => reject(new Error(`Port ${host}:${port} is unavailable; stop the existing listener first.`)));
    server.listen({ host, port, exclusive: true }, () => server.close(error => error ? reject(error) : resolvePromise()));
  });
}

export async function download(url: string, destination: string, signal?: AbortSignal): Promise<void> {
  const timeout = AbortSignal.timeout(300000);
  const response = await fetch(url, { signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
  if (!response.ok) throw new Error(`Download failed: HTTP ${response.status} from ${new URL(url).hostname}.`);
  await Bun.write(destination, response);
}
