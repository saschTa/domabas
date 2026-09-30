import { mkdir, mkdtemp, open, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { install } from "./browser/browser-tools.ts";
import { captureCompose, compose, publishedPort } from "../development/compose.ts";
import { dockerTestHost, forwardDockerPort } from "../ci/ci-network.ts";
import { ROOT, type Environment, ProcessScope, environment, runCLI, waitHTTP, withCleanup } from "../shared/runtime.ts";

async function unusedPort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") { server.close(); reject(new Error("No test port available.")); return; }
      server.close(error => error ? reject(error) : resolve(address.port));
    });
  });
}
async function json(url: string, options: RequestInit = {}): Promise<Record<string, unknown>> {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(10000) });
  if (!response.ok) {
    const path = new URL(url).pathname;
    const failure = path.startsWith("/session") ? await response.json().catch(() => null) as { value?: { error?: string; message?: string } } | null : null;
    const detail = path === "/session" && typeof failure?.value?.message === "string" ? ` (${failure.value.message.slice(0,2000)})`
      : typeof failure?.value?.error === "string" ? ` (${failure.value.error.slice(0,100)})` : "";
    throw new Error(`${path} returned HTTP ${response.status}${detail}.`);
  }
  return await response.json() as Record<string, unknown>;
}

export class RealtimeSmokeProbe {
  private readonly socket: Bun.WebSocket;
  private readonly started = performance.now();
  private readonly frames: { serial: number; type: string; topics: string[] }[] = [];
  private serial = 0;
  private ready = false;
  private failure: Error | undefined;
  private closeCode: number | undefined;
  private heartbeats = 0;
  private lastFrame = this.started;
  private readonly abort = () => this.socket.terminate();

  constructor(base: string, token: string, private readonly signal: AbortSignal) {
    const endpoint = new URL(`${base}/api/v1/realtime`);
    endpoint.protocol = endpoint.protocol === "https:" ? "wss:" : "ws:";
    const Socket = globalThis.WebSocket as unknown as { new(url: string, options: Bun.WebSocketOptions): Bun.WebSocket };
    this.socket = new Socket(endpoint.href, { protocols: ["domabas.realtime.v1"], headers: { Origin: new URL(base).origin }, perMessageDeflate: false });
    this.socket.onopen = () => {
      if (this.socket.protocol !== "domabas.realtime.v1") { this.failure = new Error("Proxy did not negotiate the realtime protocol."); return; }
      this.socket.send(JSON.stringify({ type: "authenticate", version: 1, token }));
    };
    (this.socket as unknown as WebSocket).onmessage = event => {
      try {
        if (typeof event.data !== "string" || new TextEncoder().encode(event.data).length > 512) throw new Error("Invalid realtime frame size/type.");
        const frame = JSON.parse(event.data) as Record<string, unknown>;
        if (!frame || frame.version !== 1 || typeof frame.type !== "string" || !["ready", "invalidate", "resync", "heartbeat"].includes(frame.type)) throw new Error("Invalid realtime frame envelope.");
        const keys = frame.type === "heartbeat" ? ["type", "version"] : ["type", "version", "topics"];
        if (Object.keys(frame).length !== keys.length || Object.keys(frame).some(key => !keys.includes(key))) throw new Error("Realtime frame contains undeclared data.");
        const topics = frame.type === "heartbeat" ? [] : frame.topics;
        const allowed = ["documents", "processing", "processing_configuration", "email", "paperless", "chat", "activity", "identity", "members", "system_users"];
        if (!Array.isArray(topics) || topics.length > 10 || new Set(topics).size !== topics.length || topics.some(topic => typeof topic !== "string" || !allowed.includes(topic))) throw new Error("Invalid realtime topics.");
        if ((!this.ready && frame.type !== "ready") || (this.ready && frame.type === "ready")) throw new Error("Invalid realtime readiness sequence.");
        if (frame.type === "ready") this.ready = true;
        if (frame.type === "heartbeat") this.heartbeats++;
        this.lastFrame = performance.now();
        this.frames.push({ serial: ++this.serial, type: frame.type, topics });
        if (this.frames.length > 64) this.frames.shift();
      } catch (error) { this.failure = error instanceof Error ? error : new Error("Malformed realtime frame."); }
    };
    this.socket.onerror = () => { this.failure = new Error("Realtime proxy transport failed."); };
    this.socket.onclose = event => { this.closeCode = event.code; };
    signal.addEventListener("abort", this.abort, { once: true });
    if (signal.aborted) this.abort();
  }

