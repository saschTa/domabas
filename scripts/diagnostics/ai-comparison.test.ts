import { expect, test } from "bun:test";
import { parseAIComparison } from "./ai-comparison.ts";

test("requires explicit external API bases and model and defaults to thinking off", () => {
  expect(() => parseAIComparison([])).toThrow("endpoint");
  expect(() => parseAIComparison(["--endpoint=http://localhost/v1"])).toThrow("model");
  expect(() => parseAIComparison(["--endpoint=http://user:secret@localhost/v1", "--model=sample"])).toThrow();
  const options = parseAIComparison(["--endpoint=http://localhost:1234/v1/", "--model=sample"]);
  expect(options.endpoints).toEqual(["http://localhost:1234/v1"]);
  expect(options.modes).toEqual(["off"]);
});
