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
async function databases(): Promise<void> {
  const url = new URL("postgres://postgres:5432/postgres");
  url.username = value("POSTGRES_ADMIN_USER"); url.password = value("POSTGRES_ADMIN_PASSWORD");
  const sql = new SQL(url.toString(), { max: 1, connectionTimeout: 10, idleTimeout: 1 });
  try {
    const role = value("POSTGRES_USER"), password = value("POSTGRES_PASSWORD");
    if (role === value("POSTGRES_ADMIN_USER")) throw new Error("Administrative and application database roles must differ.");
    const roleName = identifier(role);
    const roles = await sql`SELECT 1 FROM pg_roles WHERE rolname = ${role}`;
    if (roles.length) await sql.unsafe(`ALTER ROLE ${roleName} LOGIN PASSWORD ${literal(password)}`);
    else await sql.unsafe(`CREATE ROLE ${roleName} LOGIN PASSWORD ${literal(password)}`);
    const database = value("POSTGRES_DB");
    const databases = await sql`SELECT 1 FROM pg_database WHERE datname = ${database}`;
    if (!databases.length) await sql.unsafe(`CREATE DATABASE ${identifier(database)} OWNER ${roleName}`);
    const applicationURL = new URL(url);
    applicationURL.pathname = `/${value("POSTGRES_DB")}`;
    const application = new SQL(applicationURL.toString(), { max: 1, connectionTimeout: 10, idleTimeout: 1 });
    try {
      await application.unsafe("CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public VERSION '0.8.6'");
      const extension = await application`SELECT e.extversion, n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector'`;
      if (extension[0]?.extversion !== "0.8.6" || extension[0]?.nspname !== "public") throw new Error("Domabas requires pgvector 0.8.6 in the public schema.");
    } finally { await application.close({ timeout: 5 }); }
    console.log("Application database, role and pgvector are provisioned.");
  } finally { await sql.close({ timeout: 5 }); }
}

try {
  await databases();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
