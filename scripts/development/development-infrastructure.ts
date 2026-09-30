import { dirname, join } from "node:path";
import { compose, infraUp } from "./compose.ts";
import { installNativeOllama, nativeOllamaEnvironment, withNativeOllama } from "./native-ollama.ts";
import { ROOT, type Environment, type ManagedProcess, ProcessScope } from "../shared/runtime.ts";

export type OllamaRuntime = "cpu" | "cuda" | "rocm" | "mlx";

export function ollamaRuntime(env: Environment, platform = process.platform, arch = process.arch): OllamaRuntime {
  const runtime = env.OLLAMA_RUNTIME ?? "cpu";
  if (!["cpu", "cuda", "rocm", "mlx"].includes(runtime)) throw new Error("OLLAMA_RUNTIME must be cpu, cuda, rocm or mlx.");
  if (runtime === "mlx" && (platform !== "darwin" || arch !== "arm64")) throw new Error("OLLAMA_RUNTIME=mlx requires macOS on Apple Silicon. Use cpu, cuda or rocm on this host.");
  return runtime as OllamaRuntime;
}

export function developmentComposeOverrides(runtime: OllamaRuntime): string[] {
  return runtime === "cpu" ? [] : [join(ROOT, `compose.${runtime}.yaml`)];
}

export async function withDevelopmentInfrastructure<T>(scope: ProcessScope, env: Environment, work: (native?: ManagedProcess) => Promise<T>): Promise<T> {
  const runtime = ollamaRuntime(env);
  const overrides = developmentComposeOverrides(runtime);
  console.log(`Development Ollama runtime: ${runtime}`);
  if (runtime !== "mlx") {
    await infraUp(scope, env, overrides);
    return await work();
  }
  const nativeEnv = nativeOllamaEnvironment(env);
  const executable = await installNativeOllama(scope);
  await compose(scope, ["stop", "document-processor", "ollama"], env);
  const composeEnv = { ...env, DOMABAS_OLLAMA_CACHE: dirname(nativeEnv.OLLAMA_MODELS!) };
  return await withNativeOllama(scope, nativeEnv, executable, async native => {
    console.log("Native Ollama uses .cache/ollama/models. Choose an MLX model in Admin → Document processing to use the MLX engine; Nomic embeddings retain their pinned format.");
    try {
      await compose(scope, ["run", "--build", "--rm", "--no-deps", "--entrypoint", "curl", "document-processor", "--fail", "--silent", "--show-error", "--max-time", "5", `http://host.docker.internal:${nativeEnv.LLM_OLLAMA_PORT}/api/version`], composeEnv, undefined, overrides);
    } catch (cause) {
      throw new Error("MLX requires Docker to build the processor, mount .cache/ollama, and reach the host's loopback listener through host.docker.internal. See docs/development/compose.md and the error above.", { cause });
    }
    await infraUp(scope, composeEnv, overrides);
    scope.signal.throwIfAborted();
    return await work(native);
  });
}
