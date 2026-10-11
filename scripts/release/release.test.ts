import { describe, expect, test } from "bun:test";
import { GitHubReleaseClient, RELEASE_IMAGES, nextReleaseVersion, publishRelease, publishScannedImages, releaseCompose, releaseConfiguration, type GitHubRelease, type ReleaseBump, type ReleaseImage } from "./release.ts";
import { ROOT } from "../shared/runtime.ts";
import { FLUTTER_SHA256, FLUTTER_VERSION } from "../ci/setup-flutter.ts";

const env = { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: "refs/heads/main", GITHUB_SHA: "a".repeat(40), GITHUB_REPOSITORY: "Example-Owner/Domabas", GITHUB_SERVER_URL: "https://github.com", GITHUB_API_URL: "https://api.github.com", RELEASE_BUMP: "patch" };
const config = releaseConfiguration(env);
const source = await Bun.file(`${ROOT}/compose.yaml`).text();
const images = (version: string): ReleaseImage[] => RELEASE_IMAGES.map(image => ({ name: image.name, tag: `ghcr.io/example-owner/domabas-${image.name}:${version}`, reference: `ghcr.io/example-owner/domabas-${image.name}@sha256:${"b".repeat(64)}`, platform: "linux/amd64" }));

describe("release versions and triggers", () => {
  test("starts at 0.0.1 and increments semantic versions numerically", () => {
    expect(nextReleaseVersion([], "patch")).toBe("v0.0.1");
    expect(nextReleaseVersion(["v0.0.9", "v0.0.10", "v0.0.2", "v8.0.0-rc.1", "other"], "patch")).toBe("v0.0.11");
    expect(nextReleaseVersion(["v0.3.7"], "minor")).toBe("v0.4.0");
    expect(nextReleaseVersion(["v0.3.7"], "major")).toBe("v1.0.0");
    expect(nextReleaseVersion(["v1.2.3", "v0.99.99"], "patch")).toBe("v1.2.4");
    expect(() => nextReleaseVersion(["v1.2.9007199254740991"], "patch")).toThrow("safe integer");
  });
  test("requires an explicit valid version increment from the manual input", () => {
    for (const bump of ["patch", "minor", "major"] as const) expect(releaseConfiguration({ ...env, RELEASE_BUMP: bump }).bump).toBe(bump);
    for (const bump of [undefined, "", "latest", "MINOR"]) expect(() => releaseConfiguration({ ...env, RELEASE_BUMP: bump })).toThrow("RELEASE_BUMP");
  });
  test("rejects automatic events, non-main refs, credentials in URLs and invalid commits", () => {
    for (const change of [{ GITHUB_REF: "refs/tags/v0.0.1" }, { GITHUB_EVENT_NAME: "pull_request" }, { GITHUB_EVENT_NAME: "push" }, { GITHUB_EVENT_NAME: "schedule" }, { GITHUB_REF: "refs/heads/feature" }]) {
      expect(() => releaseConfiguration({ ...env, ...change })).toThrow("manual workflow dispatch on main");
    }
    expect(() => releaseConfiguration({ ...env, GITHUB_SHA: "main" })).toThrow("exact event commit");
    expect(() => releaseConfiguration({ ...env, GITHUB_API_URL: "https://secret@example.test" })).toThrow("GitHub.com");
    expect(() => releaseConfiguration({ ...env, GITHUB_REPOSITORY: "../other/path" })).toThrow("repository");
  });
});

