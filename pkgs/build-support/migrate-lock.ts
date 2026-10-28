// Run migration once in the network-enabled fetcher. Replay its manifest edits
// in the offline build, preserving unrelated changes made by project patches.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

type Json = null | boolean | number | string | Json[] | { [key: string]: Json }
type Manifest = { before: Json; after: Json }
type Snapshot = {
  inputs: Record<string, string | null>
  manifests: Record<string, string>
}
type Migration = {
  version: number
  inputs: Snapshot['inputs']
  manifests: Record<string, Manifest>
}

const inputFiles = [
  'npm-shrinkwrap.json',
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'pnpm-workspace.yaml',
  '.yarnrc.yml',
]
const read = (path: string) => readFileSync(path, 'utf8')
const json = (path: string): Json => JSON.parse(read(path))
const equal = (a: Json | undefined, b: Json | undefined): boolean => {
  if (a === b) return true
  if (Array.isArray(a) && Array.isArray(b))
    return a.length === b.length && a.every((value, i) => equal(value, b[i]))
  if (object(a) && object(b)) {
    const keys = Object.keys(a)
    return (
      keys.length === Object.keys(b).length &&
      keys.every((key) => equal(a[key], b[key]))
    )
  }
  return false
}
function object(value: Json | undefined): value is { [key: string]: Json } {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function manifests(directory = '.'): Record<string, string> {
  const result: Record<string, string> = {}
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort(
    (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0),
  )) {
    const path = join(directory, entry.name)
    if (entry.isDirectory() && !['node_modules', '.git'].includes(entry.name))
      Object.assign(result, manifests(path))
    else if (entry.isFile() && entry.name === 'package.json')
      result[path] = read(path)
  }
  return result
}

// Store only migration's edits, so unrelated manifest fields neither enter the
// fixed-output hash nor get replaced when a package reuses this cache.
function changes(
  before: Json | undefined,
  after: Json | undefined,
): { before?: Json; after?: Json } {
  if (object(before) && object(after)) {
    const original: Record<string, Json> = {}
    const migrated: Record<string, Json> = {}
    for (const key of new Set([
      ...Object.keys(before),
      ...Object.keys(after),
    ])) {
      if (equal(before[key], after[key])) continue
      const edit = changes(before[key], after[key])
      if (edit.before !== undefined) original[key] = edit.before
      if (edit.after !== undefined) migrated[key] = edit.after
    }
    return { before: original, after: migrated }
  }
  return { before, after }
}

// Apply only the keys that migration changed. An independent patch to scripts,
// version, or another dependency survives. Competing edits fail explicitly.
function merge(
  before: Json | undefined,
  after: Json | undefined,
  current: Json | undefined,
  path: string,
): Json | undefined {
  if (equal(before, after) || equal(current, after)) return current
  if (equal(current, before)) return after
  if (
    (before === undefined || object(before)) &&
    object(after) &&
    object(current)
  ) {
    const result = { ...current }
    for (const key of new Set([
      ...Object.keys(before ?? {}),
      ...Object.keys(after),
    ])) {
      const value = merge(
        before?.[key],
        after[key],
        current[key],
        `${path}.${key}`,
      )
      if (value === undefined) delete result[key]
      else result[key] = value
    }
    return result
  }
  throw new Error(
    `bunMigrateHook: conflicting migration and patch edits at ${path}; regenerate bunDepsHash or update bunDeps`,
  )
}

const [mode, path] = process.argv.slice(2)
if (mode === 'snapshot') {
  const snapshot: Snapshot = {
    inputs: Object.fromEntries(
      inputFiles.map((file) => [file, existsSync(file) ? read(file) : null]),
    ),
    manifests: manifests(),
  }
  writeFileSync(path, JSON.stringify(snapshot))
} else if (mode === 'record') {
  const before: Snapshot = JSON.parse(read(path))
  const changed: Migration['manifests'] = {}
  for (const [file, original] of Object.entries(before.manifests)) {
    const migrated = read(file)
    if (
      original !== migrated &&
      !equal(JSON.parse(original), JSON.parse(migrated))
    )
      changed[file] = changes(
        JSON.parse(original),
        JSON.parse(migrated),
      ) as Manifest
  }
  const migration: Migration = {
    version: 1,
    inputs: before.inputs,
    manifests: changed,
  }
  writeFileSync(process.argv[4], JSON.stringify(migration, null, 2) + '\n')
} else if (mode === 'apply') {
  const migration: Migration = JSON.parse(
    read(join(path, '.nix-bun/migration.json')),
  )
  if (migration.version !== 1)
    throw new Error('bunMigrateHook: unsupported migration metadata version')
  for (const [file, original] of Object.entries(migration.inputs)) {
    if ((existsSync(file) ? read(file) : null) !== original)
      throw new Error(
        `bunMigrateHook: migration input ${file} differs from cache; regenerate bunDepsHash or update bunDeps`,
      )
  }
  const lock = read(join(path, '.nix-bun/bun.lock'))
  if (
    existsSync('bun.lockb') ||
    (existsSync('bun.lock') && read('bun.lock') !== lock)
  )
    throw new Error(
      'bunMigrateHook: existing Bun lockfile differs from migrated cache; regenerate bunDepsHash or update bunDeps',
    )
  // Validate every edit before writing any manifests.
  const updates = Object.entries(migration.manifests).map(
    ([file, { before, after }]) => {
      const current = json(file)
      return [file, merge(before, after, current, file)] as const
    },
  )
  for (const [file, updated] of updates)
    writeFileSync(file, JSON.stringify(updated, null, 2) + '\n')
  writeFileSync('bun.lock', lock)
} else throw new Error(`Unknown migration operation: ${mode}`)
