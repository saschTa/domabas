import { extname } from "node:path";
import { parseArgs } from "node:util";

export function normalizeGeneratedComments(source: string, language: "go" | "dart"): string {
  const lines = source.split("\n").filter(line => {
    const comment = /^\s*\/\/(.*)$/.exec(line)?.[1]?.trim();
    if (comment === undefined) return true;
    return /^(go:|line\s|@dart\s*=|ignore(?:_for_file)?:|Code generated\b|AUTO-GENERATED FILE\b)/.test(comment);
  });
  const result = lines.join("\n");
  if ((language === "dart" && /'''|"""/.test(result)) ||
      (language === "go" && lines.some(line => (line.match(/`/g)?.length ?? 0) % 2 !== 0))) {
    throw new Error("Generated comment cleanup needs review: unsupported multiline string syntax.");
  }
  return result.replace(/[\t ]+$/gm, "").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

export async function normalizeGeneratedFile(path: string): Promise<void> {
  const extension = extname(path);
  if (extension !== ".go" && extension !== ".dart") throw new Error("Expected a generated Go or Dart source file.");
  const source = await Bun.file(path).text();
  const normalized = normalizeGeneratedComments(source, extension === ".go" ? "go" : "dart");
  if (normalized !== source) await Bun.write(path, normalized);
}

if (import.meta.main) {
  const { positionals } = parseArgs({ args: Bun.argv.slice(2), allowPositionals: true });
  if (!positionals.length) throw new Error("Usage: bun scripts/generation/generated-comments.ts <generated.go|generated.dart> [...]");
  for (const path of positionals) await normalizeGeneratedFile(path);
}