  private async until(predicate: () => boolean, timeout: number, allowClosed = false): Promise<void> {
    const deadline = performance.now() + timeout;
    for (;;) {
      this.signal.throwIfAborted();
      if (this.failure) throw this.failure;
      if (!allowClosed && this.closeCode !== undefined) throw new Error(`Realtime proxy closed unexpectedly (${this.closeCode}).`);
      if (predicate()) return;
      if (performance.now() >= deadline) throw new Error("Realtime proxy acceptance deadline exceeded.");
      await Bun.sleep(10);
    }
  }

  async waitReady(): Promise<void> { await this.until(() => this.ready, 10000); }
  mark(): number { return this.serial; }
  async waitDocuments(after: number): Promise<void> {
    await this.until(() => this.frames.some(frame => frame.serial > after && frame.type === "invalidate" && frame.topics.includes("documents")), 1000);
  }
  async verifyLongConnection(): Promise<void> {
    await this.until(() => performance.now() - this.started >= 70000, Math.max(0, 70000 - (performance.now() - this.started)) + 3000);
    if (this.heartbeats < 3 || performance.now() - this.lastFrame > 25000) throw new Error("Proxy did not sustain realtime heartbeats beyond 65 seconds.");
  }
  async waitShutdown(): Promise<void> {
    await this.until(() => this.closeCode !== undefined, 5000, true);
    if (this.closeCode !== 1001) throw new Error(`Backend did not gracefully drain its proxied socket (${this.closeCode}).`);
  }
  dispose(): void {
    this.signal.removeEventListener("abort", this.abort);
    this.socket.terminate();
  }
}

async function ingestionSmoke(base: string, token: string, signal: AbortSignal): Promise<{ id: string; digest: string }> {
  const source = await Bun.file(join(ROOT, "scripts/testing/fixtures/invoice.png")).bytes();
  const text = Buffer.from(`Comment\0${"A".repeat(1100000)}`);
  const chunk = Buffer.alloc(text.length + 12);
  chunk.writeUInt32BE(text.length);
  chunk.write("tEXt", 4);
  chunk.set(text, 8);
  let checksum = 0xffffffff;
  for (const byte of chunk.subarray(4, -4)) {
    checksum ^= byte;
    for (let bit = 0; bit < 8; bit++) checksum = (checksum >>> 1) ^ ((checksum & 1) ? 0xedb88320 : 0);
  }
  chunk.writeUInt32BE((checksum ^ 0xffffffff) >>> 0, chunk.length - 4);
  const original = Buffer.concat([source.subarray(0, -12), chunk, source.subarray(-12)]);
  const digest = new Bun.CryptoHasher("sha256").update(original).digest("hex");
  const form = new FormData();
  form.append("metadata", JSON.stringify({ title: "Compose upload", tags: ["compose"] }));
  form.append("file", new Blob([original], { type: "image/png" }), "invoice.png");
  const headers = { authorization: `Bearer ${token}` };
  const accepted = await fetch(`${base}/api/v1/documents/upload`, { method: "POST", headers, body: form, signal: AbortSignal.any([signal, AbortSignal.timeout(60000)]) });
  if (accepted.status !== 202) throw new Error(`Upload through nginx returned ${accepted.status}.`);
  const document = await accepted.json() as { id: string; file: { sha256: string } };
  if (document.file.sha256 !== digest) throw new Error("Accepted upload hash differs from its original bytes.");
  const deadline = Date.now() + 180000;
  while (true) {
    signal.throwIfAborted();
    const state = await json(`${base}/api/v1/documents/${document.id}/processing`, { headers });
    if (state.state === "ready") break;
    if (state.state === "failed" || Date.now() > deadline) throw new Error(`Compose ingestion did not become ready: ${state.failureCode ?? state.state}.`);
    await Bun.sleep(500);
  }
  for (const [mode, query] of [["fulltext", "electricity"], ["semantic", "household energy payment"]]) {
    const result = await json(`${base}/api/v1/documents/search`, { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ mode, query, tags: ["compose"] }) });
    const items = result.items as { document: { id: string }; score: number }[];
    if (items[0]?.document.id !== document.id || !Number.isFinite(items[0].score)) throw new Error(`Real ${mode} search did not find the ingested image.`);
  }
  return { id: document.id, digest };
}

