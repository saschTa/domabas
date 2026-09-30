import { join } from "node:path";
import { parseArgs } from "node:util";
import { withDevelopmentInfrastructure } from "./development-infrastructure.ts";
import { ROOT, command, environment, requireFreePort, runCLI, waitHTTP, withCleanup } from "../shared/runtime.ts";

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: {
    device: { type: "string", default: "web-server" },
    "external-db": { type: "boolean", default: false },
    "external-services": { type: "boolean", default: false },
    help: { type: "boolean", short: "h" },
  } });
  if (values.help) { console.log("Usage: bun scripts/development/dev.ts [--device DEVICE] [--external-services] (--external-db remains an alias)"); return; }
  const go = command("go"), flutter = command("flutter");
  const env = environment();
  const address = /^(.*):(\d+)$/.exec(env.HTTP_ADDR ?? "127.0.0.1:8080");
  if (!address) throw new Error("HTTP_ADDR must contain a host and port.");
  const host = address[1]!.replace(/^\[|\]$/g, "");
  const port = Number(address[2]);
  await requireFreePort(host, port);
  const readyHost = ["", "0.0.0.0", "::"].includes(host) ? "127.0.0.1" : host;
  const readiness = `http://${readyHost.includes(":") ? `[${readyHost}]` : readyHost}:${port}/readyz`;
  const web = ["web-server", "chrome", "edge"].includes(values.device);
  if (web) await requireFreePort("127.0.0.1", 7357);
  const startDevelopment = async () => {
    await scope.run([go, "mod", "download"], { cwd: join(ROOT, "backend"), env });
    await scope.run([flutter, "pub", "get", "--enforce-lockfile"], { cwd: join(ROOT, "frontend"), env });
    const backend = scope.start([go, "tool", "air", "-c", ".air.toml"], { cwd: join(ROOT, "backend"), env: { ...process.env }, stopGraceMs: 60000 });
    return await withCleanup(async () => {
      await waitHTTP(readiness, backend, 180000, scope.signal);
      const args = [flutter, "run", "-d", values.device, `--dart-define=API_BASE_URL=${env.API_BASE_URL ?? readiness.replace(/\/readyz$/, "")}`];
      if (web) args.push("--web-hostname=127.0.0.1", "--web-port=7357");
      console.log("\nAPI ready. Open http://127.0.0.1:7357 for web; press r to hot reload, R to restart, q to quit.\n");
      const frontend = scope.start(args, { cwd: join(ROOT, "frontend"), env, stdin: "inherit" });
      const result = await Promise.race([
        frontend.exited.then(code => ({ source: "frontend", code })),
        backend.exited.then(code => ({ source: "backend", code })),
      ]);
      scope.signal.throwIfAborted();
      if (result.source === "backend") throw new Error(`Backend watcher exited (${result.code}).`);
      return result.code;
    }, async () => {
      await scope.close();
      console.log("Application processes stopped. Docker infrastructure and caches are retained; stop containers with task infra:down.");
    });
  };
  if (values["external-db"] || values["external-services"]) return await startDevelopment();
  return await withDevelopmentInfrastructure(scope, env, startDevelopment);
});