describe("release deployment", () => {
  test("every first-party service uses a published digest and no build remains", () => {
    const output = releaseCompose(source, images("v0.0.1"));
    const compose = Bun.YAML.parse(output) as { services: Record<string, { build?: unknown; image?: string; ports?: string[] }> };
    expect(Object.values(compose.services).every(service => !service.build)).toBe(true);
    for (const definition of RELEASE_IMAGES) for (const service of definition.services) {
      expect(compose.services[service]!.image).toBe(images("v0.0.1").find(image => image.name === definition.name)!.reference);
    }
    expect(compose.services.postgres!.image).toContain("pgvector/pgvector:0.8.6-pg18-trixie@sha256:");
    expect(compose.services.web!.ports).toContain("${BIND_ADDRESS:-127.0.0.1}:${WEB_PORT:-8088}:8080");
    expect(output).toContain("postgres_data:");
    expect(output).not.toContain("dockerfile:");
  });
  test("fails for incomplete images and unrecognized builds", () => {
    expect(() => releaseCompose(source, images("v0.0.1").slice(1))).toThrow("Missing published image");
    const invalid = images("v0.0.1"); invalid[0]!.reference = invalid[0]!.tag;
    expect(() => releaseCompose(source, invalid)).toThrow("digest");
    const compose = Bun.YAML.parse(source) as { services: Record<string, unknown> };
    compose.services.future = { build: "." };
    expect(() => releaseCompose(Bun.YAML.stringify(compose), images("v0.0.1"))).toThrow("unpublished build");
  });
  test("container and CI Flutter pins agree", async () => {
    const dockerfile = await Bun.file(`${ROOT}/frontend/Dockerfile`).text();
    expect(dockerfile).toContain(`FLUTTER_VERSION=${FLUTTER_VERSION}`);
    expect(dockerfile).toContain(`FLUTTER_SHA256=${FLUTTER_SHA256}`);
  });
});

function fakeGitHub(options: { tags?: { name: string; commit: { sha: string } }[]; releases?: GitHubRelease[]; bump?: ReleaseBump; forbidden?: boolean; failDraft?: boolean } = {}) {
  const calls: { method: string; path: string; body?: any }[] = [];
  const tags = [...options.tags ?? []], releases = [...options.releases ?? []];
  let nextDraftFails = options.failDraft;
  const releaseConfig = { ...config, bump: options.bump ?? config.bump };
  const client = new GitHubReleaseClient(releaseConfig, "test-token", async (url, init) => {
    const path = new URL(url).pathname.replace(`/repos/${config.repository}`, "");
    const method = init.method ?? "GET", body = init.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ method, path: path + new URL(url).search, body });
    if (options.forbidden) return new Response("sensitive server response", { status: 403 });
    const paginated = (items: unknown[]) => { const page = Number(new URL(url).searchParams.get("page")); return Response.json(items.slice((page - 1) * 100, page * 100)); };
    if (method === "GET" && path === "/tags") return paginated(tags);
    if (method === "GET" && path === "/releases") return paginated(releases);
    if (method === "GET" && path.startsWith("/git/ref/tags/")) {
      const tag = tags.find(tag => path.endsWith(`/${tag.name}`));
      return tag ? Response.json({ object: { type: "commit", sha: tag.commit.sha } }) : new Response(null, { status: 404 });
    }
    if (method === "POST" && path === "/git/refs") {
      const name = body.ref.replace("refs/tags/", "");
      if (tags.some(tag => tag.name === name)) return new Response(null, { status: 422 });
      tags.push({ name, commit: { sha: body.sha } }); return Response.json({});
    }
    if (method === "POST" && path === "/releases") {
      if (nextDraftFails) { nextDraftFails = false; return new Response(null, { status: 500 }); }
      const release = { ...body, id: 1, html_url: `https://github.com/${config.repository}/releases/tag/${body.tag_name}` };
      releases.push(release); return Response.json(release);
    }
    if (method === "PATCH") { Object.assign(releases.find(release => path === `/releases/${release.id}`)!, body); return Response.json({}); }
    throw new Error(`Unexpected ${method} ${path}`);
  });
  return { client, calls, tags, releases, releaseConfig };
}

const reservedTag = { name: "v0.0.1", commit: { sha: config.sha } };
const draft: GitHubRelease = { id: 1, draft: true, tag_name: "v0.0.1", target_commitish: config.sha, html_url: "https://github.com/example-owner/domabas/releases/tag/v0.0.1" };

