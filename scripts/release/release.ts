import { chmod, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { scanImage } from "../security/scan-image.ts";
import { type Environment, ROOT, ProcessScope, command, required, runCLI } from "../shared/runtime.ts";

export const RELEASE_IMAGES = [
  { name: "backend", dockerfile: "backend/Dockerfile", services: ["backend"] },
  { name: "web", dockerfile: "frontend/Dockerfile", services: ["web"] },
  { name: "document-processor", dockerfile: "infra/document-processor/Dockerfile", services: ["document-processor"] },
  { name: "init", dockerfile: "infra/init/Dockerfile", services: ["database-init", "temporal-schema", "temporal-init"] },
] as const;

export interface ReleaseConfiguration { repository: string; sha: string; bump: ReleaseBump }
export interface ReleaseImage { name: string; tag: string; reference: string; platform: "linux/amd64" }
export interface GitHubRelease { id: number; draft: boolean; tag_name: string; target_commitish: string; html_url: string }
interface GitHubTag { name: string; commit: { sha: string } }
type ReleaseRequest = (url: string, options: RequestInit) => Promise<Response>;
export type ReleaseBump = "patch" | "minor" | "major";

export function releaseConfiguration(env: Environment): ReleaseConfiguration {
  if (env.GITHUB_EVENT_NAME !== "workflow_dispatch" || env.GITHUB_REF !== "refs/heads/main") throw new Error("Releases require a manual workflow dispatch on main.");
  if (env.GITHUB_SERVER_URL !== "https://github.com" || env.GITHUB_API_URL !== "https://api.github.com") throw new Error("Releases require GitHub.com.");
  const sha = required(env, "GITHUB_SHA"), repository = required(env, "GITHUB_REPOSITORY");
  if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error("Release requires the exact event commit SHA.");
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) throw new Error("Invalid GitHub repository.");
  const bump = env.RELEASE_BUMP;
  if (bump !== "patch" && bump !== "minor" && bump !== "major") throw new Error("Release requires RELEASE_BUMP to be patch, minor or major.");
  return { repository, sha, bump };
}

function versionParts(tag: string): number[] | undefined {
  if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag)) return;
  const parts = tag.slice(1).split(".").map(Number);
  if (parts.some(part => !Number.isSafeInteger(part))) throw new Error("Release version exceeds safe integer limits.");
  return parts;
}

export function nextReleaseVersion(tags: string[], bump: ReleaseBump): string {
  const versions = tags.map(versionParts).filter((version): version is number[] => !!version);
  versions.sort((a, b) => b[0]! - a[0]! || b[1]! - a[1]! || b[2]! - a[2]!);
  const [major, minor, patch] = versions[0] ?? [0, 0, 0];
  const parts = bump === "major" ? [major! + 1, 0, 0] : bump === "minor" ? [major!, minor! + 1, 0] : [major!, minor!, patch! + 1];
  if (parts.some(part => !Number.isSafeInteger(part))) throw new Error("Release version exceeds safe integer limits.");
  return `v${parts.join(".")}`;
}

export class GitHubReleaseClient {
  constructor(private readonly config: ReleaseConfiguration, private readonly token: string, private readonly request: ReleaseRequest = fetch) {}

