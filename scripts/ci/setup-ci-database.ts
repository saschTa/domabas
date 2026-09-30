import { SQL } from "bun";
import { required, runCLI } from "../shared/runtime.ts";

if (import.meta.main) await runCLI(async () => {
  const database = new SQL(required(process.env, "TEST_DATABASE_URL"));
  try {
    await database`CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public`;
    await database`CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public`;
  } finally { await database.close(); }
});
