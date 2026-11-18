import { existsSync } from "node:fs";
import { open } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

export function inspectionArguments(flutter: string, host: string, webPort: number, apiURL: string): string[] {
  return [flutter, "run", "--release", "--no-web-resources-cdn", "--target=lib/main.dart", "-d", "web-server",
    `--web-hostname=${host}`, `--web-port=${webPort}`, `--dart-define=API_BASE_URL=${apiURL}`];
}

export async function prepareInspection(
  directory: string, apiURL: string, webURL: string, signal: AbortSignal,
  providers: Record<string, unknown> = {},
): Promise<{ manifest: string; stopFile: string }> {
  const email = `inspection-${crypto.randomUUID()}@example.com`;
  const password = `Inspect!${crypto.randomUUID()}`;
  const response = await fetch(`${apiURL}/api/v1/auth/register`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ accountName: "Glacier review library", email, password }),
    signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]),
  });
  await response.body?.cancel();
  if (!response.ok) throw new Error(`Disposable inspection registration failed (${response.status}).`);
  const manifest = join(directory, "inspection.json"), stopFile = join(directory, "inspection.stop");
  const handle = await open(manifest, "wx", 0o600);
  try {
    await handle.writeFile(JSON.stringify({ webURL, apiURL, email, password, stopFile, providers }, null, 2));
  } finally { await handle.close(); }
  return { manifest, stopFile };
}

export async function waitForInspection(
  stopFile: string, signal: AbortSignal, childExit: () => number | null,
  { timeoutMs = 2 * 60 * 60 * 1000, intervalMs = 250 } = {},
): Promise<void> {
  const deadline = performance.now() + timeoutMs;
  while (true) {
    signal.throwIfAborted();
    const code = childExit();
    if (code !== null) throw new Error(`Inspection application or API exited (${code}).`);
    if (existsSync(stopFile)) return;
    if (performance.now() >= deadline) throw new Error("Disposable inspection reached its two-hour limit.");
    await delay(Math.min(intervalMs, Math.max(1, deadline - performance.now())), undefined, { signal });
  }
}
