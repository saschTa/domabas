import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { command, ProcessScope, ROOT, runCLI } from "../shared/runtime.ts";

export interface AIComparisonOptions {
  endpoints: string[];
  model: string;
  contexts: number[];
  modes: ("on" | "off")[];
  output: string;
}

export function parseAIComparison(args: string[]): AIComparisonOptions {
  const options: AIComparisonOptions = {
    endpoints: [], model: "qwen3.5:4b", contexts: [16384, 65536], modes: ["off"],
    output: join(ROOT, "backend", "tmp", `ai-comparison-${Date.now()}.json`),
  };
  for (const arg of args) {
    if (arg.startsWith("--endpoint=")) {
      const value = new URL(arg.slice(11));
      if (!["http:", "https:"].includes(value.protocol) || value.username || value.password || value.search || value.hash || value.pathname !== "/") throw new Error("Each endpoint must be an HTTP(S) origin without credentials.");
      options.endpoints.push(value.origin);
    } else if (arg.startsWith("--model=")) options.model = arg.slice(8);
    else if (arg.startsWith("--contexts=")) {
      options.contexts = arg.slice(11).split(",").map(Number);
      if (!options.contexts.length || options.contexts.length > 4 || options.contexts.some(value => !Number.isInteger(value) || value < 4096 || value > 1048576)) throw new Error("Contexts must contain one to four integers from 4096 to 1048576.");
    } else if (arg === "--compare-thinking") options.modes = ["on", "off"];
    else if (arg.startsWith("--output=")) options.output = resolve(arg.slice(9));
    else throw new Error("Unknown argument. Use --endpoint=ORIGIN [--model=TAG] [--contexts=16384,65536] [--compare-thinking] [--output=PATH].");
  }
  if (!options.endpoints.length || options.endpoints.length > 4) throw new Error("Provide one to four explicit --endpoint=ORIGIN values. Run each desired Ollama version separately; this command never upgrades runtimes or downloads models.");
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,199}$/.test(options.model)) throw new Error("Provide a valid installed model tag.");
  return options;
}

export async function inspectAIEndpoint(endpoint: string, model: string, signal: AbortSignal): Promise<{ version: string; digest: string }> {
  const get = async (path: string) => {
    const response = await fetch(endpoint + path, { redirect: "error", signal: AbortSignal.any([signal, AbortSignal.timeout(10000)]) });
    if (!response.ok || !response.body) throw new Error("Evaluation endpoint did not provide runtime metadata.");
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      while (true) {
        const part = await reader.read(); if (part.done) break;
        size += part.value.length;
        if (size > 4 * 1024 * 1024) throw new Error("Evaluation metadata exceeds its size limit.");
        chunks.push(part.value);
      }
    } finally { await reader.cancel(); }
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  };
  const version = await get("/api/version") as { version?: string };
  const tags = await get("/api/tags") as { models?: { name?: string; model?: string; digest?: string }[] };
  const installed = tags.models?.find(value => value.name === model || value.model === model);
  if (!installed?.digest) throw new Error(`Required model ${model} is not installed; no model was downloaded.`);
  if (typeof version.version !== "string" || !/^[a-zA-Z0-9.+_-]{1,100}$/.test(version.version) || !/^(sha256:)?[a-fA-F0-9]{64}$/.test(installed.digest)) throw new Error("Evaluation runtime identity is invalid.");
  return { version: version.version, digest: installed.digest };
}

export async function runAIComparison(scope: ProcessScope, options: AIComparisonOptions): Promise<number> {
  const results: unknown[] = [];
  const report = { createdAt: new Date().toISOString(), model: options.model, synthetic: true, results };
  let failed = false;
  await mkdir(dirname(options.output), { recursive: true });
  const save = () => writeFile(options.output, JSON.stringify(report, null, 2) + "\n");
  for (const [index, endpoint] of options.endpoints.entries()) {
    let identity: { version: string; digest: string };
    try { identity = await inspectAIEndpoint(endpoint, options.model, scope.signal); }
    catch (error) {
      scope.signal.throwIfAborted(); failed = true;
      const message = error instanceof Error && error.message.startsWith("Required model") ? error.message : "Endpoint is unavailable or its runtime/model metadata is invalid.";
      results.push({ endpoint: index + 1, available: false, error: message }); await save(); console.error(`Endpoint ${index + 1}: ${message}`); continue;
    }
    for (const context of options.contexts) for (const thinking of options.modes) {
      console.log(`Evaluating endpoint ${index + 1}, Ollama ${identity.version}, ${options.model}, context ${context}, thinking ${thinking}.`);
      const output = await scope.capture([command("go"), "test", "-count=1", "-v", "-tags=ai_eval", "-timeout=20m", "./tests/aieval"], {
        cwd: join(ROOT, "backend"), env: { ...process.env, AI_EVAL_ENDPOINT: endpoint, AI_EVAL_MODEL: options.model, AI_EVAL_CONTEXT: String(context), AI_EVAL_THINKING: thinking },
      }, 21 * 60 * 1000);
      const cases: unknown[] = [], diagnostics: unknown[] = [];
      for (const line of output.stdout.split(/\r?\n/)) {
        if (line.startsWith("AI_EVAL ")) cases.push(JSON.parse(line.slice(8)));
        else if (line.startsWith('{"time":') && line.includes('"msg":"ai_inference"')) diagnostics.push(JSON.parse(line));
      }
      const passed = output.code === 0 && cases.length === 6;
      failed ||= !passed;
      results.push({ endpoint: index + 1, ...identity, context, thinking, passed, cases, diagnostics });
      await save(); console.log(`${passed ? "Passed" : "Failed"}: ${cases.length} cases recorded.`);
      if (!cases.length) console.error("No evaluation results were produced. Compile the ai_eval test package to check toolchain errors.");
    }
  }
  console.log(`Comparison report: ${options.output}`);
  return failed ? 1 : 0;
}

if (import.meta.main) await runCLI(scope => runAIComparison(scope, parseAIComparison(process.argv.slice(2))), { timeoutMs: 60 * 60 * 1000 });
