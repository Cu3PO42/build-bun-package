import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, rmSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

// Resolve packages from the installed fixture, not this test's store path.
const require = createRequire(join(process.cwd(), 'package.json'))
const fixture = process.argv[2]
const expectedPackages: Record<string, number> = {
  'markdown-toc': 58,
  localtunnel: 91,
  'yarn-lock-converter': 57,
  'relative-time': 56,
  'opcua-schema': 42,
}
const lock = Bun.JSONC.parse(await Bun.file('bun.lock').text())
assert.equal(Object.keys(lock.packages).length, expectedPackages[fixture])

function version(bin: string, expected: string) {
  const result = Bun.spawnSync([
    join(process.cwd(), 'node_modules/.bin', bin),
    '--version',
  ])
  assert.equal(result.exitCode, 0, result.stderr.toString())
  assert.equal(result.stdout.toString().trim(), expected)
}

switch (fixture) {
  case 'markdown-toc': {
    // The npm lock contains a deep graph of older CommonJS packages.
    const matter = require('gray-matter')('---\ntitle: Migration\n---\nbody')
    assert.equal(matter.data.title, 'Migration')
    assert.equal(matter.content.trim(), 'body')
    const Remarkable = require('remarkable')
    assert.equal(
      new Remarkable().render('# Migration\n'),
      '<h1>Migration</h1>\n',
    )
    version('remarkable', '1.7.4')
    break
  }
  case 'localtunnel': {
    // Mocha's nested dependencies must keep their own locked versions.
    const mocha = createRequire(require.resolve('mocha/package.json'))
    assert.equal(require('debug/package.json').version, '4.3.2')
    assert.equal(mocha('debug/package.json').version, '4.3.1')
    assert.equal(require('yargs/package.json').version, '17.1.1')
    assert.equal(mocha('yargs/package.json').version, '16.2.0')
    assert.equal(
      require('yargs/yargs')(['--port', '8080']).number('port').parse().port,
      8080,
    )
    version('mocha', '9.1.1')
    // Fetch all platforms, then install this host's optional dependencies only.
    assert.equal(lock.packages.fsevents[2].os, 'darwin')
    assert.equal(
      existsSync('node_modules/fsevents'),
      process.platform === 'darwin',
    )
    break
  }
  case 'yarn-lock-converter': {
    // Exercise registry metadata hydration of a genuine Yarn 3 lockfile and
    // actual I/O through the migrated transitive cache dependency graph.
    const parsed = require('@yarnpkg/lockfile').parse(
      '# yarn lockfile v1\n\nexample@^1.0.0:\n  version "1.2.3"\n',
    )
    assert.equal(parsed.type, 'success')
    assert.equal(parsed.object['example@^1.0.0'].version, '1.2.3')
    assert.deepEqual(require('js-yaml').load('nested:\n  enabled: true\n'), {
      nested: { enabled: true },
    })
    const cache = mkdtempSync(join(tmpdir(), 'migration-cacache-'))
    try {
      const cacache = require('cacache')
      await cacache.put(cache, 'migration-test', 'cached data')
      assert.equal(
        (await cacache.get(cache, 'migration-test')).data.toString(),
        'cached data',
      )
    } finally {
      rmSync(cache, { recursive: true, force: true })
    }
    version('js-yaml', '4.1.0')
    break
  }
  case 'relative-time': {
    // pnpm's npm aliases must resolve to the underlying packages, while the
    // complete development graph supplies a working minifier and source maps.
    assert.equal(lock.packages['string-width-cjs'][0], 'string-width@4.2.3')
    assert.equal(require('string-width-cjs')('古'), 2)
    assert.equal(require('strip-ansi-cjs')('\u001b[31mred\u001b[0m'), 'red')
    const result = await require('terser').minify(
      { 'input.js': 'const value = 1 + 2; console.log(value);' },
      { sourceMap: { filename: 'output.js', url: 'output.js.map' } },
    )
    assert.match(result.code, /console\.log\(3\)/)
    assert.equal(JSON.parse(result.map).version, 3)
    version('terser', 'terser 5.43.1')
    const scratch = mkdtempSync(join(tmpdir(), 'migration-pnpm-'))
    try {
      const nested = join(scratch, 'nested', 'directory')
      await require('mkdirp').mkdirp(nested)
      assert.ok(existsSync(nested))
      await require('rimraf').rimraf(join(scratch, 'nested'))
      assert.ok(!existsSync(nested))
    } finally {
      rmSync(scratch, { recursive: true, force: true })
    }
    break
  }
  case 'opcua-schema': {
    // This is an upstream npm shrinkwrap v2, with both packages and legacy
    // dependency sections. Exercise its parsers and a migrated executable.
    const xml = await require('xml2js').parseStringPromise(
      '<Nodes><Node Name="Root" Id="84"/></Nodes>',
    )
    assert.deepEqual({ ...xml.Nodes.Node[0].$ }, { Name: 'Root', Id: '84' })
    const result = Bun.spawnSync(
      [join(process.cwd(), 'node_modules/.bin/csv-parser')],
      { stdin: Buffer.from('Name,Id\nRoot,84\nObjects,85\n') },
    )
    assert.equal(result.exitCode, 0, result.stderr.toString())
    const rows = result.stdout
      .toString()
      .trim()
      .split('\n')
      .map((line) => JSON.parse(line))
    assert.deepEqual(rows, [
      { Name: 'Root', Id: '84' },
      { Name: 'Objects', Id: '85' },
    ])
    assert.deepEqual(require('lodash').keyBy(rows, 'Id')['84'], rows[0])
    assert.equal(
      require('yargs/yargs')(['--node', '84']).number('node').parse().node,
      84,
    )
    break
  }
  default:
    throw new Error(`Unknown fixture: ${fixture}`)
}
