// Keep the locked dependency graph and manifest constraints. Only fetched
// resolutions become local archives, which Bun can install even in offline mode.
import {
  chmodSync,
  cpSync,
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { join } from 'node:path'

type Source = {
  id: string
  key: string
  kind: string
  packageName: string
  integrity: string | null
  rev: string | null
}
const bundle = process.argv[2]
const sources: Source[] = JSON.parse(
  readFileSync(join(bundle, 'sources.json'), 'utf8'),
)
const lock = Bun.JSONC.parse(readFileSync('bun.lock', 'utf8'))
const replacements = new Map<string, Set<string>>()

function makeWritable(path: string) {
  const stat = lstatSync(path)
  if (stat.isSymbolicLink()) return
  chmodSync(path, stat.mode | 0o200)
  if (stat.isDirectory())
    for (const name of readdirSync(path)) makeWritable(join(path, name))
}

for (const source of sources) {
  const original = lock.packages[source.key]
  if (source.kind === 'git') {
    // Seed only Bun's native Git entry, retaining its source identity and the
    // fetched checkout rather than converting it to a different archive source.
    // Bun 1.4.4 keys these entries by the full .bun-tag, without a cache version.
    const rev = source.rev!
    if (!/^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$/.test(rev))
      throw new Error('Invalid locked Git commit')
    const target = join(process.env.BUN_INSTALL_CACHE_DIR!, `@G@${rev}`)
    if (!existsSync(target)) {
      cpSync(realpathSync(join(bundle, 'checkouts', source.id)), target, {
        recursive: true,
        dereference: false,
        verbatimSymlinks: true,
        filter: (path) => !path.endsWith('/.git'),
      })
      makeWritable(target)
      rmSync(join(target, '.bun-tag'), { force: true, recursive: true })
      writeFileSync(join(target, '.bun-tag'), rev)
    }
    // An explicit fetcherOpts.rev can pin a legacy row lacking a full commit.
    const resolution = original[0].replace(/#[^#]*$/, '') + `#${rev}`
    const targets = replacements.get(original[0]) ?? new Set<string>()
    targets.add(resolution)
    replacements.set(original[0], targets)
    original[0] = resolution
    original[2] = rev
    continue
  }
  const resolution = `${source.packageName}@${join(bundle, 'tarballs', `${source.id}.tgz`)}`
  const targets = replacements.get(original[0]) ?? new Set<string>()
  targets.add(resolution)
  replacements.set(original[0], targets)
  const metadata = original[source.kind === 'npm' ? 2 : 1]
  lock.packages[source.key] = [resolution, metadata]
  if (source.integrity) lock.packages[source.key].push(source.integrity)
}

// Bun keys patches by the resolved source, rather than package.json's version.
// Change both copies so it applies the same patches to the local resolutions.
function rewritePatches(patches: Record<string, string>) {
  return Object.fromEntries(
    Object.entries(patches).flatMap(([key, path]) =>
      [...(replacements.get(key) ?? [key])].map((target) => [target, path]),
    ),
  )
}
if (lock.patchedDependencies)
  lock.patchedDependencies = rewritePatches(lock.patchedDependencies)
const manifest = Bun.JSONC.parse(readFileSync('package.json', 'utf8'))
if (manifest.patchedDependencies) {
  manifest.patchedDependencies = rewritePatches(manifest.patchedDependencies)
  writeFileSync('package.json', JSON.stringify(manifest, null, 2) + '\n')
}
writeFileSync('bun.lock', JSON.stringify(lock, null, 2) + '\n')
