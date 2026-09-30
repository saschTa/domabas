import { join } from "node:path";
import { parseArgs } from "node:util";
import { install } from "./browser-tools.ts";
import { ROOT, ProcessScope, command, environment, runCLI } from "../../shared/runtime.ts";

export const browserTestGroups = {
  realtime: ["test/realtime_frame_independent_test.dart", "test/realtime_transport_independent_test.dart", "test/realtime_browser_independent_test.dart"],
  scanner: ["test/unit/scanner_validation_independent_test.dart", "test/scanner_images_browser_independent_test.dart"],
  document: ["test/document_vocabulary_transport_independent_test.dart", "test/document_rendering_browser_independent_test.dart"],
  upload: ["test/document_upload_transport_test.dart", "test/document_upload_acquisition_browser_test.dart"],
} as const;

export async function runBrowserTests(scope: ProcessScope, group?: keyof typeof browserTestGroups, skipPub = false): Promise<void> {
  const chrome = process.env.CHROME_EXECUTABLE ?? (await install(scope.signal)).chrome;
  const files = group ? browserTestGroups[group] : ["test/browser_suite.dart"];
  await scope.run([
    command("flutter"), "test", ...(skipPub ? ["--no-pub"] : []), "--platform", "chrome", "--reporter=expanded", ...files,
  ], { cwd: join(ROOT, "frontend"), env: environment({ ...process.env, CHROME_EXECUTABLE: chrome }) }, group ? 180000 : 360000);
}

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: { "skip-pub": { type: "boolean", default: false } } });
  await runBrowserTests(scope, undefined, values["skip-pub"]);
});
