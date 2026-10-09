'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs/promises')
const path = require('node:path')
const { execFileSync, spawnSync } = require('node:child_process')
const signMacApp = require('../scripts/sign-macos.cjs')

test('packaged app and native helper are signed with a bound bundle identity', { skip: process.platform !== 'darwin' }, async () => {
  const cache = path.resolve(__dirname, '../.cache')
  await fs.mkdir(cache, { recursive: true })
  const output = await fs.mkdtemp(path.join(cache, 'signing-test-'))
  const contents = path.join(output, 'Fixture.app/Contents')
  await fs.mkdir(path.join(contents, 'MacOS'), { recursive: true })
  await fs.mkdir(path.join(contents, 'Resources'), { recursive: true })
  await fs.writeFile(path.join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.glint.signing-test</string>
<key>CFBundleExecutable</key><string>Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>`)
  const source = path.join(output, 'fixture.c')
  const binary = path.join(output, 'fixture')
  await fs.writeFile(source, 'int main(void) { return 0; }\n')
  execFileSync('clang', [source, '-o', binary])
  await fs.copyFile(binary, path.join(contents, 'MacOS/Fixture'))
  await fs.copyFile(binary, path.join(contents, 'Resources/macselection'))
  await fs.copyFile(binary, path.join(contents, 'Resources/macocr'))
  await signMacApp({ electronPlatformName: 'darwin', appOutDir: output,
    packager: { appInfo: { productFilename: 'Fixture' } } })
  const bundle = path.join(output, 'Fixture.app')
  execFileSync('codesign', ['--verify', '--deep', '--strict', bundle])
  const signature = spawnSync('codesign', ['--display', '--verbose=4', '-r-', bundle], { encoding: 'utf8' })
  assert.equal(signature.status, 0, signature.stderr)
  assert.match(signature.stderr, /Identifier=com.glint.signing-test/)
  assert.ok(!signature.stderr.includes('Info.plist=not bound'))
  assert.ok(!signature.stderr.includes('Sealed Resources=none'))
})
