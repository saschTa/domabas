import { SQL } from "bun";

function value(name: string): string {
  const result = process.env[name];
  if (!result) throw new Error(`Required environment variable ${name} is missing.`);
  return result;
}
function identifier(name: string): string {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(name)) throw new Error("Database and role names must be lowercase SQL identifiers (at most 63 characters).");
  return `"${name}"`;
}
const literal = (text: string): string => `'${text.replaceAll("'", "''")}'`;
const controller = new AbortController();
const children = new Set<ReturnType<typeof Bun.spawn>>();
for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => {
  controller.abort(new Error("Initialization interrupted."));
  for (const child of children) child.kill();
});
async function execute(args: string[], capture = false): Promise<{ code: number; output: string }> {
  controller.signal.throwIfAborted();
  const child = Bun.spawn(args, { env: process.env, stdout: capture ? "pipe" : "inherit", stderr: capture ? "pipe" : "inherit" });
  children.add(child);
  const timer = setTimeout(() => child.kill(), 60000);
  try {
    const [code, stdout, stderr] = await Promise.all([
      child.exited,
      capture ? new Response(child.stdout as ReadableStream).text() : "",
      capture ? new Response(child.stderr as ReadableStream).text() : "",
    ]);
    controller.signal.throwIfAborted();
    if (code && !capture) throw new Error(`${args[0]} failed with exit ${code}.`);
    return { code, output: stdout + stderr };
  } finally { clearTimeout(timer); children.delete(child); }
}

async function databases(): Promise<void> {
  const url = new URL("postgres://postgres:5432/postgres");
  url.username = value("POSTGRES_ADMIN_USER"); url.password = value("POSTGRES_ADMIN_PASSWORD");
  const sql = new SQL(url.toString(), { max: 1, connectionTimeout: 10, idleTimeout: 1 });
  try {
    const roles = [value("POSTGRES_USER"), value("TEMPORAL_DB_USER")];
    if (new Set([value("POSTGRES_ADMIN_USER"), ...roles]).size !== 3) throw new Error("Administrative, application and Temporal database roles must differ.");
    for (const [role, password] of [[roles[0]!, value("POSTGRES_PASSWORD")], [roles[1]!, value("TEMPORAL_DB_PASSWORD")]]) {
      const name = identifier(role!);
      const existing = await sql`SELECT 1 FROM pg_roles WHERE rolname = ${role}`;
      if (!existing.length) await sql.unsafe(`CREATE ROLE ${name} LOGIN PASSWORD ${literal(password!)}`);
      else await sql.unsafe(`ALTER ROLE ${name} LOGIN PASSWORD ${literal(password!)}`);
    }
    for (const [database, role] of [[value("POSTGRES_DB"), roles[0]!], [value("TEMPORAL_DB"), roles[1]!], [value("TEMPORAL_VISIBILITY_DB"), roles[1]!]]) {
      const dbName = identifier(database!), roleName = identifier(role!);
      const existing = await sql`SELECT 1 FROM pg_database WHERE datname = ${database}`;
      if (!existing.length) await sql.unsafe(`CREATE DATABASE ${dbName} OWNER ${roleName}`);
    }
    const applicationURL = new URL(url);
    applicationURL.pathname = `/${value("POSTGRES_DB")}`;
    const application = new SQL(applicationURL.toString(), { max: 1, connectionTimeout: 10, idleTimeout: 1 });
    try {
      await application.unsafe("CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public VERSION '0.8.6'");
      const extension = await application`SELECT e.extversion, n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector'`;
      if (extension[0]?.extversion !== "0.8.6" || extension[0]?.nspname !== "public") throw new Error("Domabas requires pgvector 0.8.6 in the public schema.");
    } finally { await application.close({ timeout: 5 }); }
    console.log("Application and Temporal databases/roles and pgvector are provisioned.");
  } finally { await sql.close({ timeout: 5 }); }
}

async function schemas(): Promise<void> {
  for (const [database, kind] of [[value("TEMPORAL_DB"), "temporal"], [value("TEMPORAL_VISIBILITY_DB"), "visibility"]]) {
    const base = ["temporal-sql-tool", "--plugin", "postgres12", "--ep", "postgres", "-p", "5432", "-u", value("TEMPORAL_DB_USER"), "--db", database!];
    await execute([...base, "setup-schema", "-v", "0.0"]);
    await execute([...base, "update-schema", "-d", `/etc/temporal/schema/postgresql/v12/${kind}/versioned`]);
  }
}

async function namespace(): Promise<void> {
  const base = ["temporal", "--address", value("TEMPORAL_ADDRESS"), "--namespace", value("TEMPORAL_NAMESPACE")];
  const healthDeadline = Date.now() + 60000;
  for (;;) {
    const health = await execute([...base, "--command-timeout", "5s", "operator", "cluster", "health"], true);
    if (!health.code) break;
    if (Date.now() >= healthDeadline) throw new Error(`Temporal cluster is unavailable: ${health.output}`);
    controller.signal.throwIfAborted();
    await Bun.sleep(500);
  }
  const described = await execute([...base, "operator", "namespace", "describe"], true);
  if (described.code) {
    if (!/namespace[^\n]*(not found|does not exist)/i.test(described.output)) throw new Error(described.output);
    const created = await execute([...base, "operator", "namespace", "create", "--retention", "72h"], true);
    if (created.code && !/namespace[^\n]*already exists/i.test(created.output)) throw new Error(created.output);
  }
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const checked = await execute([...base, "operator", "namespace", "describe"], true);
    if (!checked.code) { console.log("Temporal namespace is ready."); return; }
    if (!/namespace[^\n]*(not found|does not exist)/i.test(checked.output)) throw new Error(checked.output);
    await Bun.sleep(500);
  }
  throw new Error("Timed out waiting for Temporal namespace registration.");
}

try {
  const mode = Bun.argv[2];
  if (mode === "databases") await databases();
  else if (mode === "schemas") await schemas();
  else if (mode === "namespace") await namespace();
  else throw new Error("Expected databases, schemas or namespace initialization mode.");
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  for (const child of children) child.kill();
}
