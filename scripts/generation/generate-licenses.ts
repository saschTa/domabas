import { createHash } from "node:crypto";
import { mkdir, readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT, runCLI, type ProcessScope } from "../shared/runtime.ts";

type Notice = { title: string; textId: string };
type Entry = { id: string; name: string; version: string; component: string; license: string; sourceUrl: string; notices: Notice[] };
export type LicenseCatalog = { schemaVersion: number; inputs: Record<string, string>; texts: Record<string, string>; entries: Entry[] };
type Supplemental = { version: string; files?: string[]; urls?: string[]; note?: string } & (
  { id: string; name: string; component: string; license?: string; sourceUrl: string } |
  { appendTo: string }
);
type GoModule = { Path: string; Version?: string; Dir?: string; Main?: boolean };
const catalogPath = "third_party/licenses/catalog.json";
const assetPath = "frontend/assets/licenses/third-party.json";
const indexPath = "third_party/licenses/INDEX.md";
const digest = (text: string) => createHash("sha256").update(text).digest("hex");
const ordered = <T>(value: Record<string, T>) => Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b, "en")));

export function identifyLicense(text: string): string {
  const found = new Set<string>();
  if (/^\s*GNU AFFERO GENERAL PUBLIC LICENSE\s*\n\s*Version/mi.test(text)) found.add("AGPL (see notices)");
  if (/^\s*GNU (?:LESSER|LIBRARY) GENERAL PUBLIC LICENSE\s*\n\s*Version/mi.test(text)) found.add("LGPL (see notices)");
  if (/^\s*GNU GENERAL PUBLIC LICENSE\s*\n\s*Version 3/mi.test(text)) found.add("GPL-3.0 (see notices)");
  else if (/^\s*GNU GENERAL PUBLIC LICENSE\s*\n\s*Version 2/mi.test(text)) found.add("GPL-2.0 (see notices)");
  text = text.replace(/\s+/g, " ");
  if (/Mozilla Public License[\s,]*(?:Version|version)?\s*2\.0/.test(text)) found.add("MPL-2.0");
  if (/Apache License[\s,]*(?:Version)?\s*2\.0|Licensed under the Apache License, Version 2\.0/i.test(text)) found.add("Apache-2.0");
  if (/Permission is hereby granted, free of charge, to any person obtaining a copy/i.test(text)) found.add("MIT");
  if (/Redistribution and use in source and binary forms/i.test(text)) found.add(/Neither the name|names of its contributors/i.test(text) ? "BSD-3-Clause" : "BSD (see notices)");
  if (/Permission to use, copy, modify, and(?:\/or)? distribute this software for any purpose with or without fee/i.test(text)) found.add("ISC");
  if (/SIL OPEN FONT LICENSE/i.test(text)) found.add("OFL-1.1");
  if (/This software is provided ['"]as-is['"]|This software is provided 'as-is'/i.test(text)) found.add("Zlib (see notices)");
  if (/This is free and unencumbered software released into the public domain/.test(text)) found.add("Unlicense");
  return [...found].join("; ") || "See notices";
}

async function trackedInputs(scope: ProcessScope, root: string): Promise<Record<string, string>> {
  const result = await scope.capture(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], { cwd: root });
  if (result.code) throw new Error("Cannot enumerate tracked license inputs.");
  const paths = result.stdout.split("\0").filter(path => path && (
    /(^|\/)(go\.(mod|sum)|pubspec\.(yaml|lock)|package\.json|bun\.lock|Dockerfile|.*\.podspec|.*\.gradle\.kts|CMakeLists\.txt|.*Package\.swift|Package\.resolved|Podfile\.lock)$/.test(path) ||
    /(^|\/)compose[^/]*\.yaml$/.test(path) ||
    path.startsWith("third_party/") && !path.startsWith("third_party/licenses/") && !path.endsWith(".md") ||
    path.startsWith("frontend/assets/licenses/") && path !== assetPath ||
    /^\.github\/workflows\/.*\.ya?ml$/.test(path) ||
    [".tool-versions", ".bun-version", "scripts/security/scan-dependencies.ts", "scripts/security/scan-image.ts", "scripts/ci/setup-flutter.ts", "scripts/testing/browser/browser-tools.ts", "scripts/generation/generate-client.ts", "scripts/development/native-ollama.ts", "frontend/android/gradle/wrapper/gradle-wrapper.properties", "backend/internal/data/document/datasources/processor/document_pins.go"].includes(path)
  ));
  paths.push("third_party/licenses/supplemental.json", "third_party/licenses/android-resolution.json");
  const supplemental = JSON.parse(await readFile(join(root, "third_party/licenses/supplemental.json"), "utf8")) as Supplemental[];
  paths.push(...supplemental.flatMap(source => source.files ?? []));
  return ordered(Object.fromEntries(await Promise.all([...new Set(paths)].map(async path => [path, digest(await readFile(join(root, path), "utf8"))]))));
}

async function noticeFiles(directory: string, prefix = ""): Promise<string[]> {
  const output: string[] = [];
  for (const entry of await readdir(join(directory, prefix), { withFileTypes: true })) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory() && ![".git", "node_modules", "build", ".dart_tool"].includes(entry.name)) output.push(...await noticeFiles(directory, path));
    else if (entry.isFile() && /^(licen[sc]e|copying|notice|copyright|unlicense)([._-]|$)/i.test(entry.name)) output.push(path);
  }
  return output.sort();
}

