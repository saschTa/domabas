import { afterEach, describe, expect, test } from "bun:test";
import { chmod, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { composeArguments } from "./compose.ts";
import { developmentComposeOverrides, ollamaRuntime } from "./development-infrastructure.ts";
import { OLLAMA_VERSION, nativeOllamaEnvironment, withNativeOllama } from "./native-ollama.ts";
import { ROOT, ProcessScope, environment, requireFreePort, waitHTTP } from "../shared/runtime.ts";

const temporary: string[] = [];
afterEach(async () => { await Promise.all(temporary.splice(0).map(path => rm(path, { recursive: true, force: true }))); });

describe("development Ollama selection", () => {
  test("selects all four runtimes and rejects typos or unsupported MLX hosts", () => {
    expect(ollamaRuntime({})).toBe("cpu");
    for (const runtime of ["cpu", "cuda", "rocm", "mlx"] as const) {
      expect(ollamaRuntime({ OLLAMA_RUNTIME: runtime }, "darwin", "arm64")).toBe(runtime);
      expect(developmentComposeOverrides(runtime)).toEqual(runtime === "cpu" ? [] : [join(ROOT, `compose.${runtime}.yaml`)]);
    }
    for (const value of ["", "metal", "CUDA"]) expect(() => ollamaRuntime({ OLLAMA_RUNTIME: value })).toThrow("must be");
    expect(() => ollamaRuntime({ OLLAMA_RUNTIME: "mlx" }, "darwin", "x64")).toThrow("Apple Silicon");
    expect(() => ollamaRuntime({ OLLAMA_RUNTIME: "mlx" }, "linux", "arm64")).toThrow("Apple Silicon");
  });

  test("one file setting is overridden by an exported selector", async () => {
    const dir = await mkdtemp(join(tmpdir(), "domabas-runtime-test-"));
    temporary.push(dir);
    const file = join(dir, ".env");
    await Bun.write(file, "OLLAMA_RUNTIME=mlx\n");
    expect(ollamaRuntime(environment({}, file), "darwin", "arm64")).toBe("mlx");
    expect(ollamaRuntime(environment({ OLLAMA_RUNTIME: "rocm" }, file))).toBe("rocm");
  });

  test("native inference keeps a managed private origin and cache", () => {
    const input = { OLLAMA_HOST: "0.0.0.0:11434", OLLAMA_MODELS: "/unrelated", OLLAMA_MAX_QUEUE: "256", OLLAMA_NO_CLOUD: "0" };
    const result = nativeOllamaEnvironment(input);
    expect(result.OLLAMA_HOST).toBe("127.0.0.1:11435");
    expect(result.OLLAMA_MODELS).toBe(join(ROOT, ".cache/ollama/models"));
    expect(result.OLLAMA_MAX_QUEUE).toBe("256");
    expect(result.OLLAMA_NO_CLOUD).toBe("1");
    expect(input.OLLAMA_MODELS).toBe("/unrelated");
    expect(nativeOllamaEnvironment({ LLM_OLLAMA_PORT: "11439", LLM_OLLAMA_URL: "http://127.0.0.1:11439" }).OLLAMA_HOST).toBe("127.0.0.1:11439");
    for (const port of ["0", "65536", "-1", "11435x"]) expect(() => nativeOllamaEnvironment({ LLM_OLLAMA_PORT: port })).toThrow("LLM_OLLAMA_PORT");
    expect(() => nativeOllamaEnvironment({ LLM_OLLAMA_URL: "http://other:11435" })).toThrow("LLM_OLLAMA_URL");
    expect(() => nativeOllamaEnvironment({ COMPOSE_PROFILES: "tools,container-ollama" })).toThrow("profile");
  });

  test.skipIf(!Bun.which("docker"))("development overrides are explicit; ordinary Compose ignores the selector", () => {
    const base = composeArguments(["config"]);
    expect(base.filter(arg => arg.endsWith(".yaml"))).toEqual([join(ROOT, "compose.yaml")]);
    const cuda = composeArguments(["config"], developmentComposeOverrides("cuda"));
    expect(cuda.filter(arg => arg.endsWith(".yaml"))).toEqual([join(ROOT, "compose.yaml"), join(ROOT, "compose.cuda.yaml")]);
  });
});

async function nativeFixture() {
  const dir = await mkdtemp(join(tmpdir(), "domabas-native-ollama-test-"));
  temporary.push(dir);
  const reserve = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
  const port = reserve.port!;
  await reserve.stop(true);
  const executable = join(dir, "ollama");
  await Bun.write(executable, `#!${process.execPath}
Bun.serve({ hostname: "127.0.0.1", port: Number(process.env.LLM_OLLAMA_PORT), async fetch(request) {
  const path = new URL(request.url).pathname;
  if (path === "/exit") setTimeout(() => process.exit(7), 10);
  if (path === "/drain") await Bun.write(process.env.DRAIN_RECORD!, "native still ready");
  return Response.json({ version: process.env.FIXTURE_VERSION });
} });
`);
  await chmod(executable, 0o755);
  const env = { ...process.env, LLM_OLLAMA_PORT: String(port), LLM_OLLAMA_URL: `http://127.0.0.1:${port}`, FIXTURE_VERSION: OLLAMA_VERSION, DRAIN_RECORD: join(dir, "drained") };
  return { executable, env, port, dir };
}

describe.skipIf(process.platform === "win32")("native Ollama process ownership", () => {
  test("infrastructure CLI selects Docker overrides and keeps the test baseline independent of MLX", async () => {
    const dir = await mkdtemp(join(tmpdir(), "domabas-compose-selection-test-"));
    temporary.push(dir);
    const docker = join(dir, "docker");
    const log = join(dir, "commands");
    await Bun.write(docker, `#!${process.execPath}
import { appendFile } from "node:fs/promises";
await appendFile(process.env.COMMAND_LOG!, JSON.stringify(process.argv.slice(2)) + "\\n");
`);
    await chmod(docker, 0o755);
    const scope = new ProcessScope();
    try {
      for (const runtime of ["cpu", "cuda", "rocm", "mlx"]) {
        await Bun.write(log, "");
        const args = [process.execPath, "--no-env-file", join(ROOT, "scripts/development/compose.ts"), "infra-up"];
        if (runtime === "mlx") args.push("--docker-only");
        const result = await scope.capture(args, { env: { ...process.env, OLLAMA_RUNTIME: runtime, PATH: `${dir}:${process.env.PATH}`, COMMAND_LOG: log } });
        expect(result.code).toBe(0);
        const calls = (await Bun.file(log).text()).trim().split("\n").map(line => JSON.parse(line) as string[]);
        expect(calls).toHaveLength(3);
        expect(calls[1]!.slice(-5)).toEqual(["run", "--build", "--rm", "--no-deps", "temporal-init"]);
        expect(calls[2]!.slice(-6)).toEqual(["up", "--no-deps", "--wait", "--wait-timeout", "90", "temporal-ui"]);
        for (const call of calls) {
          expect(call.filter(arg => arg.endsWith(".yaml"))).toEqual([join(ROOT, "compose.yaml"), ...developmentComposeOverrides(runtime === "mlx" ? "cpu" : runtime as "cpu" | "cuda" | "rocm")]);
          expect(call).not.toContain("--volumes");
        }
      }
    } finally { await scope.close(); }
  });

  test.each([false, true])("drains application processes before native Ollama on failure=%s", async failure => {
    const fixture = await nativeFixture();
    const scope = new ProcessScope();
    let nativePID = 0;
    const result = withNativeOllama(scope, fixture.env, fixture.executable, async native => {
      nativePID = native.pid;
      const application = scope.start([process.execPath, "--no-env-file", "-e", `
        process.on("SIGTERM", async () => {
          await fetch(process.env.LLM_OLLAMA_URL + "/drain");
          process.exit(0);
        });
        await Bun.write(process.env.APP_READY!, "ready");
        setInterval(() => {}, 1000);
      `], { env: { ...fixture.env, APP_READY: join(fixture.dir, "app-ready") } });
      const deadline = performance.now() + 5000;
      while (!await Bun.file(join(fixture.dir, "app-ready")).exists()) {
        if (performance.now() > deadline || application.exitCode !== null) throw new Error("Application fixture did not start.");
        await Bun.sleep(10);
      }
      if (failure) throw new Error("application failed");
      return "done";
    });
    if (failure) await expect(result).rejects.toThrow("application failed");
    else expect(await result).toBe("done");
    expect(await Bun.file(fixture.env.DRAIN_RECORD).text()).toBe("native still ready");
    expect(() => process.kill(nativePID, 0)).toThrow();
    await requireFreePort("127.0.0.1", fixture.port);
  });

  test("native failure terminates the session and releases the listener", async () => {
    const fixture = await nativeFixture();
    const scope = new ProcessScope();
    await expect(withNativeOllama(scope, fixture.env, fixture.executable, async () => {
      await fetch(`${fixture.env.LLM_OLLAMA_URL}/exit`);
      return await new Promise<never>(() => {});
    })).rejects.toThrow("Native Ollama exited (7)");
    await requireFreePort("127.0.0.1", fixture.port);
  });

  test("startup rejects a mismatched version and cleans up the process", async () => {
    const fixture = await nativeFixture();
    await expect(withNativeOllama(new ProcessScope(), { ...fixture.env, FIXTURE_VERSION: "wrong" }, fixture.executable, async () => {
      throw new Error("must not run");
    })).rejects.toThrow(`must be version ${OLLAMA_VERSION}`);
    await requireFreePort("127.0.0.1", fixture.port);
  });

  test("cancellation closes the owned server", async () => {
    const fixture = await nativeFixture();
    const scope = new ProcessScope();
    await expect(withNativeOllama(scope, fixture.env, fixture.executable, async native => {
      scope.interrupt(new Error("cancelled"));
      await waitHTTP(`${fixture.env.LLM_OLLAMA_URL}/api/version`, native, 1000, scope.signal);
    })).rejects.toThrow("cancelled");
    await requireFreePort("127.0.0.1", fixture.port);
  });

  test("does not reuse or stop an unrelated listener", async () => {
    const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response("unrelated") });
    try {
      await expect(withNativeOllama(new ProcessScope(), { LLM_OLLAMA_PORT: String(server.port) }, "/missing", async () => {})).rejects.toThrow("unavailable");
      expect(await (await fetch(server.url)).text()).toBe("unrelated");
    } finally { await server.stop(true); }
  });
});
