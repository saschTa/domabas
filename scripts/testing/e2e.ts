import { existsSync } from "node:fs";
import { mkdir, mkdtemp, open, rm, type FileHandle } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isIPv4 } from "node:net";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { setTimeout as delay } from "node:timers/promises";
import { install } from "./browser/browser-tools.ts";
import { nativeBin } from "../development/database.ts";
import { compose, infraUp } from "../development/compose.ts";
import { emailFixtureEnvironment, startEmailFixture } from "./fixtures/email-fixture.ts";
import { startLLMFixture } from "./fixtures/llm-fixture.ts";
import { startPaperlessFixture } from "./fixtures/paperless-fixture.ts";
import { ROOT, ProcessScope, binary, command, environment, required, requireFreePort, runCLI, waitHTTP, withCleanup } from "../shared/runtime.ts";
import { inspectionArguments, prepareInspection, waitForInspection } from "./e2e-inspection.ts";

async function streamBrowserLogs(port: number, signal: AbortSignal, secrets: string[]): Promise<void> {
  while (!signal.aborted) {
    try {
      const requestSignal = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
      const base = `http://127.0.0.1:${port}`;
      const response = await fetch(`${base}/sessions`, { signal: requestSignal });
      if (response.ok) {
        const sessions = await response.json() as { value: { id: string }[] };
        for (const session of sessions.value) {
          const logs = await fetch(`${base}/session/${encodeURIComponent(session.id)}/log`, {
            method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ type: "browser" }), signal: requestSignal,
          });
          if (!logs.ok) continue;
          const entries = await logs.json() as { value: { level: string; message: string }[] };
          for (const entry of entries.value) {
            let message = entry.message;
            for (const secret of secrets) if (secret) message = message.replaceAll(secret, "[redacted]");
            console.log(`[browser ${entry.level}] ${message.slice(0, 8000)}`);
          }
        }
      }
    } catch (error) {
      if (!signal.aborted) console.error(`Browser diagnostics unavailable: ${error instanceof Error ? error.name : "request failed"}.`);
    }
    try { await delay(5000, undefined, { signal }); }
    catch { break; }
  }
}

async function psqlCommand(scope: ProcessScope): Promise<string | undefined> {
  const path = Bun.which("psql");
  if (path) return path;
  try { return join(await nativeBin(scope), binary("psql")); }
  catch { scope.signal.throwIfAborted(); }
  for (const path of ["/opt/homebrew/opt/libpq/bin/psql", "/usr/local/opt/libpq/bin/psql"]) {
    if (existsSync(path)) return path;
  }
  return undefined;
}

export function schemaURL(databaseURL: string, schema: string): string {
  const url = new URL(databaseURL);
  url.searchParams.set("search_path", schema);
  return url.toString();
}

export function portValue(text: string | undefined, fallback: number): number {
  const value = text === undefined ? fallback : Number(text);
  if (!Number.isInteger(value) || value < 1 || value > 65535) throw new Error("E2E port must be an integer from 1 to 65535.");
  return value;
}

export function hostValue(text: string | undefined): string {
  const host = text ?? "127.0.0.1";
  if (!isIPv4(host) || host === "0.0.0.0") throw new Error("E2E_HOST must be a reachable IPv4 address on this computer.");
  return host;
}

