import { parseArgs } from "node:util";
import { command, runCLI } from "../shared/runtime.ts";

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: { "containers-only": { type: "boolean", default: false }, "tests-only": { type: "boolean", default: false } } });
  if (process.platform !== "linux") throw new Error("CI prerequisites require Linux.");
  const prefix = process.getuid?.() === 0 ? [] : [command("sudo"), "-n"];
  const apt = command("apt-get");
  const env = { ...process.env, DEBIAN_FRONTEND: "noninteractive" };
  await scope.run([...prefix, apt, "-o", "Acquire::Retries=3", "update"], { env });
  await scope.run([...prefix, apt, "-o", "Acquire::Retries=3", "install", "-y", "--no-install-recommends",
    "procps",
    ...(values["tests-only"] ? [] : ["libgtk-3-0t64", "libasound2t64", "libnss3", "libatk-bridge2.0-0t64", "libcups2t64", "libxcomposite1",
      "libxdamage1", "libxrandr2", "libgbm1", "libxkbcommon0"]),
    ...(values["containers-only"] ? [] : ["unzip", "xz-utils"]),
    ...(values["containers-only"] || values["tests-only"] ? [] : ["postgresql-client", "poppler-utils"]),
    ...(values["containers-only"] || values["tests-only"] ? [] : ["clang", "cmake", "ninja-build", "pkg-config", "libgtk-3-dev", "libsecret-1-dev", "libstdc++-14-dev", "libglu1-mesa"])], { env });
  if (!values["containers-only"] && !values["tests-only"]) await scope.run([command("java"), "-version"]);
  if (!values["tests-only"]) await scope.run([command("docker"), "compose", "version"]);
});
