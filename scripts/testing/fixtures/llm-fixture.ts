export const llmFixtureProperties = {
  sender: "LLM fixture sender",
  subject: "LLM fixture subject",
  description: "Extracted from document text",
  tags: ["llm-extracted"],
  documentDate: "2026-09-19",
  recipients: [],
};

export function startLLMFixture() {
  const key = crypto.randomUUID();
  let calls = 0;
  let failureDelivered = false;
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      if (new URL(request.url).pathname !== "/v1/chat/completions" || request.method !== "POST") {
        return new Response(null, { status: 404 });
      }
      if (request.headers.get("Authorization") !== `Bearer ${key}`) {
        return new Response(null, { status: 401 });
      }
      const body = await request.json() as { model?: string; messages?: { role: string; content: string; tool_call_id?: string }[]; stream?: boolean; tools?: unknown[]; response_format?: { type?: string; json_schema?: { name?: string; schema?: { type?: string } } } };
      if (body.model === "chat-fixture-model") {
        if (body.stream !== false || !body.tools?.length || !body.messages?.some(message => message.role === "user" && message.content?.trim())) return new Response(null, { status: 400 });
        calls++;
        const results = body.messages.filter(message => message.role === "tool");
        const tool = (id: string, name: string, args: unknown) => Response.json({ choices: [{ finish_reason: "tool_calls", message: { role: "assistant", content: "", tool_calls: [{ id, type: "function", function: { name, arguments: JSON.stringify(args) } }] } }] });
        if (!results.length) return tool("chat-catalog-first", "list_tools", { offset: 0 });
        if (results.length === 1) {
          const catalog = JSON.parse(results[0]!.content) as { nextOffset?: number };
          if (catalog.nextOffset === undefined) return new Response(null, { status: 422 });
          return tool("chat-catalog-next", "list_tools", { offset: catalog.nextOffset });
        }
        if (results.length === 2) return tool("chat-search", "search_documents", { query: "Chat evidence", offset: 0 });
        if (results.length === 3) {
          const result = JSON.parse(results[2]!.content) as { items?: { documentId: string }[] };
          if (result.items?.[0]?.documentId) return tool("chat-read", "read_document", { documentId: result.items[0].documentId, offset: 0 });
        }
        const evidence = results.slice(3).some(result => {
          const document = JSON.parse(result.content) as { text?: string };
          return document.text?.includes("42 euros");
        });
        return Response.json({ choices: [{ finish_reason: "stop", message: { role: "assistant", content: evidence ? "Your Chat evidence PDF records a reference amount of 42 euros." : "The available Chat evidence does not establish the reference amount." } }] });
      }
      if (body.model !== "fixture-model" || body.stream !== false || !body.messages?.some(message => message.role === "user" && message.content.trim())) {
        return new Response(null, { status: 400 });
      }
      if (body.response_format?.type !== "json_schema" || !body.response_format.json_schema?.name || body.response_format.json_schema.schema?.type !== "object") {
        return Response.json({ error: "response_format.type must be json_schema for the LM Studio fixture" }, { status: 400 });
      }
      calls++;
      if (!failureDelivered && body.messages.some(message => message.content.includes("AI isolation retry fixture"))) {
        failureDelivered = true;
        return new Response(null, { status: 401 });
      }
      return Response.json({ choices: [{ finish_reason: "stop", message: { role: "assistant", content: JSON.stringify(body.messages.some(message => message.content.includes('"required":["reason"]')) ? { reason: "other_document" } : body.messages.some(message => message.content.includes('"isInvoice"')) ? { isInvoice: false, invoice: null } : llmFixtureProperties) } }] });
    },
  });
  return {
    url: `http://127.0.0.1:${server.port}/v1`, key,
    get calls() { return calls; },
    stop: () => server.stop(true),
  };
}
