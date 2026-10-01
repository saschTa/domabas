import { expect, test } from "bun:test";
import { hostValue } from "./e2e.ts";

test("HTTP browser tests accept loopback and LAN hosts", () => {
  expect(hostValue(undefined)).toBe("127.0.0.1");
  expect(hostValue("192.168.0.230")).toBe("192.168.0.230");
  for (const host of ["", "0.0.0.0", "http://192.168.0.230", "192.168.0.230:8080", "invalid"]) {
    expect(() => hostValue(host)).toThrow("reachable IPv4 address");
  }
});
