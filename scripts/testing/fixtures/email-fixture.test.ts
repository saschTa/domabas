import { describe, expect, test } from "bun:test";
import { join, resolve } from "node:path";
import { emailFixtureEnvironment, parseEmailFixture } from "./email-fixture.ts";

const directory = resolve("fixture-owned-directory");
const fixture = {
  host: "127.0.0.1", port: 19993, caFile: join(directory, "ca.pem"),
  username: "test-user", password: "fixture-only-password", mailbox: "INBOX", messageCount: 1,
};

describe("email fixture isolation", () => {
  test("rejects external endpoints and CA paths without reflecting credentials", () => {
    for (const value of [
      { ...fixture, host: "mail.example.com" },
      { ...fixture, port: 0 },
      { ...fixture, caFile: resolve("foreign-ca.pem") },
      { ...fixture, caFile: directory },
      { ...fixture, password: "fixture-secret\ninvalid" },
    ]) {
      try {
        parseEmailFixture(value, directory);
        throw new Error("Unexpected fixture acceptance");
      } catch (error) {
        expect(String(error)).not.toContain("fixture-secret");
        expect(String(error)).not.toContain("Unexpected fixture acceptance");
      }
    }
  });

  test("accepts an owned loopback fixture", () => {
    expect(parseEmailFixture(fixture, directory)).toEqual(fixture);
  });

  test("isolates backend key and TLS settings without mutating ambient overrides", () => {
    const ambient = { EMAIL_CREDENTIAL_KEYS: "deployment-secret", EMAIL_CREDENTIAL_ACTIVE_KEY_ID: "deployment", EMAIL_CREDENTIAL_KEY_FILE: "deployment.key", DATABASE_URL: "owned-schema" };
    const first = emailFixtureEnvironment(ambient, fixture);
    expect(ambient.EMAIL_CREDENTIAL_KEYS).toBe("deployment-secret");
    expect(first.DATABASE_URL).toBe("owned-schema");
    expect(first.EMAIL_IMAP_ALLOWED_HOSTS).toBe("127.0.0.1");
    expect(first.EMAIL_IMAP_CA_FILE).toBe(fixture.caFile);
    expect(first.EMAIL_CREDENTIAL_KEYS).toBe("");
    expect(first.EMAIL_CREDENTIAL_ACTIVE_KEY_ID).toBe("");
    expect(first.EMAIL_CREDENTIAL_KEY_FILE).toBe(join(directory, "email.key"));
    expect(ambient.EMAIL_CREDENTIAL_KEY_FILE).toBe("deployment.key");
  });
});