async function verifyOriginal(base: string, token: string, original: { id: string; digest: string }): Promise<void> {
  const response = await fetch(`${base}/api/v1/documents/${original.id}/content`, { headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(60000) });
  if (!response.ok || new Bun.CryptoHasher("sha256").update(await response.arrayBuffer()).digest("hex") !== original.digest) throw new Error("Persisted original bytes changed or disappeared.");
}

async function emailSmoke(base: string, token: string, signal: AbortSignal): Promise<{ id: string; digest: string; providerID: string }> {
  const headers = { authorization: `Bearer ${token}` };
  const capabilities = await json(`${base}/api/v1/email-capabilities`, { headers });
  if (capabilities.credentialsAvailable !== true || capabilities.unavailableReason || capabilities.transport !== "implicit_tls") throw new Error("Compose did not initialize automatic email credentials.");
  const providerID = crypto.randomUUID();
  const provider = await json(`${base}/api/v1/email-providers`, { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ id: providerID, label: "Compose key persistence", endpoint: "imap.example.test", port: 993, mailbox: "INBOX", username: "compose-mailbox", password: "compose-fixture-password", enabled: false, intervalMinutes: 15, maxAgeDays: 30, pageSize: 50 }) });
  if (provider.credentialState !== "ready" || provider.username !== "compose-mailbox") throw new Error("Automatic email key could not store mailbox credentials.");
  const configuration = await json(`${base}/api/v1/system/document-processing`, { headers });
  if (configuration.manifestRevision !== 2 || configuration.extractionRevision !== "document-content-v2") throw new Error("Compose did not install the email-capable extraction manifest.");
  const body = "Compose mailbox retention evidence.";
  const original = new TextEncoder().encode(`From: sender@example.test\r\nTo: receiver@example.test\r\nSubject: Compose email\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n${body}\r\n`);
  const digest = new Bun.CryptoHasher("sha256").update(original).digest("hex");
  const form = new FormData();
  form.append("metadata", JSON.stringify({ title: "Compose email", tags: ["compose-email"] }));
  form.append("file", new Blob([original], { type: "message/rfc822" }), "message.eml");
  const accepted = await fetch(`${base}/api/v1/documents/upload`, { method: "POST", headers, body: form, signal: AbortSignal.any([signal, AbortSignal.timeout(60000)]) });
  if (accepted.status !== 202) throw new Error(`EML upload through nginx returned ${accepted.status}.`);
  const document = await accepted.json() as { id: string; file: { sha256: string; mediaType: string } };
  if (document.file.sha256 !== digest || document.file.mediaType !== "message/rfc822") throw new Error("Accepted EML identity differs from its original bytes/type.");
  const deadline = Date.now() + 180000;
  while (true) {
    signal.throwIfAborted();
    const state = await json(`${base}/api/v1/documents/${document.id}/processing`, { headers });
    if (state.state === "ready") {
      if (state.extractionMethod !== "mime" || state.ocrEngine !== "domabas-mime" || state.ocrVersion !== "1" || state.ocrModel !== "") throw new Error("Compose email processing did not preserve actual MIME provenance.");
      break;
    }
    if (state.state === "failed" || Date.now() > deadline) throw new Error(`Compose email did not become ready: ${state.failureCode ?? state.state}.`);
    await Bun.sleep(500);
  }
  const text = await json(`${base}/api/v1/documents/${document.id}/ocr`, { headers });
  if (text.status !== "available" || typeof text.text !== "string" || !text.text.includes(body)) throw new Error("Compose email did not retain its extracted body.");
  const search = await json(`${base}/api/v1/documents/search`, { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ mode: "fulltext", query: "mailbox retention", tags: ["compose-email"] }) });
  const items = search.items as { document: { id: string } }[];
  if (items[0]?.document.id !== document.id) throw new Error("Compose email was not searchable after extraction.");
  return { id: document.id, digest, providerID };
}