async function fetchText(url: string, signal: AbortSignal): Promise<string | undefined> {
  const cache = join(ROOT, ".cache/license-audit", digest(url));
  if (await Bun.file(cache).exists()) return await readFile(cache, "utf8");
  const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(30000)]) });
  if (response.status === 404) return undefined;
  if (!response.ok) throw new Error(`License download failed (${response.status}): ${url}`);
  const text = await response.text();
  if (/^\s*<!doctype html/i.test(text)) throw new Error(`Expected plain notice: ${url}`);
  await mkdir(join(ROOT, ".cache/license-audit"), { recursive: true });
  await Bun.write(cache, text);
  return text;
}

export async function collectLicenses(scope: ProcessScope, root = ROOT): Promise<LicenseCatalog> {
  const catalog: LicenseCatalog = { schemaVersion: 1, inputs: await trackedInputs(scope, root), texts: {}, entries: [] };
  const addNotice = (entry: { notices: Notice[] }, title: string, text: string) => {
    if (!text.trim()) return;
    const textId = digest(text);
    catalog.texts[textId] = text;
    if (!entry.notices.some(notice => notice.textId === textId)) entry.notices.push({ title, textId });
  };
  const addFiles = async (entry: Entry, directory: string) => {
    for (const path of await noticeFiles(directory)) addNotice(entry, path, await readFile(join(directory, path), "utf8"));
  };
  const finish = (entry: Entry) => {
    if (!entry.license) entry.license = entry.notices.length ? identifyLicense(entry.notices.map(n => catalog.texts[n.textId]).join("\n")) : "Review required: missing license evidence";
    if (!entry.notices.length) addNotice(entry, "Evidence gap", "No license text was found in this exact package distribution. Review its upstream licensing before redistributing this component. See third_party/COMMERCIAL_LICENSE_REVIEW.md.");
    catalog.entries.push(entry);
  };
  const modules = await scope.capture(["go", "-C", "backend", "list", "-m", "-json", "all"], { cwd: root }, 120000);
  if (modules.code) throw new Error("Resolve the Go module graph first with go -C backend mod download all.");
  const runtimeResult = await scope.capture(["go", "-C", "backend", "list", "-deps", "-f", "{{with .Module}}{{.Path}}{{end}}", "./cmd/..."], { cwd: root }, 120000);
  if (runtimeResult.code) throw new Error("Cannot classify Go command dependencies.");
  const runtime = new Set(runtimeResult.stdout.split("\n"));
  const goModules = modules.stdout.trim().split(/\n(?=\{)/).map(text => JSON.parse(text) as GoModule);
  for (const module of goModules.filter(module => !module.Main)) {
    if (!module.Dir) throw new Error(`Run go -C backend mod download all; missing ${module.Path}`);
    const entry: Entry = { id: `go:${module.Path}`, name: module.Path, version: module.Version ?? "", component: runtime.has(module.Path) ? "Go application" : "Go tooling / test / module graph", license: "", sourceUrl: `https://pkg.go.dev/${module.Path}@${module.Version}`, notices: [] };
    await addFiles(entry, module.Dir);
    if (module.Path === "github.com/iris-contrib/schema") {
      const readme = await readFile(join(module.Dir, "README.md"), "utf8");
      addNotice(entry, "README.md — License", readme.slice(readme.indexOf("## License")));
    }
    if (module.Path === "github.com/nexus-rpc/nexus-proto-annotations") {
      const url = `https://raw.githubusercontent.com/nexus-rpc/nexus-proto-annotations/${module.Version}/LICENSE`;
      const notice = await fetchText(url, scope.signal);
      if (notice) addNotice(entry, url, notice);
    }
    finish(entry);
  }
  const configPath = join(root, "frontend/.dart_tool/package_config.json");
  const config = JSON.parse(await readFile(configPath, "utf8")) as { packages: { name: string; rootUri: string }[] };
  const lock = Bun.YAML.parse(await readFile(join(root, "frontend/pubspec.lock"), "utf8")) as { packages: Record<string, { version: string; dependency: string; source: string }> };
  for (const pkg of config.packages.filter(pkg => !["domabas", "domabas_api"].includes(pkg.name))) {
    const directory = fileURLToPath(new URL(pkg.rootUri, `file://${configPath}`));
    const pinned = lock.packages[pkg.name];
    if (!pinned) throw new Error(`Unlocked Dart package: ${pkg.name}`);
    const entry: Entry = { id: `dart:${pkg.name}`, name: pkg.name, version: pinned.source === "sdk" ? "Flutter 3.47.4 / Dart 3.13.3" : pinned.version, component: pinned.dependency === "direct dev" ? "Flutter tooling / test" : "Flutter client", license: "", sourceUrl: pinned.source === "hosted" ? `https://pub.dev/packages/${pkg.name}/versions/${pinned.version}` : pinned.source === "sdk" ? "https://github.com/flutter/flutter/tree/3.47.4" : "https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_drop", notices: [] };
    await addFiles(entry, directory);
    if (!entry.notices.length && pinned.source === "sdk") addNotice(entry, "Flutter SDK LICENSE", await readFile(resolve(directory, "../../LICENSE"), "utf8"));
    finish(entry);
  }
  const bunLock = JSON.parse((await readFile(join(root, "bun.lock"), "utf8")).replace(/,\s*([}\]])/g, "$1")) as { packages: Record<string, [string]> };
  for (const [name, [identity]] of Object.entries(bunLock.packages)) {
    const version = identity.slice(identity.lastIndexOf("@") + 1);
    const entry: Entry = { id: `npm:${name}`, name, version, component: "Bun tooling", license: "", sourceUrl: `https://www.npmjs.com/package/${name}/v/${version}`, notices: [] };
    let metadata: { license?: string; version: string };
    const directory = join(root, "node_modules", name);
    if (await Bun.file(join(directory, "package.json")).exists()) {
      metadata = JSON.parse(await readFile(join(directory, "package.json"), "utf8"));
      if (metadata.version !== version) throw new Error(`Installed npm version differs: ${name}`);
      await addFiles(entry, directory);
    } else {
      const json = await fetchText(`https://registry.npmjs.org/${name}/${version}`, scope.signal);
      if (!json) throw new Error(`Missing locked npm package ${identity}`);
      metadata = JSON.parse(json);
      for (const file of ["LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"]) {
        const url = `https://cdn.jsdelivr.net/npm/${name}@${version}/${file}`;
        const notice = await fetchText(url, scope.signal);
        if (notice) { addNotice(entry, url, notice); break; }
      }
    }
    entry.license = metadata.license ?? "";
    if (name.startsWith("@img/sharp-libvips")) {
      entry.license = `${entry.license || "LGPL (see notices)"}; bundled libraries under additional terms (see notices)`;
      const url = `https://cdn.jsdelivr.net/npm/${name}@${version}/README.md`;
      const readme = await fetchText(url, scope.signal);
      if (readme) addNotice(entry, "Upstream bundled-library licensing table", readme);
      const lgpl = await fetchText("https://www.gnu.org/licenses/lgpl-3.0.txt", scope.signal);
      const gpl = await fetchText("https://www.gnu.org/licenses/gpl-3.0.txt", scope.signal);
      if (lgpl && gpl) { addNotice(entry, "LGPL-3.0", lgpl); addNotice(entry, "GPL-3.0 incorporated by LGPL-3.0", gpl); }
    }
    finish(entry);
  }
  const supplemental = JSON.parse(await readFile(join(root, "third_party/licenses/supplemental.json"), "utf8")) as Supplemental[];
  for (const source of supplemental) {
    const entry: { notices: Notice[] } = { notices: [] };
    for (const path of source.files ?? []) addNotice(entry, path, await readFile(join(root, path), "utf8"));
    for (const url of source.urls ?? []) {
      const text = await fetchText(url, scope.signal);
      if (!text) throw new Error(`Missing supplemental license: ${url}`);
      addNotice(entry, url, text);
    }
    if (source.note) addNotice(entry, "Inventory scope", source.note);
    if ("appendTo" in source) appendSupplementalNotices(catalog, source.appendTo, source.version, entry.notices);
    else finish({ id: source.id, name: source.name, version: source.version, component: source.component, license: source.license ?? "", sourceUrl: source.sourceUrl, notices: entry.notices });
  }
  catalog.entries.sort((a, b) => a.id.localeCompare(b.id, "en"));
  catalog.texts = ordered(catalog.texts);
  validateCatalog(catalog);
  return catalog;
}

