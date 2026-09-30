import { expect, test } from "bun:test";
import { inspectAIEndpoint, parseAIComparison } from "./ai-comparison.ts";

test("AI comparison disables thinking by default and requires explicit safe endpoints", () => {
  expect(() => parseAIComparison([])).toThrow("explicit");
  expect(() => parseAIComparison(["--endpoint=http://user:secret@localhost:11434"])).toThrow("credentials");
  expect(() => parseAIComparison(["--endpoint=http://localhost/path"])).toThrow();
  expect(() => parseAIComparison(["--endpoint=http://localhost", "--contexts=NaN"])).toThrow();
  const options = parseAIComparison(["--endpoint=http://localhost:11434"]);
  expect(options.model).toBe("qwen3.5:4b");
  expect(options.modes).toEqual(["off"]);
  expect(options.contexts).toEqual([16384, 65536]);
  expect(parseAIComparison(["--endpoint=http://localhost", "--compare-thinking"]).modes).toEqual(["on", "off"]);
});

test("AI comparison never pulls a missing model and records installed digest", async () => {
  const paths: string[] = [];
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch(request) {
    const path = new URL(request.url).pathname; paths.push(path);
    return Response.json(path === "/api/version" ? { version: "0.34.4" } : { models: [{ name: "qwen3.5:4b", digest: "a".repeat(64) }] });
  } });
  try {
    const endpoint = `http://127.0.0.1:${server.port}`;
    expect(await inspectAIEndpoint(endpoint, "qwen3.5:4b", AbortSignal.timeout(1000))).toEqual({ version: "0.34.4", digest: "a".repeat(64) });
    await expect(inspectAIEndpoint(endpoint, "missing", AbortSignal.timeout(1000))).rejects.toThrow("not installed");
    expect(paths).toEqual(["/api/version", "/api/tags", "/api/version", "/api/tags"]);
  } finally { server.stop(true); }
});
