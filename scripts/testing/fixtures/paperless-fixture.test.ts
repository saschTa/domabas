import { expect, test } from "bun:test";
import { startPaperlessFixture } from "./paperless-fixture.ts";

test("Paperless fixture validates tokens and original-download semantics", async () => {
  const fixture = await startPaperlessFixture();
  try {
    expect((await fetch(`${fixture.url}/api/documents/`)).status).toBe(401);
    const headers = { Authorization: `Token ${fixture.token}` };
    const page = await (await fetch(`${fixture.url}/api/documents/`, { headers })).json() as { results: unknown[] };
    expect(page.results).toHaveLength(2);
    expect((await fetch(`${fixture.url}/api/documents/1/download/`, { headers })).status).toBe(404);
    const original = await fetch(`${fixture.url}/api/documents/1/download/?original=true`, { headers });
    expect(original.headers.get("Content-Type")).toBe("image/png");
    expect((await original.bytes()).byteLength).toBeGreaterThan(1000);
    expect((await fetch(`${fixture.url}/api/documents/`, { method: "POST", headers })).status).toBe(405);
  } finally { await fixture.stop(); }
});