export function appendSupplementalNotices(catalog: LicenseCatalog, id: string, version: string, notices: Notice[]): void {
  const target = catalog.entries.find(entry => entry.id === id);
  if (!target || target.version !== version) throw new Error(`Missing or outdated supplemental target: ${id}@${version}`);
  for (const notice of notices) if (!target.notices.some(existing => existing.textId === notice.textId)) target.notices.push(notice);
}

export function validateCatalog(catalog: LicenseCatalog): void {
  if (catalog.schemaVersion !== 1 || !catalog.entries.length) throw new Error("Invalid license catalog.");
  const ids = new Set<string>();
  for (const entry of catalog.entries) {
    if (!entry.id || ids.has(entry.id) || !entry.name || !entry.component || !entry.license || !entry.notices.length) throw new Error(`Invalid or duplicate license entry: ${entry.id}`);
    ids.add(entry.id);
    for (const notice of entry.notices) {
      const text = catalog.texts[notice.textId];
      if (!notice.title || !text || digest(text) !== notice.textId) throw new Error(`Missing or altered license text: ${entry.id}`);
    }
  }
}

export async function validateLockedCoverage(catalog: LicenseCatalog, root = ROOT): Promise<void> {
  const entries = new Map(catalog.entries.map(entry => [entry.id, entry]));
  const requireEntry = (id: string, version?: string) => {
    const entry = entries.get(id);
    if (!entry || version && entry.version !== version) throw new Error(`Missing or outdated locked license entry: ${id}`);
  };
  const go = await readFile(join(root, "backend/go.mod"), "utf8");
  for (const match of go.matchAll(/^\s*([^\s]+) (v[^\s]+)(?: \/\/ indirect)?$/gm)) requireEntry(`go:${match[1]}`, match[2]);
  const dart = Bun.YAML.parse(await readFile(join(root, "frontend/pubspec.lock"), "utf8")) as { packages: Record<string, { version: string; source: string }> };
  for (const [name, pkg] of Object.entries(dart.packages)) if (name !== "domabas_api") requireEntry(`dart:${name}`, pkg.source === "sdk" ? undefined : pkg.version);
  const npm = JSON.parse((await readFile(join(root, "bun.lock"), "utf8")).replace(/,\s*([}\]])/g, "$1")) as { packages: Record<string, [string]> };
  for (const [name, [identity]] of Object.entries(npm.packages)) requireEntry(`npm:${name}`, identity.slice(identity.lastIndexOf("@") + 1));
  const supplemental = JSON.parse(await readFile(join(root, "third_party/licenses/supplemental.json"), "utf8")) as Supplemental[];
  for (const source of supplemental) requireEntry("appendTo" in source ? source.appendTo : source.id, source.version);
}

