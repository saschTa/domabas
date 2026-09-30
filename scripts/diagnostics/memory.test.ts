import { describe, expect, test } from "bun:test";
import { parseContainerMemory, positiveSeconds } from "./memory.ts";

describe("memory evidence", () => {
  test("keeps tmpfs within file memory and subtracts only inactive file cache", () => {
    const result = parseContainerMemory("1000\n1500\n2048\nanon 400\nfile 500\nshmem 300\ninactive_file 200\noom 2\noom_kill 1\n");
    expect(result).toEqual({ currentBytes: 1000, peakBytes: 1500, limitBytes: 2048, workingSetBytes: 800, anonymousBytes: 400, fileBytes: 500, sharedBytes: 300, oom: 2, oomKills: 1 });
  });
  test("reports unlimited memory without inventing a limit", () => {
    expect(parseContainerMemory("100\n100\nmax\nanon 20\nfile 80\nshmem 0\ninactive_file 105\noom 0\noom_kill 0").limitBytes).toBeNull();
    expect(parseContainerMemory("100\n100\nmax\nanon 20\nfile 80\nshmem 0\ninactive_file 105\noom 0\noom_kill 0").workingSetBytes).toBe(100);
  });
  test("rejects unavailable or malformed counters instead of reporting zero usage", () => {
    for (const output of ["", "max\n0\nmax", "100\n100\nmax\nanon bad", "100\n100\nmax\nanon 20"]) expect(() => parseContainerMemory(output)).toThrow();
  });
  test("bounds measurement time", () => {
    expect(positiveSeconds("900", 86400)).toBe(900);
    for (const value of ["0", "-1", "1.5", "NaN", "86401"]) expect(() => positiveSeconds(value, 86400)).toThrow();
  });
});