async function browserSmoke(scope: ProcessScope, webPort: number, email: string, password: string, dockerHost: string): Promise<void> {
  const { chrome, driver } = await install(scope.signal);
  await scope.run([chrome, "--version"]);
  const driverPort = await unusedPort();
  const log = await open(join(ROOT, ".logs/compose-chromedriver.log"), "w");
  const child = scope.start([driver, `--port=${driverPort}`], { stdout: log.fd, stderr: log.fd });
  const base = `http://127.0.0.1:${driverPort}`;
  let session: string | undefined;
  let forwarded: Awaited<ReturnType<typeof forwardDockerPort>> | undefined;
  await withCleanup(async () => {
    forwarded = await forwardDockerPort(dockerHost, webPort, scope.signal);
    const origin = forwarded.origin;
    await waitHTTP(`${base}/status`, child, 30000, scope.signal);
    const created = await json(`${base}/session`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ capabilities: { alwaysMatch: {
      browserName: "chrome", "goog:loggingPrefs": { performance: "ALL", browser: "ALL" },
      "goog:chromeOptions": { binary: chrome, args: ["--headless=new", "--window-size=1280,1000", "--no-sandbox", "--disable-dev-shm-usage", "--no-proxy-server"] },
    } } }) });
    session = (created.value as { sessionId: string }).sessionId;
    const request = async (path: string, body: unknown) => {
      try {
        return await json(`${base}/session/${session}${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      } catch (error) {
        const screenshot = await json(`${base}/session/${session}/screenshot`).catch(() => null);
        if (typeof screenshot?.value === "string") await Bun.write(join(ROOT, ".logs/compose-browser-failure.png"), Buffer.from(screenshot.value, "base64"));
        throw error;
      }
    };
    await request("/url", { url: origin });
    const element = async (selector: string, using = "css selector"): Promise<string> => {
      const deadline = Date.now() + 60000;
      while (Date.now() < deadline) {
        scope.signal.throwIfAborted();
        await request("/execute/sync", { script: "document.querySelector('flt-semantics-placeholder')?.click(); document.querySelectorAll('flt-glass-pane').forEach(host => host.shadowRoot?.querySelector('flt-semantics-placeholder')?.click()); return true;", args: [] });
        const found = await request("/elements", { using, value: selector });
        const item = (found.value as Record<string, string>[])[0];
        if (item) return item["element-6066-11e4-a52e-4f735466cecf"]!;
        await Bun.sleep(200);
      }
      const state = await request("/execute/sync", { script: "return Array.from(document.querySelectorAll('[aria-label],[role]')).map(e => ({tag:e.tagName,role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.textContent}));", args: [] });
      await Bun.write(join(ROOT, ".logs/compose-browser-semantics.json"), JSON.stringify(state));
      const errors = await request("/log", { type: "browser" });
      console.error(JSON.stringify({ state, errors }).replaceAll(password, "[redacted]").slice(-16000));
      throw new Error(`Compiled Flutter control unavailable: ${selector}`);
    };
    const type = async (label: string, value: string): Promise<void> => {
      const selector = `input[aria-label="${label}"], textarea[aria-label="${label}"], [role="textbox"][aria-label="${label}"]`;
      await request(`/element/${await element(selector)}/click`, {});
      const focusDeadline = Date.now() + 10000;
      let focused = false;
      while (!focused && Date.now() < focusDeadline) {
        scope.signal.throwIfAborted();
        const result = await request("/execute/sync", { script: "return document.activeElement?.getAttribute('aria-label') === arguments[0];", args: [label] });
        focused = result.value === true;
        if (!focused) await Bun.sleep(50);
      }
      if (!focused) throw new Error(`Compiled Flutter input did not receive focus: ${label}`);
      await request(`/element/${await element(selector)}/value`, { text: value });
      await request("/execute/async", { script: "const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(() => done(true)));", args: [] });
    };
    await type("Email", email);
    await type("Password", password);
    await request(`/element/${await element("//*[@role='button' and (@aria-label='Sign in' or normalize-space(.)='Sign in')]", "xpath")}/click`, {});
    let signedIn = false;
    const deadline = Date.now() + 60000;
    while (Date.now() < deadline) {
      scope.signal.throwIfAborted();
      const result = await request("/log", { type: "performance" });
      for (const entry of result.value as { message: string }[]) {
        const event = JSON.parse(entry.message).message as { method: string; params: { response?: { url: string; status: number } } };
        const response = event.params.response;
        if (event.method === "Network.responseReceived" && response?.url === `${origin}/api/v1/auth/login` && response.status === 200) signedIn = true;
        if (event.method === "Network.responseReceived" && response?.url.startsWith(`${origin}/api/v1/documents`)) {
          if (response.status !== 200) throw new Error(`Compiled Flutter app's same-origin API returned ${response.status}.`);
          if (!signedIn) throw new Error("Compiled Flutter queried documents without a successful same-origin sign-in.");
          console.log("Compiled Flutter web app signed in and queried its account library from its published browser origin.");
          return;
        }
      }
      await Bun.sleep(250);
    }
    const state = await request("/execute/sync", { script: "return Array.from(document.querySelectorAll('[aria-label],[role],input')).map(e => ({tag:e.tagName,role:e.getAttribute('role'),label:e.getAttribute('aria-label'),disabled:e.getAttribute('aria-disabled'),valueLength:e instanceof HTMLInputElement ? e.value.length : undefined,text:e instanceof HTMLInputElement ? undefined : e.textContent}));", args: [] });
    const errors = await request("/log", { type: "browser" });
    await Bun.write(join(ROOT, ".logs/compose-browser-timeout.json"), JSON.stringify({ state, errors }));
    const screenshot = await json(`${base}/session/${session}/screenshot`);
    if (typeof screenshot.value === "string") await Bun.write(join(ROOT, ".logs/compose-browser-timeout.png"), Buffer.from(screenshot.value, "base64"));
    throw new Error("The compiled Flutter app did not complete a same-origin document API request.");
  }, async () => {
    try { if (session) await fetch(`${base}/session/${session}`, { method: "DELETE", signal: AbortSignal.timeout(5000) }); }
    finally { try { await child.stop(); } finally { try { await log.close(); } finally { await forwarded?.close(); } } }
  });
}

