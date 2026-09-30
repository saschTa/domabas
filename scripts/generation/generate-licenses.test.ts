import { createHash } from "node:crypto";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "bun:test";
import { appendSupplementalNotices, identifyLicense, licenseIndex, validateCatalog, validateLockedCoverage, type LicenseCatalog } from "./generate-licenses.ts";
import { ROOT } from "../shared/runtime.ts";

describe("offline license inventory", () => {
  test("every locked package has evidence, including other-platform tooling", async () => {
    const catalog = await Bun.file(`${ROOT}/third_party/licenses/catalog.json`).json() as LicenseCatalog;
    validateCatalog(catalog);
    await validateLockedCoverage(catalog);
    const withoutWindows = { ...catalog, entries: catalog.entries.filter(entry => entry.id !== "npm:@img/sharp-win32-x64") };
    await expect(validateLockedCoverage(withoutWindows)).rejects.toThrow("npm:@img/sharp-win32-x64");
  });

  test("a referenced notice cannot be changed or lost silently", () => {
    const text = "An upstream copyright and license notice";
    const textId = createHash("sha256").update(text).digest("hex");
    const catalog: LicenseCatalog = { schemaVersion: 1, inputs: {}, texts: { [textId]: text }, entries: [{ id: "example", name: "Example", version: "1", component: "Client", license: "See notices", sourceUrl: "", notices: [{ title: "LICENSE", textId }] }] };
    expect(() => validateCatalog(catalog)).not.toThrow();
    expect(() => validateCatalog({ ...catalog, texts: {} })).toThrow("Missing or altered");
    expect(() => validateCatalog({ ...catalog, texts: { [textId]: "Changed notice" } })).toThrow("Missing or altered");
    expect(() => validateCatalog({ ...catalog, entries: [...catalog.entries, ...catalog.entries] })).toThrow("duplicate");
  });

  test("supplemental source notices preserve package metadata and existing notices", () => {
    const license = "Original license";
    const source = "Source retrieval instructions";
    const licenseId = createHash("sha256").update(license).digest("hex");
    const sourceId = createHash("sha256").update(source).digest("hex");
    const original = { id: "dart:example", name: "Example", version: "1", component: "Flutter client", license: "MPL-2.0", sourceUrl: "https://example.test", notices: [{ title: "LICENSE", textId: licenseId }] };
    const catalog: LicenseCatalog = { schemaVersion: 1, inputs: {}, texts: { [licenseId]: license, [sourceId]: source }, entries: [structuredClone(original)] };
    const sourceNotice = { title: "Covered source", textId: sourceId };
    const additional = [{ title: "Retained LICENSE", textId: licenseId }, sourceNotice];
    appendSupplementalNotices(catalog, original.id, original.version, additional);
    appendSupplementalNotices(catalog, original.id, original.version, additional);
    expect(catalog.entries).toEqual([{ ...original, notices: [...original.notices, sourceNotice] }]);
    validateCatalog(catalog);
    expect(() => appendSupplementalNotices(catalog, "dart:missing", "1", additional)).toThrow("supplemental target");
    expect(() => appendSupplementalNotices(catalog, original.id, "2", additional)).toThrow("supplemental target");
    expect(catalog.entries).toHaveLength(1);
  });

  test("offline coverage rejects a source notice pinned to an older package", async () => {
    const root = await mkdtemp(join(tmpdir(), "domabas-license-coverage-"));
    try {
      for (const path of ["backend", "frontend", "third_party/licenses"]) await mkdir(join(root, path), { recursive: true });
      await writeFile(join(root, "backend/go.mod"), "module example\n");
      await writeFile(join(root, "frontend/pubspec.lock"), "packages:\n  example:\n    version: '2'\n    source: hosted\n");
      await writeFile(join(root, "bun.lock"), '{"packages":{}}');
      await writeFile(join(root, "third_party/licenses/supplemental.json"), '[{"appendTo":"dart:example","version":"1"}]');
      const catalog: LicenseCatalog = { schemaVersion: 1, inputs: {}, texts: {}, entries: [{ id: "dart:example", name: "Example", version: "2", component: "Flutter client", license: "MPL-2.0", sourceUrl: "", notices: [] }] };
      await expect(validateLockedCoverage(catalog, root)).rejects.toThrow("outdated locked license entry: dart:example");
      await writeFile(join(root, "third_party/licenses/supplemental.json"), '[{"appendTo":"dart:example","version":"2"}]');
      await expect(validateLockedCoverage(catalog, root)).resolves.toBeUndefined();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("GPL mentioning AGPL compatibility is not classified as AGPL", () => {
    expect(identifyLicense("GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\nYou may link with the GNU Affero General Public License.")).toBe("GPL-3.0 (see notices)");
    expect(identifyLicense("GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3, 19 November 2007")).toContain("AGPL");
    expect(identifyLicense("No license grant found.")).toBe("See notices");
  });

  test("wrapped grant text is recognized without treating license names as grants", () => {
    expect(identifyLicense("Permission is hereby granted, free of charge, to any\nperson obtaining a copy")).toBe("MIT");
    expect(identifyLicense("Permission to use, copy, modify, and/or distribute this\nsoftware for any purpose with or without fee")).toBe("ISC");
    expect(identifyLicense("Redistribution and use in source and binary\nforms\nNeither the\nname of the author")).toBe("BSD-3-Clause");
    expect(identifyLicense("Compatible with MIT, GPLv2 and LGPL. No license grant found.")).toBe("See notices");
    expect(identifyLicense("GNU GENERAL PUBLIC LICENSE\nVersion 3\ncompatible with GNU Affero General Public License Version 3")).toBe("GPL-3.0 (see notices)");
    expect(identifyLicense("Mozilla Public License Version 2.0\nSecondary licenses include the GNU General Public License, Version 2.0, the GNU Lesser\nGeneral Public License, Version 2.1.")).toBe("MPL-2.0");
    expect(identifyLicense("GNU LESSER GENERAL PUBLIC LICENSE\nVersion 2.1")).toBe("LGPL (see notices)");
  });

  test("mixed distributions expose their additional terms and missing grants stay visible", async () => {
    const catalog = await Bun.file(`${ROOT}/third_party/licenses/catalog.json`).json() as LicenseCatalog;
    const entry = (id: string) => catalog.entries.find(entry => entry.id === id)!;
    expect(entry("extra:Bun").license).toContain("LGPL-2.0 / LGPL-2.1");
    expect(entry("extra:pdfium/licenses/libjpeg_turbo.md").license).toContain("IJG");
    expect(entry("extra:emscripten/system_lib_compiler-rt_LICENSE.TXT").license).toContain("LLVM-exception");
    for (const dependency of catalog.entries.filter(entry => entry.id.startsWith("npm:@img/sharp-libvips"))) {
      expect(dependency.license).toContain("LGPL-3.0-or-later");
      expect(dependency.license).toContain("additional terms");
      expect(dependency.license).not.toContain("GPL-3.0;");
    }
    expect(entry("go:github.com/chzyer/logex").license).toBe("Review required: missing license evidence");
    expect(entry("dart:dbus").license).toBe("MPL-2.0");
    expect(entry("go:github.com/chzyer/logex").notices.some(notice => notice.title === "Evidence gap")).toBe(true);
    const application = entry("extra:Domabas");
    expect(application.license).toBe("MIT");
    expect(application.notices.map(notice => catalog.texts[notice.textId])).toContain(await Bun.file(`${ROOT}/LICENSE`).text());
    expect(licenseIndex(catalog)).toContain("| Domabas |  | Application | MIT |");
    expect(licenseIndex(catalog)).not.toContain("[Domabas]()");
  });
});
