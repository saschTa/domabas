import { expect, test } from "bun:test";
import { forwardDockerPort } from "./ci-network.ts";

test("browser forwarding preserves HTTP origins, cookies and WebSockets and closes on cancellation", async () => {
  const controller = new AbortController();
  const upstream = Bun.serve({
    hostname: "127.0.0.1", port: 0,
    fetch(request, server) {
      if (server.upgrade(request)) return;
      return Response.json({ host: request.headers.get("host"), origin: request.headers.get("origin"), cookie: request.headers.get("cookie") });
    },
    websocket: { message(socket, message) { socket.send(message); } },
  });
  const forwarding = await forwardDockerPort("127.0.0.1", upstream.port!, controller.signal);
  let socket: WebSocket | undefined;
  try {
    const response = await fetch(`${forwarding.origin}/api/v1/auth/restore`, {
      method: "POST", headers: { origin: forwarding.origin, cookie: "session=test-fixture" }, signal: AbortSignal.timeout(3000),
    });
    expect(await response.json()).toEqual({ host: new URL(forwarding.origin).host, origin: forwarding.origin, cookie: "session=test-fixture" });
    socket = new WebSocket(forwarding.origin.replace("http:", "ws:"));
    const current = socket;
    const echoed = new Promise<string>((resolve, reject) => {
      current.onopen = () => current.send("realtime smoke");
      current.onmessage = event => resolve(String(event.data));
      current.onerror = () => reject(new Error("Forwarded WebSocket failed."));
    });
    expect(await echoed).toBe("realtime smoke");
    const closed = new Promise<void>(resolve => { current.onclose = () => resolve(); });
    controller.abort();
    await forwarding.close();
    await closed;
    await expect(fetch(forwarding.origin, { signal: AbortSignal.timeout(3000) })).rejects.toThrow();
  } finally {
    socket?.close();
    await forwarding.close();
    upstream.stop(true);
  }
});
