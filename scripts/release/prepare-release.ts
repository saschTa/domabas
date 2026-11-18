import { appendFile } from "node:fs/promises";
import { command, required, runCLI } from "../shared/runtime.ts";
import { GitHubReleaseClient, releaseConfiguration } from "./release.ts";

export async function prepareRelease(client: GitHubReleaseClient): Promise<{ version: string; publish: boolean }> {
  await client.verifyMainCI();
  const release = await client.prepare();
  return { version: release.tag_name, publish: release.draft };
}

if (import.meta.main) await runCLI(async scope => {
  const config = releaseConfiguration(process.env);
  const git = await scope.capture([command("git"), "rev-parse", "HEAD"]);
  if (git.code || git.stdout.trim() !== config.sha) throw new Error("Checkout does not match the release commit.");
  const client = new GitHubReleaseClient(config, required(process.env, "GITHUB_TOKEN"), (url, options) => fetch(url, { ...options, signal: AbortSignal.any([scope.signal, AbortSignal.timeout(120000)]) }));
  const result = await prepareRelease(client);
  await appendFile(required(process.env, "GITHUB_OUTPUT"), `version=${result.version}\npublish=${result.publish}\n`);
  console.log(`${result.publish ? "Prepared draft" : "Already published"} ${result.version}`);
});
