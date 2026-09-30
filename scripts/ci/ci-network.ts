import { existsSync } from "node:fs";
import { createConnection, createServer, isIPv4, type Socket } from "node:net";
import { hostname } from "node:os";
import { ProcessScope, command } from "../shared/runtime.ts";

export function dockerGateway(inspect: { HostConfig: { NetworkMode: string }; NetworkSettings: { Networks: Record<string, { Gateway?: string }> } }): string {
  if (inspect.HostConfig.NetworkMode === "host") return "127.0.0.1";
  const gateways = [...new Set(Object.values(inspect.NetworkSettings.Networks).map(network => network.Gateway).filter(value => value && isIPv4(value)))];
  if (gateways.length !== 1) throw new Error("Cannot select the runner's Docker gateway; set DOCKER_TEST_HOST to its reachable IPv4 address.");
  return gateways[0]!;
}

export async function dockerTestHost(scope: ProcessScope): Promise<string> {
  const explicit = process.env.DOCKER_TEST_HOST;
  if (explicit) {
    if (!isIPv4(explicit)) throw new Error("DOCKER_TEST_HOST must be an IPv4 address on the Docker host.");
    return explicit;
  }
  if (!existsSync("/.dockerenv")) return "127.0.0.1";
  const result = await scope.capture([command("docker"), "inspect", hostname()]);
  if (result.code) throw new Error("Cannot inspect the CI container; use a local Docker socket or set DOCKER_TEST_HOST explicitly.");
  return dockerGateway(JSON.parse(result.stdout)[0]);
}

export async function forwardDockerPort(host: string, port: number, signal: AbortSignal): Promise<{ origin: string; close: () => Promise<void> }> {
  signal.throwIfAborted();
  const sockets = new Set<Socket>();
  const server = createServer(client => {
    const upstream = createConnection({ host, port });
    for (const [socket, peer] of [[client, upstream], [upstream, client]] as const) {
      sockets.add(socket);
      socket.on("error", () => peer.destroy());
      socket.on("close", () => { sockets.delete(socket); peer.destroy(); });
    }
    client.pipe(upstream).pipe(client);
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => { server.removeListener("error", reject); resolve(); });
  });
  let closing: Promise<void> | undefined;
  const close = (): Promise<void> => closing ??= new Promise<void>((resolve, reject) => {
    signal.removeEventListener("abort", abort);
    for (const socket of sockets) socket.destroy();
    server.close(error => error ? reject(error) : resolve());
  });
  const abort = () => { void close().catch(() => {}); };
  signal.addEventListener("abort", abort, { once: true });
  if (signal.aborted) { await close(); signal.throwIfAborted(); }
  const address = server.address();
  if (!address || typeof address === "string") { await close(); throw new Error("Cannot allocate the browser's loopback forwarding port."); }
  return { origin: `http://127.0.0.1:${address.port}`, close };
}