  private async api(path: string, method = "GET", body?: unknown): Promise<Response> {
    const response = await this.request(`https://api.github.com/repos/${this.config.repository}${path}`, {
      method, redirect: "error", headers: { authorization: `Bearer ${this.token}`, accept: "application/vnd.github+json", "content-type": "application/json", "X-GitHub-Api-Version": "2022-11-28" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok && !(method === "GET" && response.status === 404)) throw new Error(`GitHub ${method} ${path} returned HTTP ${response.status}. Check workflow permissions and repository rules.`);
    return response;
  }

  private async list<T>(path: string): Promise<T[]> {
    const output: T[] = [];
    for (let page = 1; ; page++) {
      const response = await this.api(`${path}?per_page=100&page=${page}`);
      if (response.status === 404) throw new Error(`GitHub could not list ${path}.`);
      const values = await response.json() as T[];
      output.push(...values);
      if (values.length < 100) return output;
    }
  }

  async verifyTag(version: string): Promise<void> {
    const response = await this.api(`/git/ref/tags/${version}`);
    const tag = response.status === 404 ? undefined : await response.json() as { object: { type: string; sha: string } };
    if (tag?.object.type !== "commit" || tag.object.sha !== this.config.sha) throw new Error("Release tag does not point directly to this exact commit; refusing to publish.");
  }

  async prepare(): Promise<GitHubRelease> {
    const tags = await this.list<GitHubTag>("/tags");
    const matching = tags.filter(tag => versionParts(tag.name) && tag.commit.sha === this.config.sha);
    if (matching.length > 1) throw new Error("Multiple release versions point to this commit; resolve the ambiguity first.");
    let version = matching[0]?.name;
    const releases = await this.list<GitHubRelease>("/releases");
    const previous = releases.filter(release => release.target_commitish === this.config.sha && versionParts(release.tag_name));
    if (previous.length > 1 || previous[0] && previous[0].tag_name !== version) throw new Error("Existing release tag changed or was removed; refusing to create another version.");
    if (!version) {
      version = nextReleaseVersion([...tags.map(tag => tag.name), ...releases.map(release => release.tag_name)], this.config.bump);
      await this.api("/git/refs", "POST", { ref: `refs/tags/${version}`, sha: this.config.sha });
    }
    await this.verifyTag(version);
    const existing = releases.find(release => release.tag_name === version);
    if (existing) {
      if (existing.target_commitish !== this.config.sha) throw new Error("Existing release does not belong to this exact commit.");
      return existing;
    }
    return await (await this.api("/releases", "POST", { tag_name: version, target_commitish: this.config.sha, name: `Domabas ${version}`, draft: true, prerelease: version.startsWith("v0.") })).json() as GitHubRelease;
  }

  async publish(release: GitHubRelease, body: string): Promise<void> {
    await this.verifyTag(release.tag_name);
    await this.api(`/releases/${release.id}`, "PATCH", { body, draft: false, make_latest: "false" });
  }
}

export function releaseCompose(source: string, images: readonly ReleaseImage[]): string {
  const document = Bun.YAML.parse(source) as { name: string; services: Record<string, { build?: unknown; image?: string; platform?: string }> } & Record<string, unknown>;
  for (const definition of RELEASE_IMAGES) {
    const image = images.find(image => image.name === definition.name);
    if (!image || !/@sha256:[a-f0-9]{64}$/.test(image.reference)) throw new Error(`Missing published image digest for ${definition.name}.`);
    for (const service of definition.services) {
      if (!document.services[service]?.build) throw new Error(`Missing build definition for ${service}.`);
      delete document.services[service]!.build;
      document.services[service]!.image = image.reference;
      document.services[service]!.platform = image.platform;
    }
  }
  for (const key of Object.keys(document)) if (key.startsWith("x-")) delete document[key];
  if (Object.values(document.services).some(service => service.build)) throw new Error("Release Compose still contains an unpublished build.");
  return Bun.YAML.stringify(document);
}

export async function publishRelease(config: ReleaseConfiguration, client: GitHubReleaseClient, buildImages: (version: string) => Promise<ReleaseImage[]>, source: string): Promise<string> {
  const release = await client.prepare();
  if (!release.draft) return release.html_url;
  const images = await buildImages(release.tag_name);
  for (const image of images) {
    const repository = `ghcr.io/${config.repository.toLowerCase()}-${image.name}`;
    if (image.tag !== `${repository}:${release.tag_name}` || !image.reference.startsWith(`${repository}@sha256:`)) throw new Error("Built image does not belong to this release.");
  }
  const compose = releaseCompose(source, images);
  const notes = [
    `Built from [${config.sha.slice(0, 12)}](https://github.com/${config.repository}/commit/${config.sha}). Required checks: task check, PostgreSQL integration, database generation consistency, OSV dependency scanning and Trivy image scanning. Both vulnerability gates block critical findings.`,
    "Containers target linux/amd64. The web image contains Flutter web; native apps are not distributed. Versions below 1.0.0 are previews. Temporal, browser E2E, live-model and complete Compose smoke tests are separate local validation, not guarantees of this release.",
    "Version tags are immutable after publication. Failed builds remain drafts; retry the same workflow run to reuse its version. No floating latest image tag is published.",
    ["| Image | Version | Immutable image |", "| --- | --- | --- |", ...images.map(image => `| ${image.name} | \`${image.tag}\` | \`${image.reference}\` |`)].join("\n"),
    ["```sh", ...images.map(image => `docker pull ${image.tag}`), "```"].join("\n"),
    "Save the configuration below as compose.yaml and run `docker compose up --wait`. Set deployment passwords and bind addresses first. Public GHCR packages support anonymous pulls; private packages require authentication. Ordinary shutdown retains database, file and model volumes.",
    `<details>\n<summary>Compose deployment pinned to published image digests</summary>\n\n\`\`\`yaml\n${compose}\n\`\`\`\n</details>`,
  ].join("\n\n");
  await client.publish(release, notes);
  return release.html_url;
}

export interface ReleaseImageOperations {
  build(definition: typeof RELEASE_IMAGES[number], tag: string): Promise<string>;
  scan(imageID: string, name: string): Promise<void>;
  push(tag: string, imageID: string): Promise<string>;
}

export async function publishScannedImages(config: ReleaseConfiguration, version: string, operations: ReleaseImageOperations): Promise<ReleaseImage[]> {
  const candidates: { name: string; tag: string; repository: string; imageID: string }[] = [];
  for (const definition of RELEASE_IMAGES) {
    const repository = `ghcr.io/${config.repository.toLowerCase()}-${definition.name}`;
    const tag = `${repository}:${version}`;
    const imageID = await operations.build(definition, tag);
    if (!/^sha256:[a-f0-9]{64}$/.test(imageID)) throw new Error(`Missing local image ID for ${definition.name}.`);
    await operations.scan(imageID, definition.name);
    candidates.push({ name: definition.name, tag, repository, imageID });
  }
  const images: ReleaseImage[] = [];
  for (const candidate of candidates) {
    const reference = await operations.push(candidate.tag, candidate.imageID);
    if (!reference.startsWith(`${candidate.repository}@sha256:`) || !/@sha256:[a-f0-9]{64}$/.test(reference)) throw new Error(`Missing published image digest for ${candidate.name}.`);
    images.push({ name: candidate.name, tag: candidate.tag, reference, platform: "linux/amd64" });
  }
  return images;
}

export async function buildReleaseImages(scope: ProcessScope, config: ReleaseConfiguration, version: string, env: Environment, directory: string): Promise<ReleaseImage[]> {
  const docker = command("docker");
  const inspectID = async (tag: string): Promise<string> => {
    const result = await scope.capture([docker, "image", "inspect", "--format", "{{.Id}}", tag], { env });
    if (result.code) throw new Error("Could not inspect the local release image.");
    return result.stdout.trim();
  };
  return await publishScannedImages(config, version, {
    build: async (definition, tag) => {
      const metadata = join(directory, `${definition.name}.json`);
      await scope.run([docker, "buildx", "build", "--platform", "linux/amd64", "--load",
        "--label", `org.opencontainers.image.source=https://github.com/${config.repository}`,
        "--label", `org.opencontainers.image.revision=${config.sha}`, "--label", `org.opencontainers.image.version=${version}`,
        "--label", "org.opencontainers.image.licenses=MIT", "--metadata-file", metadata,
        "--file", definition.dockerfile, "--tag", tag, "."], { env });
      const result = await Bun.file(metadata).json() as Record<string, string>;
      const imageID = await inspectID(tag);
      if (result["containerimage.config.digest"] !== imageID) throw new Error("Loaded image does not match the build output.");
      return imageID;
    },
    scan: async (imageID, name) => { await scanImage(scope, imageID, name, env); },
    push: async (tag, imageID) => {
      if (await inspectID(tag) !== imageID) throw new Error("Release image changed after scanning; refusing to push.");
      await scope.run([docker, "push", tag], { env });
      const result = await scope.capture([docker, "image", "inspect", "--format", "{{json .RepoDigests}}", tag], { env });
      if (result.code || await inspectID(tag) !== imageID) throw new Error("Could not verify the pushed release image.");
      const references = JSON.parse(result.stdout) as string[];
      const repository = tag.slice(0, tag.lastIndexOf(":"));
      const matching = references.filter(reference => reference.startsWith(`${repository}@sha256:`));
      if (matching.length !== 1) throw new Error("Registry did not return a unique release image digest.");
      return matching[0]!;
    },
  });
}

if (import.meta.main) await runCLI(async scope => {
  const config = releaseConfiguration(process.env);
  const git = await scope.capture([command("git"), "rev-parse", "HEAD"]);
  if (git.code || git.stdout.trim() !== config.sha) throw new Error("Checkout does not match the release commit.");
  await scope.run([command("bun"), "--no-env-file", "scripts/generation/generate-licenses.ts", "--check"]);
  const token = required(process.env, "GITHUB_TOKEN"), actor = required(process.env, "GITHUB_ACTOR");
  const dockerConfig = join(required(process.env, "DOCKER_CONFIG"), "config.json");
  const original = await Bun.file(dockerConfig).exists() ? await readFile(dockerConfig, "utf8") : undefined;
  const settings = JSON.parse(original ?? "{}") as { auths?: Record<string, { auth: string }> };
  settings.auths = { ...settings.auths, "ghcr.io": { auth: Buffer.from(`${actor}:${token}`).toString("base64") } };
  const directory = await mkdtemp(join(tmpdir(), "domabas-release-"));
  await chmod(directory, 0o700);
  const env = { ...process.env };
  delete env.GITHUB_TOKEN;
  try {
    await Bun.write(dockerConfig, JSON.stringify(settings));
    await chmod(dockerConfig, 0o600);
    const client = new GitHubReleaseClient(config, token, (url, options) => fetch(url, { ...options, signal: AbortSignal.any([scope.signal, AbortSignal.timeout(120000)]) }));
    const url = await publishRelease(config, client, version => buildReleaseImages(scope, config, version, env, directory), await Bun.file(join(ROOT, "compose.yaml")).text());
    console.log(`Published ${url}`);
  } finally {
    try {
      if (original === undefined) await rm(dockerConfig, { force: true });
      else await Bun.write(dockerConfig, original);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
}, { timeoutMs: 50 * 60 * 1000 });
