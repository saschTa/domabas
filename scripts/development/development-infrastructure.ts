import { join } from "node:path";
import { ROOT, type Environment } from "../shared/runtime.ts";

export function developmentComposeOverrides(env: Environment): string[] {
  const runtime = env.EMBEDDING_RUNTIME ?? "cpu";
  if (runtime === "cpu") return [];
  if (runtime === "vulkan") return [join(ROOT, "compose.vulkan.yaml")];
  throw new Error("EMBEDDING_RUNTIME must be cpu or vulkan.");
}
