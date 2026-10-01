import { existsSync } from "node:fs";
import { mkdir, mkdtemp, open, rm, type FileHandle } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isIPv4 } from "node:net";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { setTimeout as delay } from "node:timers/promises";
import { install } from "./browser/browser-tools.ts";
import { nativeBin } from "../development/database.ts";
import { captureCompose, compose, infraUp } from "../development/compose.ts";
import { emailFixtureEnvironment, startEmailFixture } from "./fixtures/email-fixture.ts";
import { startLLMFixture } from "./fixtures/llm-fixture.ts";
import { startPaperlessFixture } from "./fixtures/paperless-fixture.ts";
import { ROOT, ProcessScope, binary, command, environment, required, requireFreePort, runCLI, waitHTTP, withCleanup } from "../shared/runtime.ts";
import { cleanupWorkflows, ownedExecutions } from "./workflow-cleanup.ts";

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
    "external-db": { type: "boolean", default: false }, "external-services": { type: "boolean", default: false }, help: { type: "boolean", short: "h" },
  } });
  if (values.help) { console.log("Usage: bun scripts/testing/e2e.ts [--external-services] (--external-db remains an alias)"); return; }
  const go = command("go"), flutter = command("flutter");
  let env = environment();
  const host = hostValue(env.E2E_HOST);
  const apiPort = portValue(env.E2E_API_PORT, 18080), webPort = portValue(env.E2E_WEB_PORT, 7357), driverPort = portValue(env.E2E_DRIVER_PORT, 4444);
  for (const port of [apiPort, webPort]) await requireFreePort(host, port);
  await requireFreePort("127.0.0.1", driverPort);
  const external = values["external-db"] || values["external-services"];
  if (!external) await infraUp(scope, env);
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
  const query = async (queryScope: ProcessScope, statement: string): Promise<string> => {
    const args = ["--dbname", psql ? databaseURL : containerURL!, "-X", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", statement];
    const result = psql ? await queryScope.capture([psql, ...args], { env: sqlEnv }) : await captureCompose(queryScope, ["exec", "-T", "postgres", "psql", ...args], sqlEnv);
    if (result.code) throw new Error("Cannot read the disposable workflow cleanup manifest.");
    return result.stdout.trim();
  };
  const installedBrowser = await install(scope.signal);
  const chrome = env.CHROME_EXECUTABLE || installedBrowser.chrome;
  const driver = installedBrowser.driver;
  const schema = `e2e_${crypto.randomUUID().replaceAll("-", "")}`;
  env.CHROME_EXECUTABLE = chrome;
  env.DATABASE_URL = schemaURL(databaseURL, schema);
  env.HTTP_ADDR = `${host}:${apiPort}`;
  env.CORS_ORIGINS = `http://localhost:${webPort},http://127.0.0.1:${webPort},http://${host}:${webPort}`;
  env.TEMPORAL_TASK_QUEUE = `domabas-${schema}`;
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
        driverLog = await open(join(logs, "chromedriver.log"), "w");
        const server = scope.start([executable], { cwd: join(ROOT, "backend"), env, stdout: serverLog.fd, stderr: serverLog.fd, stopGraceMs: 60000 });
        await waitHTTP(`${apiURL}/readyz`, server, 90000, scope.signal);
        const browserDriver = scope.start([driver, `--port=${driverPort}`], { env, stdout: driverLog.fd, stderr: driverLog.fd });
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
        const tables = JSON.parse(await query(cleanup, `SELECT json_build_object('paperless',to_regclass('"${schema}".paperless_runs') IS NOT NULL,'email',to_regclass('"${schema}".email_executions') IS NOT NULL,'documents',to_regclass('"${schema}".document_processing_executions') IS NOT NULL,'ai',to_regclass('"${schema}".document_ai_jobs') IS NOT NULL,'chat',to_regclass('"${schema}".chat_turns') IS NOT NULL,'thumbnails',to_regclass('"${schema}".document_thumbnail_jobs') IS NOT NULL)`)) as { paperless: boolean; email: boolean; documents: boolean; ai: boolean; chat: boolean; thumbnails: boolean };
        const selections = [];
        if (tables.paperless) selections.push(`SELECT 'domabas-paperless-'||id::text AS "workflowId",'' AS "runId",task_queue AS "taskQueue",'domabas.PaperlessImport.v1' AS "workflowType" FROM "${schema}".paperless_runs WHERE NOT execution_closed`);
        if (tables.email) selections.push(`SELECT workflow_id AS "workflowId",COALESCE(workflow_run_id,'') AS "runId",task_queue AS "taskQueue",'domabas.EmailPoll.v1' AS "workflowType" FROM "${schema}".email_executions WHERE closed_at IS NULL`);
        if (tables.documents) selections.push(`SELECT workflow_id AS "workflowId",run_id AS "runId",task_queue AS "taskQueue",CASE WHEN split_pipeline THEN 'domabas.DocumentIngestion.v2' ELSE 'domabas.DocumentIngestion.v1' END AS "workflowType" FROM "${schema}".document_processing_executions WHERE closed_at IS NULL`);
        if (tables.ai) selections.push(`SELECT workflow_id AS "workflowId",run_id AS "runId",task_queue AS "taskQueue",'domabas.DocumentAI.v1' AS "workflowType" FROM "${schema}".document_ai_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL`);
        if (tables.thumbnails) selections.push(`SELECT workflow_id AS "workflowId",run_id AS "runId",task_queue AS "taskQueue",'domabas.DocumentThumbnail.v1' AS "workflowType" FROM "${schema}".document_thumbnail_jobs WHERE admitted_at IS NOT NULL AND closed_at IS NULL`);
        if (tables.chat) selections.push(`SELECT workflow_id AS "workflowId",run_id AS "runId",task_queue AS "taskQueue",'domabas.ChatTurn.v1' AS "workflowType" FROM "${schema}".chat_turns WHERE admitted_at IS NOT NULL AND NOT execution_closed`);
        if (selections.length) {
          const manifest = JSON.parse(await query(cleanup, `SELECT COALESCE(json_agg(owned),'[]'::json) FROM (${selections.join(" UNION ALL ")}) owned`));
          await cleanupWorkflows(cleanup, env, ownedExecutions(manifest, env.TEMPORAL_TASK_QUEUE!));
        }
        await sql(cleanup, `DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      }
      finally {
        try { await cleanup.close(); }
        finally { await rm(storageRoot, { recursive: true, force: true }); }
      }
    },
  );
});
