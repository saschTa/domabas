import { mkdir } from "node:fs/promises";
import { createServer } from "node:net";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { captureCompose, compose, infraUp, publishedPort } from "../development/compose.ts";
import { dockerTestHost } from "./ci-network.ts";
import { ROOT, ProcessScope, command, environment, required, runCLI, withCleanup } from "../shared/runtime.ts";

export function ciSuite(value = "units"): "units" | "full" {
  if (value !== "units" && value !== "full") throw new Error("CI suite must be units or full.");
  return value;
}

export async function runCITests(suite: ReturnType<typeof ciSuite>, run: (args: string[], cwd?: string) => Promise<void>): Promise<void> {
  if (suite === "units") {
    await run(["go", "test", "-race", "-count=1", "./..."], join(ROOT, "backend"));
  } else {
    await run(["bun", "--no-env-file", "scripts/testing/backend-database-tests.ts", "integration", "--include-units"]);
    await run(["bun", "--no-env-file", "scripts/testing/backend-database-tests.ts", "temporal"]);
  }
  await run(["flutter", "test", "--no-pub"], join(ROOT, "frontend"));
  if (suite === "full") {
    await run(["bun", "--no-env-file", "scripts/testing/browser/browser-tests.ts", "--skip-pub"]);
    await run(["bun", "--no-env-file", "scripts/testing/backend-database-tests.ts", "e2e"]);
    await run(["bun", "--no-env-file", "scripts/testing/e2e.ts", "--external-services"]);
  }
}

export async function runCIAnalysis(suite: ReturnType<typeof ciSuite>, run: (args: string[], cwd?: string) => Promise<void>, checkGoFormatting: () => Promise<void>): Promise<void> {
  if (suite !== "full") return;
  await run(["bun", "--no-env-file", "run", "typecheck"]);
  await run(["bun", "--no-env-file", "scripts/generation/check-generated.ts"]);
  await run(["bun", "--no-env-file", "scripts/generation/generate-database.ts", "--check"]);
  await checkGoFormatting();
  await run(["go", "vet", "./..."], join(ROOT, "backend"));
  await run(["dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test", "integration_test", "test_driver"], join(ROOT, "frontend"));
  await run(["flutter", "analyze", "--no-pub", "--fatal-infos"], join(ROOT, "frontend"));
}

async function freePort(): Promise<string> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close();
        reject(new Error("Could not allocate a test port."));
        return;
      }
      server.close(error => error ? reject(error) : resolve(String(address.port)));
    });
  });
}

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: { help: { type: "boolean", short: "h" }, suite: { type: "string", default: "units" }, builds: { type: "boolean", default: false } } });
  if (values.help) { console.log("Usage: bun scripts/ci/ci.ts [--suite=units|full] [--builds] (full requires Linux, Docker and documented prerequisites)"); return; }
  const suite = ciSuite(values.suite);
  if (suite === "units" && values.builds) throw new Error("The units suite only runs tests; --builds requires the full suite.");
  const bun = command("bun"), go = command("go"), flutter = command("flutter");
  const env = environment({ ...process.env, CI: "true" });
  const backend = join(ROOT, "backend"), frontend = join(ROOT, "frontend");
  const run = async (args: string[], cwd = ROOT): Promise<void> => {
    const started = performance.now();
    const label = args.slice(0, 5).join(" ");
    console.log(`Starting ${label}`);
    await scope.run([command(args[0]!), ...args.slice(1)], { cwd, env });
    console.log(`Finished ${label} in ${((performance.now() - started) / 1000).toFixed(1)}s`);
  };
  console.log(`Running ${suite} CI suite.`);
  await run([bun, "--no-env-file", "test", "scripts"]);
  await run([go, "mod", "download"], backend);
  await run([flutter, "pub", "get", "--enforce-lockfile"], frontend);
  if (suite === "units") {
    await runCITests(suite, run);
    return;
  }
  if (process.platform !== "linux") throw new Error("The complete Linux CI suite needs Linux; use task check/test tasks locally.");
  command("docker");
  command("java");
  const dockerHost = await dockerTestHost(scope);
  const project = `domabas-ci-${crypto.randomUUID().replaceAll("-", "")}`;
  Object.assign(env, { COMPOSE_PROJECT_NAME: project, COMPOSE_PROFILES: "", BIND_ADDRESS: dockerHost, PRIVATE_BIND_ADDRESS: dockerHost, POSTGRES_PORT: "0", TEMPORAL_PORT: "0", WEB_PORT: "0", TEMPORAL_UI_PORT: "0", DOCUMENT_PROCESSOR_PORT: "0", LLM_OLLAMA_PORT: "0" });
  await withCleanup(async () => {
    await infraUp(scope, env);
    const database = new URL(`postgres://${dockerHost}/domabas?sslmode=disable`);
    database.username = required(env, "POSTGRES_USER");
    database.password = required(env, "POSTGRES_PASSWORD");
    database.pathname = `/${required(env, "POSTGRES_DB")}`;
    database.port = String(await publishedPort(scope, "postgres", 5432, env));
    env.DATABASE_URL = env.TEST_DATABASE_URL = database.toString();
    env.TEMPORAL_ADDRESS = `${dockerHost}:${await publishedPort(scope, "temporal", 7233, env)}`;
    env.TEMPORAL_UI_URL = `http://${dockerHost}:${await publishedPort(scope, "temporal-ui", 8080, env)}`;
    env.DOCUMENT_PROCESSOR_URL = `http://${dockerHost}:${await publishedPort(scope, "document-processor", 8091, env)}`;
    env.LLM_OLLAMA_URL = `http://${dockerHost}:${await publishedPort(scope, "ollama", 11434, env)}`;
    const ports = new Set<string>();
    for (const setting of ["E2E_API_PORT", "E2E_WEB_PORT", "E2E_DRIVER_PORT"]) {
      let port: string;
      do { port = await freePort(); } while (ports.has(port));
      ports.add(port);
      env[setting] = port;
    }
    await runCIAnalysis(suite, run, async () => {
      const formatting = await scope.capture([command("gofmt"), "-l", "."], { cwd: backend, env });
      if (formatting.code || formatting.stdout.trim()) throw new Error(`Go formatting differs:\n${formatting.stdout}`);
    });
    await runCITests(suite, run);
    if (values.builds) {
      await run([go, "build", "-o", "tmp/server", "./cmd/server"], backend);
      await run([flutter, "build", "web", "--release", "--no-web-resources-cdn"], frontend);
      await run([flutter, "build", "linux", "--release"], frontend);
    }
  }, async () => {
    const cleanup = new ProcessScope();
    try {
      await mkdir(join(ROOT, ".logs"), { recursive: true });
      const logs = await captureCompose(cleanup, ["logs", "--no-color"], env);
      await Bun.write(join(ROOT, ".logs/ci-compose.log"), logs.stdout + logs.stderr);
    } finally {
      try { await compose(cleanup, ["down", "--volumes", "--remove-orphans"], env, 120000); }
      finally { await cleanup.close(); }
    }
  });
}, { timeoutMs: 25 * 60 * 1000 });
