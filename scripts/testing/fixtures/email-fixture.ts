import { dirname, isAbsolute, join, relative, sep } from "node:path";
import { ROOT, binary, command, type Environment, type ManagedProcess, ProcessScope } from "../../shared/runtime.ts";

export interface EmailFixture {
  host: string;
  port: number;
  caFile: string;
  username: string;
  password: string;
  mailbox: string;
  messageCount: number;
}

export function parseEmailFixture(value: unknown, directory: string): EmailFixture {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid email fixture readiness.");
  const data = value as Record<string, unknown>;
  if (data.host !== "127.0.0.1" || !Number.isInteger(data.port) || Number(data.port) < 1 || Number(data.port) > 65535 ||
      !Number.isInteger(data.messageCount) || Number(data.messageCount) < 1 || Number(data.messageCount) > 100) {
    throw new Error("Invalid email fixture endpoint or message count.");
  }
  for (const key of ["username", "password", "mailbox", "caFile"]) {
    if (typeof data[key] !== "string" || data[key].length < 1 || data[key].length > 4096 || /[\r\n\0]/.test(data[key])) {
      throw new Error("Invalid email fixture metadata.");
    }
  }
  const caFile = data.caFile as string;
  const path = relative(directory, caFile);
  if (!isAbsolute(caFile) || !path || path === ".." || path.startsWith(`..${sep}`) || isAbsolute(path)) {
    throw new Error("Email fixture CA must belong to its temporary directory.");
  }
  return {
    host: data.host, port: Number(data.port), caFile,
    username: data.username as string, password: data.password as string,
    mailbox: data.mailbox as string, messageCount: Number(data.messageCount),
  };
}

export function emailFixtureEnvironment(environment: Environment, fixture: EmailFixture): Environment {
  return {
    ...environment,
    EMAIL_CREDENTIAL_KEYS: "",
    EMAIL_CREDENTIAL_ACTIVE_KEY_ID: "",
    EMAIL_CREDENTIAL_KEY_FILE: join(dirname(fixture.caFile), "email.key"),
    EMAIL_IMAP_CA_FILE: fixture.caFile,
    EMAIL_IMAP_ALLOWED_HOSTS: fixture.host,
  };
}

async function waitFixture(scope: ProcessScope, child: ManagedProcess, readyFile: string, directory: string): Promise<EmailFixture> {
  const deadline = performance.now() + 15000;
  while (performance.now() < deadline) {
    scope.signal.throwIfAborted();
    if (child.exitCode !== null) throw new Error("Email fixture exited before readiness.");
    const file = Bun.file(readyFile);
    if (await file.exists()) {
      if (file.size > 8192) throw new Error("Email fixture readiness exceeds its size limit.");
      return parseEmailFixture(await file.json(), directory);
    }
    await Bun.sleep(50);
  }
  throw new Error("Email fixture did not become ready.");
}

export async function startEmailFixture(scope: ProcessScope, environment: Environment, directory: string): Promise<EmailFixture> {
  const executable = join(directory, binary("imap-fixture"));
  const readyFile = join(directory, "imap-ready.json");
  await scope.run([command("go"), "build", "-o", executable, "./tests/imapfixture/cmd"], { cwd: join(ROOT, "backend"), env: environment });
  const child = scope.start([executable, "--directory", directory, "--ready-file", readyFile, "--addr", "127.0.0.1:0"], {
    cwd: join(ROOT, "backend"), env: environment, stdout: "ignore", stderr: "ignore",
  });
  return waitFixture(scope, child, readyFile, directory);
}