export async function runSmoke(scope: ProcessScope): Promise<void> {
  const project = `domabas-smoke-${crypto.randomUUID().replaceAll("-", "")}`;
  const temporary = await mkdtemp(join(tmpdir(), "domabas-compose-smoke-"));
  const cachedNetwork = join(temporary, "cached-models.yaml");
  const dockerHost = await dockerTestHost(scope);
  const env: Environment = environment({ ...process.env, COMPOSE_PROJECT_NAME: project, COMPOSE_PROFILES: "", BIND_ADDRESS: dockerHost, PRIVATE_BIND_ADDRESS: dockerHost, POSTGRES_PORT: "0", TEMPORAL_PORT: "0", WEB_PORT: "0", TEMPORAL_UI_PORT: "0", DOCUMENT_PROCESSOR_PORT: "0", LLM_OLLAMA_PORT: "0", LLM_CREDENTIAL_KEY: "", EMAIL_CREDENTIAL_KEYS: "", EMAIL_CREDENTIAL_ACTIVE_KEY_ID: "", EMAIL_IMAP_ALLOWED_HOSTS: "", EMAIL_IMAP_CA_FILE: "", PAPERLESS_CREDENTIAL_KEY: "" });
  const startTemporalUI = async (): Promise<void> => {
    await compose(scope, ["up", "--build", "--wait", "--wait-timeout", "180", "temporal-ui"], env);
    env.TEMPORAL_UI_URL = `http://${dockerHost}:${await publishedPort(scope, "temporal-ui", 8080, env)}`;
    await waitHTTP(`${env.TEMPORAL_UI_URL}/`, undefined, 30000, scope.signal);
  };
  const verifyDashboardLink = async (base: string, headers: Record<string, string>): Promise<void> => {
    const configuration = await json(`${base}/api/v1/system/document-processing`, { headers });
    if (configuration.dashboardUrl !== env.TEMPORAL_UI_URL) throw new Error("Compose did not configure the Temporal dashboard link.");
  };
  const credentialFingerprint = async (): Promise<string> => {
    const fingerprints: string[] = [];
    for (const name of ["paperless", "email", "llm"]) {
      const file = `/var/lib/domabas/secrets/${name}.key`;
      const permissions = await captureCompose(scope, ["exec", "-T", "backend", "stat", "-c", "%a", file], env);
      if (permissions.code || permissions.stdout.trim() !== "600") throw new Error(`Automatic ${name} key is missing or has unsafe permissions.`);
      const fingerprint = await captureCompose(scope, ["exec", "-T", "backend", "sha256sum", file], env);
      if (fingerprint.code || !/^[0-9a-f]{64} /.test(fingerprint.stdout)) throw new Error(`Cannot verify automatic ${name} key persistence.`);
      fingerprints.push(fingerprint.stdout);
    }
    return fingerprints.join("");
  };
  const realtimeProbes: RealtimeSmokeProbe[] = [];
  let passed = false;
  await mkdir(join(ROOT, ".logs"), { recursive: true });
  await withCleanup(async () => {
    await Bun.write(cachedNetwork, "services:\n  ollama:\n    networks: [cached_models]\n  document-processor:\n    networks: [cached_models]\n  backend:\n    networks: [default, cached_models]\nnetworks:\n  cached_models:\n    internal: true\n");
    await startTemporalUI();
    await compose(scope, ["up", "--build", "--wait", "--wait-timeout", "900"], env);
    const port = await publishedPort(scope, "web", 8080, env), base = `http://${dockerHost}:${port}`;
    for (const path of ["/", "/flutter_bootstrap.js", "/main.dart.js", "/readyz"]) {
      const response = await fetch(`${base}${path}`, { signal: AbortSignal.timeout(10000) });
      await response.body?.cancel();
      if (!response.ok) throw new Error(`Web asset/proxy ${path} returned ${response.status}.`);
    }
    const email = `compose-${crypto.randomUUID()}@example.test`, password = "Compose strong password 2026";
    const session = await json(`${base}/api/v1/auth/register`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ accountName: "Compose smoke", email, password }) });
    const token = session.token;
    const identity = session.identity as { account: { id: string }; user: { id: string }; systemRole: string; isOwner: boolean };
    const accountID = identity.account.id;
    if (typeof token !== "string" || typeof accountID !== "string") throw new Error("Registration did not return a session/account.");
    if (identity.systemRole !== "admin" || !identity.isOwner) throw new Error("The first fresh-install user did not own its library and receive system administration.");
    const realtime = new RealtimeSmokeProbe(base, token, scope.signal);
    realtimeProbes.push(realtime);
    await realtime.waitReady();
    const recovery = await captureCompose(scope, ["exec", "-T", "backend", "/app/bootstrap-admin", "--user-id", identity.user.id], env);
    if (recovery.code === 0) throw new Error("Operator bootstrap replaced an existing administrator.");
    const headers = { "content-type": "application/json", authorization: `Bearer ${token}` };
    await verifyDashboardLink(base, headers);
    const paperlessOptions = await json(`${base}/api/v1/paperless-import`, { headers });
    if (paperlessOptions.pageSize !== 100 || Object.keys(paperlessOptions).length !== 1) throw new Error("Paperless requires unexpected operator setup on a fresh installation.");
    const initialCredentialFingerprint = await credentialFingerprint();
    const anonymous = await fetch(`${base}/api/v1/documents`, { signal: AbortSignal.timeout(10000) });
    await anonymous.body?.cancel();
    if (anonymous.status !== 401) throw new Error("Document library accepted an anonymous request.");
    const created = await json(`${base}/api/v1/documents`, { method: "POST", headers, body: JSON.stringify({ title: "Compose persistence smoke", description: "A real PostgreSQL and Temporal integration." }) });
    const id = created.id;
    if (typeof id !== "string") throw new Error("API creation did not return a document ID.");
    const original = await ingestionSmoke(base, token, scope.signal);
    await verifyOriginal(base, token, original);
    const originalEmail = await emailSmoke(base, token, scope.signal);
    await verifyOriginal(base, token, originalEmail);
    const invitedEmail = `separate-${crypto.randomUUID()}@example.test`;
    const invitation = await json(`${base}/api/v1/account/invitations`, { method: "POST", headers, body: JSON.stringify({ email: invitedEmail, role: "viewer", claims: [] }) });
    if (typeof invitation.code !== "string" || invitation.code.length !== 43) throw new Error("Invitation creation did not return its one-time capability.");
    await browserSmoke(scope, port, email, password, dockerHost);
    await realtime.verifyLongConnection();
    const beforeRename = realtime.mark();
    await json(`${base}/api/v1/documents/${id}`, { method: "PATCH", headers, body: JSON.stringify({ title: "Compose live update after 65 seconds" }) });
    await realtime.waitDocuments(beforeRename);
    const workflowID = `compose-${crypto.randomUUID()}`;
    const workflow = async (args: string[]): Promise<Record<string, unknown>> => {
      const result = await captureCompose(scope, ["run", "--rm", "--no-deps", "--entrypoint", "/app/workflow", "backend", ...args], env, 180000);
      if (result.code) throw new Error(`Workflow diagnostic failed: ${result.stderr}`);
      return JSON.parse(result.stdout.trim()) as Record<string, unknown>;
    };
    const shutdown = await Promise.allSettled([compose(scope, ["stop", "backend"], env), realtime.waitShutdown()]);
    for (const result of shutdown) if (result.status === "rejected") throw result.reason;
    realtime.dispose();
    const queued = await workflow(["--account-id", accountID, "--document-id", id, "--workflow-id", workflowID, "--enqueue-only", "--timeout", "2m"]);
    if (queued.workflowId !== workflowID) throw new Error("Workflow was not queued with the test-owned ID.");
    await compose(scope, ["up", "--no-deps", "--wait", "--wait-timeout", "90", "backend"], env);
    await waitHTTP(`${base}/readyz`, undefined, 30000, scope.signal);
    const reconnected = new RealtimeSmokeProbe(base, token, scope.signal);
    realtimeProbes.push(reconnected);
    await reconnected.waitReady();
    const baseline = await json(`${base}/api/v1/documents/${id}`, { headers });
    if (baseline.title !== "Compose live update after 65 seconds") throw new Error("Realtime reconnect REST baseline lost the committed update.");
    const afterReconnect = reconnected.mark();
    await json(`${base}/api/v1/documents/${id}`, { method: "PATCH", headers, body: JSON.stringify({ title: "Compose live update after reconnect" }) });
    await reconnected.waitDocuments(afterReconnect);
    reconnected.dispose();
    const result = await workflow(["--wait-workflow-id", workflowID, "--timeout", "60s"]);
    if (result.id !== id || typeof result.createdAt !== "string") throw new Error("Queued workflow did not read the persisted document.");
    await compose(scope, ["stop", "temporal"], env);
    const live = await fetch(`${base}/healthz`, { signal: AbortSignal.timeout(10000) });
    const unready = await fetch(`${base}/readyz`, { signal: AbortSignal.timeout(10000) });
    await live.body?.cancel(); await unready.body?.cancel();
    if (live.status !== 200 || unready.status !== 503) throw new Error("API liveness/readiness did not distinguish Temporal outage.");
    await compose(scope, ["up", "--no-deps", "--wait", "--wait-timeout", "180", "temporal"], env);
    await waitHTTP(`${base}/readyz`, undefined, 90000, scope.signal);
    const persisted = await workflow(["--wait-workflow-id", workflowID, "--timeout", "60s"]);
    if (persisted.id !== id) throw new Error("Temporal workflow result did not survive restart.");
    for (const service of ["database-init", "temporal-schema", "temporal-init"]) await compose(scope, ["run", "--rm", "--no-deps", service], env);
    await compose(scope, ["up", "--no-deps", "--force-recreate", "--wait", "--wait-timeout", "90", "backend"], env);
    await waitHTTP(`${base}/readyz`, undefined, 30000, scope.signal);
    const reloaded = await json(`${base}/api/v1/documents/${id}`, { headers });
    if (reloaded.id !== id) throw new Error("Document/proxy did not survive backend recreation.");
    await compose(scope, ["down"], env);
    await startTemporalUI();
    await compose(scope, ["--file", cachedNetwork, "up", "--wait", "--wait-timeout", "900"], env);
    const egress = await captureCompose(scope, ["exec", "-T", "document-processor", "curl", "--fail", "--silent", "--max-time", "3", "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/README.md"], env);
    if (egress.code === 0) throw new Error("Cached model restart unexpectedly retained external network access.");
    const restartedBase = `http://${dockerHost}:${await publishedPort(scope, "web", 8080, env)}`;
    await verifyDashboardLink(restartedBase, headers);
    const afterRestart = await json(`${restartedBase}/api/v1/documents/${id}`, { headers });
    if (await credentialFingerprint() !== initialCredentialFingerprint) throw new Error("Credential encryption keys changed across retained-volume restart.");
    const retainedProvider = await json(`${restartedBase}/api/v1/email-providers/${originalEmail.providerID}`, { headers });
    if (retainedProvider.credentialState !== "ready" || retainedProvider.username !== "compose-mailbox") throw new Error("Email credentials could not decrypt after retained-volume restart.");
    await verifyOriginal(restartedBase, token, original);
    await verifyOriginal(restartedBase, token, originalEmail);
    const history = await workflow(["--wait-workflow-id", workflowID, "--timeout", "60s"]);
    if (afterRestart.id !== id || history.id !== id) throw new Error("Application or workflow data was lost across full Compose down/up.");
    const restoredIdentity = await json(`${restartedBase}/api/v1/auth/session`, { headers });
    if (restoredIdentity.systemRole !== "admin") throw new Error("Administrator authority did not survive retained-volume restart.");
    const other = await json(`${restartedBase}/api/v1/auth/register`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ accountName: "Separate account", email: invitedEmail, password }) });
    const otherIdentity = other.identity as { account: { id: string }; systemRole: string };
    if (otherIdentity.systemRole !== "user") throw new Error("Retained startup reset the first-administrator decision.");
    const otherHeaders = { "content-type": "application/json", authorization: `Bearer ${other.token}` };
    const isolated = await json(`${restartedBase}/api/v1/documents`, { headers: otherHeaders });
    const foreign = await fetch(`${restartedBase}/api/v1/documents/${id}`, { headers: otherHeaders, signal: AbortSignal.timeout(10000) });
    await foreign.body?.cancel();
    if (isolated.total !== 0 || foreign.status !== 404) throw new Error("Account libraries are not isolated after retained-volume restart.");
    const accepted = await json(`${restartedBase}/api/v1/auth/accept-invitation`, { method: "POST", headers: otherHeaders, body: JSON.stringify({ code: invitation.code }) });
    if ((accepted.account as { id: string }).id !== accountID || accepted.role !== "viewer") throw new Error("Invitation capability did not survive restart with its intended scope.");
    const shared = await json(`${restartedBase}/api/v1/auth/switch-account`, { method: "POST", headers: otherHeaders, body: JSON.stringify({ accountId: accountID }) });
    if (shared.token === other.token || shared.expiresAt !== other.expiresAt) throw new Error("Namespace switching did not rotate the bearer while preserving expiry.");
    const sharedHeaders = { "content-type": "application/json", authorization: `Bearer ${shared.token}` };
    const sharedDocument = await json(`${restartedBase}/api/v1/documents/${id}`, { headers: sharedHeaders });
    if (sharedDocument.id !== id) throw new Error("Accepted membership could not read its shared document.");
    const denied = await fetch(`${restartedBase}/api/v1/documents`, { method: "POST", headers: sharedHeaders, body: JSON.stringify({ title: "Viewer cannot write" }), signal: AbortSignal.timeout(10000) });
    const revoked = await fetch(`${restartedBase}/api/v1/auth/session`, { headers: otherHeaders, signal: AbortSignal.timeout(10000) });
    await denied.body?.cancel(); await revoked.body?.cancel();
    if (denied.status !== 403 || revoked.status !== 401) throw new Error("Shared role or switched-session revocation was not enforced.");
    const personal = await json(`${restartedBase}/api/v1/auth/switch-account`, { method: "POST", headers: sharedHeaders, body: JSON.stringify({ accountId: otherIdentity.account.id }) });
    const personalDocuments = await json(`${restartedBase}/api/v1/documents`, { headers: { authorization: `Bearer ${personal.token}` } });
    if (personalDocuments.total !== 0) throw new Error("Shared document data leaked into the personal namespace after switching back.");
    console.log("Compose smoke passed: real OCR/embeddings, upload above 1 MiB through nginx, automatic email/Paperless keys and credential persistence, EML extraction/provenance/search, original/model cache persistence, compiled web sign-in, realtime nginx heartbeats beyond 65 seconds, graceful socket shutdown/reconnect, namespace isolation, worker recovery, outage readiness and retained-volume restart.");
    passed = true;
  }, async () => {
    for (const probe of realtimeProbes) probe.dispose();
    const cleanup = new ProcessScope();
    try {
      const logs = await captureCompose(cleanup, ["logs", "--no-color"], env);
      await Bun.write(join(ROOT, ".logs/compose-smoke.log"), logs.stdout + logs.stderr);
      if (!passed) {
        const diagnostics = await captureCompose(cleanup, ["logs", "--no-color", "--tail", "60", "document-processor", "ollama", "backend", "web"], env);
        console.error(diagnostics.stdout + diagnostics.stderr);
      }
    } finally {
      try { await compose(cleanup, ["--file", cachedNetwork, "down", "--volumes", "--remove-orphans"], env, 120000); }
      finally { try { await cleanup.close(); } finally { await rm(temporary, { recursive: true, force: true }); } }
    }
  });
}

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: { help: { type: "boolean", short: "h" } } });
  if (values.help) { console.log("Usage: bun scripts/testing/compose-smoke.ts (builds/tests/removes its own disposable stack)"); return; }
  await runSmoke(scope);
}, { timeoutMs: 18 * 60 * 1000 });
