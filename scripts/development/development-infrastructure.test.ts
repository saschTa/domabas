import { expect, test } from "bun:test";
import { join } from "node:path";
import { ROOT } from "../shared/runtime.ts";
import { developmentComposeOverrides } from "./development-infrastructure.ts";

test("CPU is the default and Vulkan selects the matching Compose override", () => {
  expect(developmentComposeOverrides({})).toEqual([]);
  expect(developmentComposeOverrides({ EMBEDDING_RUNTIME: "cpu" })).toEqual([]);
  expect(developmentComposeOverrides({ EMBEDDING_RUNTIME: "vulkan" })).toEqual([join(ROOT, "compose.vulkan.yaml")]);
  expect(() => developmentComposeOverrides({ EMBEDDING_RUNTIME: "unknown" })).toThrow("EMBEDDING_RUNTIME");
});
