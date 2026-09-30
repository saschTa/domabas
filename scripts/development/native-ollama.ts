import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { sha256 } from "../generation/generate-client.ts";
import { ROOT, type Environment, type ManagedProcess, ProcessScope, command, download, requireFreePort, waitHTTP, withCleanup } from "../shared/runtime.ts";

export const OLLAMA_VERSION = "0.34.1";
export const OLLAMA_DARWIN_SHA256 = "f18fba83fb1eb415e143fb0c24372ebc4388fd7206f4927d4899932653e8c11d";

export function nativeOllamaEnvironment(env: Environment): Environment {
  const port = env.LLM_OLLAMA_PORT ?? "11435";
  if (!/^\d+$/.test(port) || Number(port) < 1 || Number(port) > 65535) throw new Error("MLX requires LLM_OLLAMA_PORT between 1 and 65535.");
  const origin = `http://127.0.0.1:${port}`;
  if (env.LLM_OLLAMA_URL !== undefined && env.LLM_OLLAMA_URL !== origin) throw new Error(`MLX requires LLM_OLLAMA_URL=${origin} to match its managed loopback listener.`);
  if ((env.COMPOSE_PROFILES ?? "").split(",").includes("container-ollama")) throw new Error("MLX cannot use the container-ollama Compose profile.");
  return {
    ...env,
    LLM_OLLAMA_PORT: port,
    LLM_OLLAMA_URL: origin,
    OLLAMA_HOST: `127.0.0.1:${port}`,
    OLLAMA_MODELS: join(ROOT, ".cache/ollama/models"),
    OLLAMA_NUM_PARALLEL: "1",
    OLLAMA_MAX_LOADED_MODELS: "2",
    OLLAMA_MAX_QUEUE: env.OLLAMA_MAX_QUEUE ?? "128",
    OLLAMA_KEEP_ALIVE: "-1",
    OLLAMA_NO_CLOUD: "1",
  };
}

export async function installNativeOllama(scope: ProcessScope): Promise<string> {
  if (process.platform !== "darwin" || process.arch !== "arm64") throw new Error("Native MLX Ollama requires macOS on Apple Silicon.");
  const target = join(ROOT, ".cache/tools/ollama", OLLAMA_VERSION);
  const executable = join(target, "ollama");
  if (!existsSync(executable)) {
    await mkdir(dirname(target), { recursive: true });
    const temporary = await mkdtemp(join(dirname(target), ".install-"));
    try {
      console.log(`Downloading verified Ollama ${OLLAMA_VERSION} for macOS (159 MB).`);
      const archive = join(temporary, "ollama.tgz");
      await download(`https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-darwin.tgz`, archive, scope.signal);
      if (await sha256(archive) !== OLLAMA_DARWIN_SHA256) throw new Error("Native Ollama archive failed SHA-256 verification.");
      await scope.run([command("tar"), "-xzf", archive, "-C", temporary]);
      await rm(archive);
      if (!existsSync(join(temporary, "ollama"))) throw new Error("Native Ollama archive is missing its executable.");
      await rename(temporary, target);
    } finally { await rm(temporary, { recursive: true, force: true }); }
  }
  await mkdir(join(ROOT, ".cache/ollama/models"), { recursive: true });
  return executable;
}

export async function verifyNativeOllama(origin: string, native: ManagedProcess, signal: AbortSignal): Promise<void> {
  await waitHTTP(`${origin}/api/version`, native, 30000, signal);
  const response = await fetch(`${origin}/api/version`, { signal: AbortSignal.any([signal, AbortSignal.timeout(3000)]), redirect: "error" });
  const version = await response.json() as { version?: string };
  if (!response.ok || version.version !== OLLAMA_VERSION) throw new Error(`Native Ollama must be version ${OLLAMA_VERSION}; remove only .cache/tools/ollama/${OLLAMA_VERSION} and retry to reinstall.`);
}

export async function withNativeOllama<T>(scope: ProcessScope, env: Environment, executable: string, work: (native: ManagedProcess) => Promise<T>): Promise<T> {
  const nativeScope = new ProcessScope();
  return await withCleanup(async () => {
    await requireFreePort("127.0.0.1", Number(env.LLM_OLLAMA_PORT));
    const native = nativeScope.start([executable, "serve"], { env, stopGraceMs: 30000 });
    await verifyNativeOllama(env.LLM_OLLAMA_URL!, native, scope.signal);
    return await Promise.race([
      work(native),
      native.exited.then(code => { throw new Error(`Native Ollama exited (${code}). See its output above.`); }),
    ]);
  }, async () => {
    await withCleanup(() => scope.close(), () => nativeScope.close());
  });
}
