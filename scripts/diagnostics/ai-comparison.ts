import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { command, ProcessScope, ROOT, runCLI } from "../shared/runtime.ts";

export interface AIComparisonOptions {
  endpoints: string[];
  model: string;
  modes: ("on" | "off")[];
  output: string;
}

export function parseAIComparison(args: string[]): AIComparisonOptions {
  const options: AIComparisonOptions = {
    endpoints: [], model: "", modes: ["off"],
    output: join(ROOT, "backend", "tmp", `ai-comparison-${Date.now()}.json`),
  };
  for (const arg of args) {
    if (arg.startsWith("--endpoint=")) {
      const value = new URL(arg.slice(11));
      if (!["http:", "https:"].includes(value.protocol) || value.username || value.password || value.search || value.hash) throw new Error("Each endpoint must be an HTTP(S) API base URL without credentials.");
      options.endpoints.push(value.href.replace(/\/+$/, ""));
    } else if (arg.startsWith("--model=")) options.model = arg.slice(8);
    else if (arg === "--compare-thinking") options.modes = ["on", "off"];
    else if (arg.startsWith("--output=")) options.output = resolve(arg.slice(9));
    else throw new Error("Unknown argument. Use --endpoint=BASE_URL --model=MODEL [--compare-thinking] [--output=PATH].");
  }
  if (!options.endpoints.length || options.endpoints.length > 4) throw new Error("Provide one to four explicit --endpoint=BASE_URL values.");
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,199}$/.test(options.model)) throw new Error("Provide an explicit --model=MODEL identifier.");
  return options;
}

export async function runAIComparison(scope: ProcessScope, options: AIComparisonOptions): Promise<number> {
  const results: unknown[] = [];
  const report = { createdAt: new Date().toISOString(), model: options.model, synthetic: true, results };
  let failed = false;
  await mkdir(dirname(options.output), { recursive: true });
  const save = () => writeFile(options.output, JSON.stringify(report, null, 2) + "\n");
  for (const [index, endpoint] of options.endpoints.entries()) {
    for (const thinking of options.modes) {
      console.log(`Evaluating endpoint ${index + 1}, model ${options.model}, thinking ${thinking}.`);
      const output = await scope.capture([command("go"), "test", "-count=1", "-v", "-tags=ai_eval", "-timeout=20m", "./tests/aieval"], {
        cwd: join(ROOT, "backend"), env: { ...process.env, AI_EVAL_ENDPOINT: endpoint, AI_EVAL_MODEL: options.model, AI_EVAL_THINKING: thinking },
      }, 21 * 60 * 1000);
      const cases: unknown[] = [], diagnostics: unknown[] = [];
      for (const line of output.stdout.split(/\r?\n/)) {
        if (line.startsWith("AI_EVAL ")) cases.push(JSON.parse(line.slice(8)));
        else if (line.startsWith('{"time":') && line.includes('"msg":"ai_inference"')) diagnostics.push(JSON.parse(line));
      }
      const passed = output.code === 0 && cases.length === 6;
      failed ||= !passed;
      results.push({ endpoint: index + 1, thinking, passed, cases, diagnostics });
      await save(); console.log(`${passed ? "Passed" : "Failed"}: ${cases.length} cases recorded.`);
      if (!cases.length) console.error("No evaluation results were produced. Compile the ai_eval test package to check toolchain errors.");
    }
  }
  console.log(`Comparison report: ${options.output}`);
  return failed ? 1 : 0;
}

if (import.meta.main) await runCLI(scope => runAIComparison(scope, parseAIComparison(process.argv.slice(2))), { timeoutMs: 60 * 60 * 1000 });