describe("GitHub publication and recovery", () => {
  test("reserves the exact commit and publishes only after all images succeed", async () => {
    const fake = fakeGitHub();
    await publishRelease(config, fake.client, async version => {
      expect(fake.releases[0]!.draft).toBe(true);
      expect(fake.tags[0]).toEqual(reservedTag);
      return images(version);
    }, source);
    expect(fake.releases[0]!.draft).toBe(false);
    const body = fake.calls.find(call => call.method === "PATCH")!.body;
    expect(body.body).toContain("ghcr.io/example-owner/domabas-web:v0.0.1");
    expect(body.body).toContain("@sha256:");
    expect(body.body).not.toContain("android.apk");
    expect(body.make_latest).toBe("false");
    expect(fake.calls.find(call => call.method === "POST" && call.path === "/releases")!.body.prerelease).toBe(true);
  });
  test("published retries perform no builds or mutations", async () => {
    const fake = fakeGitHub({ tags: [reservedTag], releases: [{ ...draft, draft: false }] });
    await publishRelease(config, fake.client, async () => { throw new Error("must not build"); }, source);
    expect(fake.calls.every(call => call.method === "GET")).toBe(true);
  });
  test("a failed build remains a draft and a retry ignores a different bump and later versions", async () => {
    const fake = fakeGitHub();
    await expect(publishRelease(config, fake.client, async () => { throw new Error("build failed"); }, source)).rejects.toThrow("build failed");
    expect(fake.releases[0]!.draft).toBe(true);
    fake.tags.push({ name: "v0.0.2", commit: { sha: "c".repeat(40) } });
    fake.releaseConfig.bump = "major";
    await publishRelease(config, fake.client, async version => { expect(version).toBe("v0.0.1"); return images(version); }, source);
    expect(fake.calls.filter(call => call.method === "POST" && call.path === "/git/refs")).toHaveLength(1);
  });
  test("recovers a tag reservation after draft creation failed", async () => {
    const fake = fakeGitHub({ failDraft: true });
    await expect(fake.client.prepare()).rejects.toThrow("HTTP 500");
    expect(fake.tags).toEqual([reservedTag]);
    const release = await fake.client.prepare();
    expect(release.tag_name).toBe("v0.0.1");
  });
  test("refuses moved or deleted tags, mismatched releases and ambiguous versions", async () => {
    for (const options of [
      { tags: [{ ...reservedTag, commit: { sha: "c".repeat(40) } }], releases: [draft] },
      { releases: [draft] },
      { tags: [reservedTag], releases: [{ ...draft, target_commitish: "c".repeat(40) }] },
      { tags: [reservedTag, { name: "v0.0.2", commit: { sha: config.sha } }] },
    ]) {
      const fake = fakeGitHub(options);
      await expect(publishRelease(config, fake.client, async () => { throw new Error("must not build"); }, source)).rejects.toThrow(/tag|commit|Multiple/);
      expect(fake.calls.every(call => call.method === "GET")).toBe(true);
    }
  });
  test("checks that the reserved tag still matches after builds", async () => {
    const fake = fakeGitHub();
    await expect(publishRelease(config, fake.client, async version => { fake.tags[0]!.commit.sha = "c".repeat(40); return images(version); }, source)).rejects.toThrow("exact commit");
    expect(fake.releases[0]!.draft).toBe(true);
  });
  test("requires all images with the matching version and registry", async () => {
    for (const result of [images("v0.0.1").slice(1), images("v0.0.2")]) {
      const fake = fakeGitHub();
      await expect(publishRelease(config, fake.client, async () => result, source)).rejects.toThrow(/image/);
      expect(fake.releases[0]!.draft).toBe(true);
    }
  });
  test("uses the selected increment for the next version and paginates old tags and releases", async () => {
    const tags = Array.from({ length: 100 }, (_, index) => ({ name: `v0.0.${index + 1}`, commit: { sha: "c".repeat(40) } }));
    tags.push({ name: "v2.0.0", commit: { sha: "c".repeat(40) } });
    const releases = Array.from({ length: 100 }, (_, index) => ({ ...draft, id: index + 2, target_commitish: "c".repeat(40), tag_name: `v0.0.${index + 1}` }));
    const fake = fakeGitHub({ tags, releases, bump: "minor" });
    expect((await fake.client.prepare()).tag_name).toBe("v2.1.0");
    expect(fake.calls.some(call => call.path === "/tags?per_page=100&page=2")).toBe(true);
    expect(fake.calls.some(call => call.path === "/releases?per_page=100&page=2")).toBe(true);
    expect(fake.calls.find(call => call.method === "POST" && call.path === "/releases")!.body.prerelease).toBe(false);
  });
  test("authentication errors reveal neither response bodies nor tokens", async () => {
    await expect(fakeGitHub({ forbidden: true }).client.prepare()).rejects.toThrow("HTTP 403. Check workflow permissions");
  });
});

