import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { normalizeGeneratedFile } from "./generated-comments.ts";
import { ROOT, ProcessScope, binary, download, runCLI } from "../shared/runtime.ts";

export const VERSION = "7.25.0";
export const SHA256 = "41ce4f6b07f196676439d710759fa1ced7a08066d06ff1bf314681470289efae";

export async function sha256(file: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of Bun.file(file).stream()) hash.update(chunk);
  return hash.digest("hex");
}

async function javaCommand(scope: ProcessScope): Promise<string> {
  const candidates = [process.env.JAVA_HOME ? join(process.env.JAVA_HOME, "bin", binary("java")) : undefined,
    "/opt/homebrew/opt/openjdk@21/bin/java", "/usr/local/opt/openjdk@21/bin/java", Bun.which("java")];
  for (const java of candidates) {
    if (!java) continue;
    try { if ((await scope.capture([java, "-version"])).code === 0) return java; }
    catch { scope.signal.throwIfAborted(); }
  }
  throw new Error("Java 17+ is required for contract generation. Set JAVA_HOME to its installation.");
}

export async function replaceDirectory(source: string, target: string): Promise<void> {
  const backup = `${target}.previous-${crypto.randomUUID()}`;
  const existing = existsSync(target);
  if (existing) await rename(target, backup);
  try { await rename(source, target); }
  catch (error) {
    if (existing) await rename(backup, target);
    throw error;
  }
  if (existing) await rm(backup, { recursive: true, force: true });
}

export async function generateClient(scope: ProcessScope): Promise<void> {
  const java = await javaCommand(scope);
  const jar = join(ROOT, ".tools", `openapi-generator-cli-${VERSION}.jar`);
  await mkdir(dirname(jar), { recursive: true });
  if (!existsSync(jar)) {
    const temporary = `${jar}.${crypto.randomUUID()}.download`;
    try {
      await download(`https://repo.maven.apache.org/maven2/org/openapitools/openapi-generator-cli/${VERSION}/openapi-generator-cli-${VERSION}.jar`, temporary, scope.signal);
      if (await sha256(temporary) !== SHA256) throw new Error("Generator download failed SHA-256 verification.");
      await rename(temporary, jar);
    } finally { await rm(temporary, { force: true }); }
  }
  if (await sha256(jar) !== SHA256) throw new Error(`Unexpected generator checksum; remove ${jar} and retry.`);
  const target = join(ROOT, "frontend/packages/domabas_api");
  await mkdir(dirname(target), { recursive: true });
  const temporary = await mkdtemp(join(dirname(target), ".domabas-generator-"));
  try {
    const output = join(temporary, "client");
    await scope.run([java, "-jar", jar, "generate", "-i", "contracts/backend/openapi.yaml", "-g", "dart",
      "-c", "frontend/openapi-generator.yaml", "-o", output,
      "--openapi-generator-ignore-list", ".travis.yml,git_push.sh,README.md",
      "--global-property", "apiTests=false,modelTests=false,apiDocs=false,modelDocs=false"]);
    scope.signal.throwIfAborted();
    for await (const path of new Bun.Glob("lib/**/*.dart").scan({ cwd: output, absolute: true })) {
      await normalizeGeneratedFile(path);
    }
    await replaceDirectory(output, target);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

if (import.meta.main) await runCLI(generateClient);
