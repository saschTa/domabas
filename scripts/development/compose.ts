import { parseArgs } from "node:util";
import { existsSync } from "node:fs";
import { ROOT, type Environment, ProcessScope, command, environment, runCLI } from "../shared/runtime.ts";

export function composeArguments(args: readonly string[], overrides: readonly string[] = []): string[] {
  return [command("docker"), "compose", "--project-directory", ROOT, "--file", `${ROOT}/compose.yaml`, ...overrides.flatMap(file => ["--file", file]), "--env-file", `${ROOT}/backend/.env`, ...args];
}
export async function compose(scope: ProcessScope, args: readonly string[], env: Environment = environment(), timeoutMs?: number, overrides: readonly string[] = []): Promise<void> {
  await scope.run(composeArguments(args, overrides), { env }, timeoutMs);
}
export async function captureCompose(scope: ProcessScope, args: readonly string[], env: Environment = environment(), timeoutMs = 120000): Promise<{ code: number; stdout: string; stderr: string }> {
  return await scope.capture(composeArguments(args), { env }, timeoutMs);
}
export async function publishedPort(scope: ProcessScope, service: string, containerPort: number, env: Environment = environment()): Promise<number> {
  const result = await captureCompose(scope, ["port", service, String(containerPort)], env);
  const port = Number(/:(\d+)\s*$/.exec(result.stdout)?.[1]);
  if (result.code || !Number.isInteger(port) || port < 1 || port > 65535) throw new Error(`Cannot resolve the published ${service} port.`);
  return port;
}
export async function infraUp(scope: ProcessScope, env: Environment = environment(), overrides: readonly string[] = []): Promise<void> {
  try { await compose(scope, ["up", "--build", "--wait", "--wait-timeout", "900", "temporal", "document-processor"], env, undefined, overrides); }
  catch (error) {
    if (existsSync(`${ROOT}/.cache/postgres/postmaster.pid`)) console.error(`A native PostgreSQL cluster may occupy the managed port. Stop it with pg_ctl -D "${ROOT}/.cache/postgres" -m fast -w stop, or use --external-services. Existing native data has not been modified.`);
    throw error;
  }
  await compose(scope, ["run", "--build", "--rm", "--no-deps", "temporal-init"], env, undefined, overrides);
  await compose(scope, ["up", "--no-deps", "--wait", "--wait-timeout", "90", "temporal-ui"], env, undefined, overrides);
}
export async function infraDown(scope: ProcessScope, env: Environment = environment()): Promise<void> {
  await compose(scope, ["stop", "document-processor", "ollama", "temporal-ui", "temporal-init", "temporal", "temporal-schema", "database-init", "postgres"], env);
}

if (import.meta.main) await runCLI(async scope => {
  const { positionals, values } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true, options: { help: { type: "boolean", short: "h" }, "docker-only": { type: "boolean", default: false } } });
  if (values.help) { console.log("Usage: bun scripts/development/compose.ts <infra-up|infra-down|up|down> [--docker-only (infra-up test baseline)]"); return; }
  if (positionals.length !== 1) throw new Error("Expected one Compose operation: infra-up, infra-down, up or down.");
  if (values["docker-only"] && positionals[0] !== "infra-up") throw new Error("--docker-only is only supported with infra-up.");
  switch (positionals[0]) {
    case "infra-up": {
      if (values["docker-only"]) { await infraUp(scope); break; }
      const { withDevelopmentInfrastructure } = await import("./development-infrastructure.ts");
      await withDevelopmentInfrastructure(scope, environment(), async native => {
        if (native) {
          console.log("MLX infrastructure ready. Keep this terminal open; Ctrl+C stops native Ollama. Docker infrastructure and all caches are retained.");
          scope.signal.throwIfAborted();
          await new Promise<void>((resolve) => scope.signal.addEventListener("abort", () => resolve(), { once: true }));
        }
      });
      break;
    }
    case "infra-down": await infraDown(scope); break;
    case "up": await compose(scope, ["up", "--build", "--wait", "--wait-timeout", "900"]); break;
    case "down": await compose(scope, ["down"]); break;
    default: throw new Error("Expected infra-up, infra-down, up or down.");
  }
});