describe("image scan publication gate", () => {
  function operations(fail?: "build" | "scan" | "push") {
    const calls: string[] = [], ids = new Map<string, string>();
    return { calls, operations: {
      build: async (definition: typeof RELEASE_IMAGES[number], tag: string) => {
        calls.push(`build:${definition.name}`);
        if (fail === "build" && definition.name === "init") throw new Error("build failed");
        const id = `sha256:${String(RELEASE_IMAGES.indexOf(definition) + 1).repeat(64)}`;
        ids.set(tag, id); return id;
      },
      scan: async (id: string, name: string) => {
        calls.push(`scan:${name}`);
        expect([...ids.values()]).toContain(id);
        if (fail === "scan" && name === "init") throw new Error("critical finding or scanner failure");
      },
      push: async (tag: string, id: string) => {
        calls.push(`push:${tag}`);
        expect(ids.get(tag)).toBe(id);
        if (fail === "push") throw new Error("registry unavailable");
        return `${tag.slice(0, tag.lastIndexOf(":"))}@sha256:${"c".repeat(64)}`;
      },
    } };
  }

  test("all four images are built and scanned before the first push, without rebuilding", async () => {
    const fake = operations();
    const result = await publishScannedImages(config, "v0.0.1", fake.operations);
    expect(result).toHaveLength(4);
    expect(fake.calls.slice(0, 8)).toEqual(RELEASE_IMAGES.flatMap(image => [`build:${image.name}`, `scan:${image.name}`]));
    expect(fake.calls.slice(8).every(call => call.startsWith("push:"))).toBe(true);
    expect(fake.calls).toHaveLength(12);
  });

  test("a failure in the final build or scan leaves every image unpushed and release in draft", async () => {
    for (const failure of ["build", "scan"] as const) {
      const fake = operations(failure), github = fakeGitHub();
      await expect(publishRelease(config, github.client, version => publishScannedImages(config, version, fake.operations), source)).rejects.toThrow(/failed|failure/);
      expect(fake.calls.some(call => call.startsWith("push:"))).toBe(false);
      expect(github.releases[0]!.draft).toBe(true);
    }
  });

  test("a registry failure still leaves the GitHub release in draft", async () => {
    const fake = operations("push"), github = fakeGitHub();
    await expect(publishRelease(config, github.client, version => publishScannedImages(config, version, fake.operations), source)).rejects.toThrow("registry unavailable");
    expect(github.releases[0]!.draft).toBe(true);
  });

  test("missing local IDs and registry receipts cannot be advertised", async () => {
    const local = operations(); local.operations.build = async () => "unidentified";
    await expect(publishScannedImages(config, "v0.0.1", local.operations)).rejects.toThrow("local image ID");
    expect(local.calls).toEqual([]);
    const remote = operations(); remote.operations.push = async () => "ghcr.io/another/image@sha256:" + "d".repeat(64);
    await expect(publishScannedImages(config, "v0.0.1", remote.operations)).rejects.toThrow("published image digest");
  });
});
