import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { compose } from "./compose.ts";
import { ROOT, ProcessScope, binary, runCLI } from "../shared/runtime.ts";

export const DATA = join(ROOT, ".cache/postgres");

export async function nativeBin(scope: ProcessScope): Promise<string> {
  const path = Bun.which("postgres");
  const candidates = [process.env.POSTGRES_BIN, path ? dirname(path) : undefined,
    "/opt/homebrew/opt/postgresql@18/bin", "/usr/local/opt/postgresql@18/bin"];
  for (const candidate of candidates) {
    if (!candidate || !existsSync(join(candidate, binary("postgres")))) continue;
    const result = await scope.capture([join(candidate, binary("postgres")), "--version"]);
    if (!result.code && /\b18\./.test(result.stdout)) return candidate;
  }
  throw new Error("Install the PostgreSQL client or set POSTGRES_BIN to its binary directory.");
}

export async function up(scope: ProcessScope): Promise<void> {
  try {
    await compose(scope, ["up", "--wait", "--wait-timeout", "90", "postgres"]);
    await compose(scope, ["run", "--build", "--rm", "--no-deps", "database-init"]);
  }
  catch (error) {
    if (existsSync(join(DATA, "postmaster.pid"))) console.error(`A native PostgreSQL cluster may own port 54329. Stop it with pg_ctl -D "${DATA}" -m fast -w stop, or use --external-services with PostgreSQL and Temporal endpoints. Its data has not been modified.`);
    throw error;
  }
}
export async function down(scope: ProcessScope): Promise<void> {
  await compose(scope, ["stop", "postgres"]);
}

if (import.meta.main) await runCLI(async scope => {
  const { positionals, values } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true, options: { help: { type: "boolean", short: "h" } } });
  if (values.help) { console.log("Usage: bun scripts/development/database.ts <up|down>"); return; }
  if (positionals.length !== 1 || !["up", "down"].includes(positionals[0]!)) throw new Error("Usage: bun scripts/development/database.ts <up|down>");
  await (positionals[0] === "up" ? up(scope) : down(scope));
});