export function licenseIndex(catalog: LicenseCatalog): string {
  const cell = (value: string) => value.replaceAll("|", "\\|").replaceAll("\n", " ");
  const name = (entry: Entry) => entry.sourceUrl ? `[${cell(entry.name)}](${entry.sourceUrl})` : cell(entry.name);
  return `# Third-party dependency inventory\n\nGenerated by \`task generate:licenses\`. ${catalog.entries.length} components.\n\nFull retained license texts and copyright notices are in [catalog.json](catalog.json)\nand in the app's Licenses screen. Labels aid navigation; the original notices\nare authoritative. Module-graph entries can include unused, test and tool code.\nSee [commercial review and coverage limits](../COMMERCIAL_LICENSE_REVIEW.md).\n\n| Component | Version | Area | License / notice summary |\n| --- | --- | --- | --- |\n` + catalog.entries.map(entry => `| ${name(entry)} | ${cell(entry.version)} | ${cell(entry.component)} | ${cell(entry.license)} |`).join("\n") + "\n";
}

if (import.meta.main) await runCLI(async scope => {
  const args = Bun.argv.slice(2);
  if (args.some(arg => !["--collect", "--check"].includes(arg)) || args.length > 1) throw new Error("Use task generate:licenses [-- --collect] or task generate:licenses:check.");
  const catalog = args.includes("--collect") ? await collectLicenses(scope) : JSON.parse(await readFile(join(ROOT, catalogPath), "utf8")) as LicenseCatalog;
  validateCatalog(catalog);
  await validateLockedCoverage(catalog);
  if (JSON.stringify(catalog.inputs) !== JSON.stringify(await trackedInputs(scope, ROOT))) throw new Error("License inputs changed. Review dependencies and run task generate:licenses -- --collect.");
  const outputs = new Map([[catalogPath, JSON.stringify(catalog, null, 2) + "\n"], [assetPath, JSON.stringify({ schemaVersion: catalog.schemaVersion, texts: catalog.texts, entries: catalog.entries }) + "\n"], [indexPath, licenseIndex(catalog)]]);
  for (const [path, text] of outputs) {
    if (args.includes("--check")) {
      if (!await Bun.file(join(ROOT, path)).exists() || await readFile(join(ROOT, path), "utf8") !== text) throw new Error(`Stale license output: ${path}`);
    } else await Bun.write(join(ROOT, path), text);
  }
  console.log(`${args.includes("--check") ? "Verified" : "Generated"} ${catalog.entries.length} license entries.`);
}, { timeoutMs: 900000 });
