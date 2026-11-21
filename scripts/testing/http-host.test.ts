import { expect, test } from "bun:test";
import { hostValue } from "./e2e.ts";

test("HTTP browser tests accept loopback and LAN hosts", () => {
  expect(hostValue(undefined)).toBe("127.0.0.1");
  expect(hostValue("10.0.0.2")).toBe("10.0.0.2");
  for (const host of ["", "0.0.0.0", "http://10.0.0.2", "10.0.0.2:8080", "invalid"]) {
    expect(() => hostValue(host)).toThrow("reachable IPv4 address");
  }
});
