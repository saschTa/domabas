import { expect, test } from "bun:test";
import { llmFixtureProperties, startLLMFixture } from "./llm-fixture.ts";

test("LM Studio fixture rejects the standard JSON object mode", async () => {
  const fixture = startLLMFixture();
  try {
    const response = await fetch(`${fixture.url}/chat/completions`, {
      method: "POST", headers: { Authorization: `Bearer ${fixture.key}` },
      body: JSON.stringify({ model: "fixture-model", stream: false, response_format: { type: "json_object" }, messages: [{ role: "user", content: "Synthetic document" }] }),
    });
    expect(response.status).toBe(400);
    expect(fixture.calls).toBe(0);
  } finally { fixture.stop(); }
});

test("LLM fixture authenticates and validates the production wire protocol", async () => {
  const fixture = startLLMFixture();
  try {
    const body = JSON.stringify({ model: "fixture-model", stream: false, response_format: { type: "json_schema", json_schema: { name: "document_response", schema: { type: "object" } } }, messages: [{ role: "user", content: "Invoice OCR" }] });
    const denied = await fetch(`${fixture.url}/chat/completions`, { method: "POST", body });
    expect(denied.status).toBe(401);
    const response = await fetch(`${fixture.url}/chat/completions`, { method: "POST", body, headers: { Authorization: `Bearer ${fixture.key}` } });
    const value = await response.json() as { choices: { message: { content: string } }[] };
    expect(JSON.parse(value.choices[0]!.message.content)).toEqual(llmFixtureProperties);
    expect(fixture.calls).toBe(1);
  } finally { fixture.stop(); }
});

test("LLM fixture distinguishes the invoice decision from property output", async () => {
  const fixture = startLLMFixture();
  try {
    const response = await fetch(`${fixture.url}/chat/completions`, {
      method: "POST", headers: { Authorization: `Bearer ${fixture.key}` },
      body: JSON.stringify({ model: "fixture-model", stream: false, response_format: { type: "json_schema", json_schema: { name: "document_response", schema: { type: "object" } } }, messages: [
        { role: "system", content: 'Return JSON matching the invoice schema with "isInvoice" and "invoice".' },
        { role: "user", content: "A document without an invoice number or amount." },
      ] }),
    });
    const value = await response.json() as { choices: { message: { content: string } }[] };
    expect(JSON.parse(value.choices[0]!.message.content)).toEqual({ isInvoice: false, invoice: null });
  } finally { fixture.stop(); }
});

test("LLM isolation fixture fails once and accepts an independent retry", async () => {
  const fixture = startLLMFixture();
  try {
    const request = {
      method: "POST", headers: { Authorization: `Bearer ${fixture.key}` },
      body: JSON.stringify({ model: "fixture-model", stream: false, response_format: { type: "json_schema", json_schema: { name: "document_response", schema: { type: "object" } } }, messages: [{ role: "user", content: "AI isolation retry fixture" }] }),
    };
    expect((await fetch(`${fixture.url}/chat/completions`, request)).status).toBe(401);
    const response = await fetch(`${fixture.url}/chat/completions`, request);
    expect(response.status).toBe(200);
    const value = await response.json() as { choices: { message: { content: string } }[] };
    expect(JSON.parse(value.choices[0]!.message.content)).toEqual(llmFixtureProperties);
    expect(fixture.calls).toBe(2);
  } finally { fixture.stop(); }
});

test("Chat fixture discovers paginated tools and reads PDF evidence before answering", async () => {
  const fixture = startLLMFixture();
  const messages: { role: string; content: string }[] = [{ role: "user", content: "Find Chat evidence" }];
  const request = async () => {
    const response = await fetch(`${fixture.url}/chat/completions`, { method: "POST", headers: { Authorization: `Bearer ${fixture.key}` }, body: JSON.stringify({ model: "chat-fixture-model", stream: false, tools: [{}], messages }) });
    expect(response.status).toBe(200);
    return await response.json() as { choices: { message: { content: string; tool_calls?: { function: { name: string; arguments: string } }[] } }[] };
  };
  try {
    expect((await request()).choices[0]!.message.tool_calls![0]!.function.name).toBe("list_tools");
    messages.push({ role: "tool", content: JSON.stringify({ items: [{ name: "search_documents" }, { name: "read_document" }], nextOffset: 2 }) });
    const next = (await request()).choices[0]!.message.tool_calls![0]!.function;
    expect(next.name).toBe("list_tools");
    expect(JSON.parse(next.arguments)).toEqual({ offset: 2 });
    messages.push({ role: "tool", content: JSON.stringify({ items: [{ name: "list_tools" }] }) });
    expect((await request()).choices[0]!.message.tool_calls![0]!.function.name).toBe("search_documents");
    messages.push({ role: "tool", content: JSON.stringify({ items: [{ documentId: "6aeb369d-831a-42ba-8c6e-7e99450c5306" }] }) });
    const read = (await request()).choices[0]!.message.tool_calls![0]!.function;
    expect(read.name).toBe("read_document");
    expect(JSON.parse(read.arguments).documentId).toBe("6aeb369d-831a-42ba-8c6e-7e99450c5306");
    messages.push({ role: "tool", content: JSON.stringify({ text: "42 euros" }) });
    expect((await request()).choices[0]!.message.content).toContain("42 euros");
    expect(fixture.calls).toBe(5);
  } finally { fixture.stop(); }
});

test("LLM fixture returns only a classification decision before extraction", async () => {
  const fixture = startLLMFixture();
  try {
    const response = await fetch(`${fixture.url}/chat/completions`, {
      method: "POST", headers: { Authorization: `Bearer ${fixture.key}` },
      body: JSON.stringify({ model: "fixture-model", stream: false, response_format: { type: "json_schema", json_schema: { name: "document_response", schema: { type: "object" } } }, messages: [
        { role: "system", content: 'Classify with schema {"required":["reason"]}.' },
        { role: "user", content: "A career profile for a software engineer." },
      ] }),
    });
    const value = await response.json() as { choices: { message: { content: string } }[] };
    expect(JSON.parse(value.choices[0]!.message.content)).toEqual({ reason: "other_document" });
  } finally { fixture.stop(); }
});