export function composeDatabaseURL(databaseURL: string): string {
  const url = new URL(databaseURL);
  if (!["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)) {
    throw new Error("Install psql for tests against a remote database.");
  }
  url.hostname = "127.0.0.1";
  url.port = "5432";
  return url.toString();
}

export async function withTemporarySchema(
  create: () => Promise<void>, work: () => Promise<void>, drop: () => Promise<void>,
  reportCleanup: (error: unknown) => void = error => console.error(`Schema cleanup failed: ${error instanceof Error ? error.message : String(error)}`),
): Promise<void> {
  await withCleanup(async () => { await create(); await work(); }, drop, reportCleanup);
}

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: {
    inspect: { type: "boolean", default: false }, "external-db": { type: "boolean", default: false }, "external-services": { type: "boolean", default: false }, help: { type: "boolean", short: "h" },
  } });
  if (values.help) { console.log("Usage: bun scripts/testing/e2e.ts [--external-services] [--inspect] (--inspect requires external services; --external-db remains an alias)"); return; }
  const go = command("go"), flutter = command("flutter");
  let env = environment();
  const host = hostValue(env.E2E_HOST);
  const apiPort = portValue(env.E2E_API_PORT, 18080), webPort = portValue(env.E2E_WEB_PORT, 7357), driverPort = portValue(env.E2E_DRIVER_PORT, 4444);
  for (const port of [apiPort, webPort]) await requireFreePort(host, port);
  if (!values.inspect) await requireFreePort("127.0.0.1", driverPort);
  const external = values["external-db"] || values["external-services"];
  if (values.inspect && !external) throw new Error("Inspection requires --external-services pointing to the prepared disposable stack.");
  if (!external) await infraUp(scope, { ...env, EMBEDDING_DOWNLOAD_ALLOWED: "false" });
  const databaseURL = env.TEST_DATABASE_URL || required(env, "DATABASE_URL");
  const psql = await psqlCommand(scope);
  if (!psql && external) throw new Error("Install the PostgreSQL client (psql) for tests against an external database.");
  if (!psql && env.TEST_DATABASE_URL && env.TEST_DATABASE_URL !== env.DATABASE_URL) {
    throw new Error("Install psql when TEST_DATABASE_URL differs from the managed development database.");
  }
  const containerURL = psql ? undefined : composeDatabaseURL(databaseURL);
  const sqlEnv = { ...env };
  const sql = async (sqlScope: ProcessScope, statement: string): Promise<void> => {
    if (psql) {
      await sqlScope.run([psql, "--dbname", databaseURL, "-X", "-v", "ON_ERROR_STOP=1", "-q", "-c", statement], { env: sqlEnv });
    } else {
      await compose(sqlScope, ["exec", "-T", "postgres", "psql", "--dbname", containerURL!, "-X", "-v", "ON_ERROR_STOP=1", "-q", "-c", statement], sqlEnv);
    }
  };
  const installedBrowser = values.inspect ? undefined : await install(scope.signal);
  const chrome = env.CHROME_EXECUTABLE || installedBrowser?.chrome;
  const driver = installedBrowser?.driver;
  const schema = `e2e_${crypto.randomUUID().replaceAll("-", "")}`;
  env.CHROME_EXECUTABLE = chrome;
  env.DATABASE_URL = schemaURL(databaseURL, schema);
  env.HTTP_ADDR = `${host}:${apiPort}`;
  env.CORS_ORIGINS = `http://localhost:${webPort},http://127.0.0.1:${webPort},http://${host}:${webPort}`;
  const apiURL = `http://${host}:${apiPort}`;
  const executable = join(ROOT, ".tools", binary("domabas-e2e"));
  await scope.run([go, "build", "-o", executable, "./cmd/server"], { cwd: join(ROOT, "backend"), env });
  await scope.run([flutter, "pub", "get", "--enforce-lockfile"], { cwd: join(ROOT, "frontend"), env });
  const logs = join(ROOT, ".logs");
  await mkdir(logs, { recursive: true });
  const storageRoot = await mkdtemp(join(tmpdir(), "domabas-browser-"));
  env.DOCUMENT_INGESTION_ROOT = join(storageRoot, "ingestion");
  env.DOCUMENT_STORAGE_ROOT = join(storageRoot, "documents");
  const paperless = await startPaperlessFixture();
  const llm = startLLMFixture();
  env.LLM_CREDENTIAL_KEY = "";
  env.LLM_CREDENTIAL_KEY_FILE = join(storageRoot, "secrets", "llm.key");
  delete env.PAPERLESS_SERVERS;
  env.PAPERLESS_CREDENTIAL_KEY = "";
  env.PAPERLESS_CREDENTIAL_KEY_FILE = join(storageRoot, "secrets", "paperless.key");
  await withTemporarySchema(
    () => sql(scope, `CREATE SCHEMA "${schema}"`),
    async () => withCleanup(async () => {
      const fixtureDirectory = join(storageRoot, "imap");
      await mkdir(fixtureDirectory, { recursive: true, mode: 0o700 });
      const fixture = await startEmailFixture(scope, env, fixtureDirectory);
      env = emailFixtureEnvironment(env, fixture);
      const fixtureDefines = join(fixtureDirectory, "flutter-defines.json");
      await Bun.write(fixtureDefines, JSON.stringify({
        EMAIL_FIXTURE_HOST: fixture.host, EMAIL_FIXTURE_PORT: String(fixture.port),
        EMAIL_FIXTURE_USERNAME: fixture.username, EMAIL_FIXTURE_PASSWORD: fixture.password,
        EMAIL_FIXTURE_MAILBOX: fixture.mailbox,
        LLM_FIXTURE_URL: llm.url, LLM_FIXTURE_KEY: llm.key,
        PAPERLESS_FIXTURE_TOKEN: paperless.token,
        PAPERLESS_FIXTURE_URL: paperless.url,
      }));
      const serverLog = await open(join(logs, "e2e-api.log"), "w");
      let driverLog: FileHandle | undefined;
      await withCleanup(async () => {
        const server = scope.start([executable], { cwd: join(ROOT, "backend"), env, stdout: serverLog.fd, stderr: serverLog.fd, stopGraceMs: 60000 });
        await waitHTTP(`${apiURL}/readyz`, server, 90000, scope.signal);
        if (values.inspect) {
          const webLog = await open(join(logs, "e2e-inspection-web.log"), "w");
          try {
            const app = scope.start(inspectionArguments(flutter, host, webPort, apiURL), {
              cwd: join(ROOT, "frontend"), env, stdout: webLog.fd, stderr: webLog.fd,
            });
            const webURL = `http://${host}:${webPort}`;
            await waitHTTP(webURL, app, 180000, scope.signal);
            const inspection = await prepareInspection(storageRoot, apiURL, webURL, scope.signal, {
              email: { host: fixture.host, port: fixture.port, username: fixture.username, password: fixture.password, mailbox: fixture.mailbox },
              llm: { url: llm.url, key: llm.key }, paperless: { url: paperless.url, token: paperless.token },
            });
            console.log(`Disposable production application ready at ${webURL}. Private credentials: ${inspection.manifest}`);
            console.log(`Create ${inspection.stopFile} to finish normally, or press Ctrl+C. Owned processes, workflows, schema and files are cleaned up afterward.`);
            await waitForInspection(inspection.stopFile, scope.signal, () => app.exitCode ?? server.exitCode);
          } finally {
            try { await scope.close(); } finally { await webLog.close(); }
          }
          return;
        }
        driverLog = await open(join(logs, "chromedriver.log"), "w");
        const browserDriver = scope.start([driver!, `--port=${driverPort}`], { env, stdout: driverLog.fd, stderr: driverLog.fd });
        await waitHTTP(`http://127.0.0.1:${driverPort}/status`, browserDriver, 90000, scope.signal);
        const diagnosticsAbort = new AbortController();
        const diagnostics = streamBrowserLogs(driverPort, AbortSignal.any([scope.signal, diagnosticsAbort.signal]), [fixture.password, llm.key, paperless.token]);
        try {
          const test = scope.start([flutter, "drive", "--driver=test_driver/integration_test.dart", "--target=integration_test/app_test.dart",
            "-d", "web-server", "--browser-name=chrome", `--chrome-binary=${chrome}`, "--headless", "--web-browser-flag=--disable-dev-shm-usage",
            `--web-hostname=${host}`, `--web-port=${webPort}`, `--driver-port=${driverPort}`, `--dart-define=API_BASE_URL=${apiURL}`, `--dart-define-from-file=${fixtureDefines}`],
            { cwd: join(ROOT, "frontend"), env });
          const result = await test.wait(600000);
          scope.signal.throwIfAborted();
          if (result) throw new Error(`Flutter E2E failed (${result}); see .logs/e2e-api.log and .logs/chromedriver.log.`);
        } finally {
          diagnosticsAbort.abort();
          await diagnostics;
        }
      }, async () => {
        try { await scope.close(); }
        finally { await Promise.all([serverLog.close(), driverLog?.close()]); }
      });
    }, () => scope.close()),
    async () => {
      llm.stop();
      await paperless.stop();
      const cleanup = new ProcessScope();
      try {
        await sql(cleanup, `DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      }
      finally {
        try { await cleanup.close(); }
        finally { await rm(storageRoot, { recursive: true, force: true }); }
      }
    },
  );
});
