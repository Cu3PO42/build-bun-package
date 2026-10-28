// Keep the locked dependency graph and manifest constraints. Only fetched
// resolutions become local archives, which Bun can install even in offline mode.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type Source = { id: string; key: string; kind: string; packageName: string };
const bundle = process.argv[2];
const sources: Source[] = JSON.parse(readFileSync(join(bundle, "sources.json"), "utf8"));
const lock = Bun.JSONC.parse(readFileSync("bun.lock", "utf8"));
const replacements = new Map<string, Set<string>>();

for (const source of sources) {
  const original = lock.packages[source.key];
  const resolution = `${source.packageName}@${join(bundle, "tarballs", `${source.id}.tgz`)}`;
  const targets = replacements.get(original[0]) ?? new Set<string>();
  targets.add(resolution);
  replacements.set(original[0], targets);
  const metadata = original[source.kind === "npm" ? 2 : 1];
  const integrity = original[source.kind === "npm" ? 3 : 2];
  lock.packages[source.key] = [resolution, metadata, integrity];
}

// Bun keys patches by the resolved source, rather than package.json's version.
// Change both copies so it applies the same patches to the local resolutions.
function rewritePatches(patches: Record<string, string>) {
  return Object.fromEntries(Object.entries(patches).flatMap(([key, path]) =>
    [...(replacements.get(key) ?? [key])].map(target => [target, path])));
}
if (lock.patchedDependencies) lock.patchedDependencies = rewritePatches(lock.patchedDependencies);
const manifest = JSON.parse(readFileSync("package.json", "utf8"));
if (manifest.patchedDependencies) {
  manifest.patchedDependencies = rewritePatches(manifest.patchedDependencies);
  writeFileSync("package.json", JSON.stringify(manifest, null, 2) + "\n");
}
writeFileSync("bun.lock", JSON.stringify(lock, null, 2) + "\n");
