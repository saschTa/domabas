import { join } from "node:path";
import { ROOT } from "../../shared/runtime.ts";

export async function startPaperlessFixture() {
  const token = crypto.randomUUID().replaceAll("-", "");
  const original = Buffer.concat([await Bun.file(join(ROOT, "scripts/testing/fixtures/invoice.png")).bytes(), Buffer.from("\npaperless-browser-fixture")]);
  const requests: number[] = [];
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch(request) {
    if (request.method !== "GET") return new Response("Read only", { status: 405 });
    if (request.headers.get("Authorization") !== `Token ${token}`) return new Response("Unauthorized", { status: 401 });
    requests.push(Date.now());
    const url = new URL(request.url);
    if (url.pathname === "/api/documents/") return Response.json({ count: 2, next: null, results: [{ id: 1, title: "Paperless browser invoice" }, { id: 2, title: "Unsupported browser original" }] });
    const match = /^\/api\/documents\/([12])\/$/.exec(url.pathname);
    if (match) return Response.json({ id: Number(match[1]), title: match[1] === "1" ? "Paperless browser invoice" : "Unsupported browser original", created: "2026-09-18", original_file_name: match[1] === "1" ? "invoice.png" : "unsupported.txt", tags: [], correspondent: null, document_type: null, archive_serial_number: 42 });
    if (url.pathname === "/api/documents/1/download/" && url.searchParams.get("original") === "true") return new Response(original, { headers: { "Content-Type": "image/png" } });
    if (url.pathname === "/api/documents/2/download/" && url.searchParams.get("original") === "true") return new Response("Unsupported original", { headers: { "Content-Type": "text/plain" } });
    return new Response("Not found", { status: 404 });
  } });
  return { url: `http://127.0.0.1:${server.port}`, token, requests, stop: () => server.stop(true) };
}
