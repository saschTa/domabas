import { expect, test } from "bun:test";
import { join } from "node:path";
import { ROOT } from "../shared/runtime.ts";
import { RealtimeSmokeProbe } from "./compose-smoke.ts";

async function withRealtimeFrame(frame: Record<string, unknown>, check: (probe: RealtimeSmokeProbe) => Promise<void>): Promise<void> {
  const server = Bun.serve({
    hostname: "127.0.0.1", port: 0,
    fetch(request, server) {
      if (server.upgrade(request, { headers: { "Sec-WebSocket-Protocol": "domabas.realtime.v1" } })) return;
      return new Response("WebSocket required", { status: 400 });
    },
    websocket: { message(socket) { socket.send(JSON.stringify(frame)); } },
  });
  const probe = new RealtimeSmokeProbe(server.url.origin, "test-token", new AbortController().signal);
  try { await check(probe); }
  finally { probe.dispose(); await server.stop(true); }
}

test("Compose realtime probe accepts every topic in the public contract", async () => {
  const contract = Bun.YAML.parse(await Bun.file(join(ROOT, "contracts/backend/openapi.yaml")).text()) as {
    components: { schemas: { RealtimeTopic: { enum: string[] } } };
  };
  await withRealtimeFrame({ type: "ready", version: 1, topics: contract.components.schemas.RealtimeTopic.enum }, async probe => {
    await probe.waitReady();
    expect(probe.mark()).toBe(1);
  });
});

test("Compose realtime probe rejects invalid topics and undeclared frame data", async () => {
  for (const topics of ["documents", ["unknown"], [1], ["chat", "chat"], Array(11).fill("documents")]) {
    await withRealtimeFrame({ type: "ready", version: 1, topics }, async probe => {
      await expect(probe.waitReady()).rejects.toThrow("Invalid realtime topics.");
    });
  }
  await withRealtimeFrame({ type: "ready", version: 1, topics: ["chat"], token: "unexpected" }, async probe => {
    await expect(probe.waitReady()).rejects.toThrow("Realtime frame contains undeclared data.");
  });
});
