'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { execFileSync } = require('node:child_process')

test('native activation observer preserves popup clicks and dismisses external app activation', { skip: process.platform !== 'darwin' }, () => {
  const root = path.resolve(__dirname, '..')
  fs.mkdirSync(path.join(root, '.cache'), { recursive: true })
  const directory = fs.mkdtempSync(path.join(root, '.cache/selection-activation-'))
  const source = fs.readFileSync(path.join(root, 'src/main/native/macselection.swift'), 'utf8')
  const bootstrap = source.indexOf('let application = NSApplication.shared')
  assert.ok(bootstrap > 0)
  const harness = `
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let owner = NSRunningApplication.current
let monitor = SelectionMonitor(parentPID: owner.processIdentifier)
monitor.start()
FileHandle.standardOutput.write(Data("OWNER\\n".utf8))
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: owner])
FileHandle.standardOutput.write(Data("EXTERNAL\\n".utf8))
guard let external = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier != owner.processIdentifier }) else { fatalError("Missing external test application") }
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: external])
FileHandle.standardOutput.write(Data("END\\n".utf8))
`
  const file = path.join(directory, 'monitor.swift')
  const binary = path.join(directory, 'monitor')
  fs.writeFileSync(file, source.slice(0, bootstrap) + harness)
  execFileSync('swiftc', [file, '-o', binary, '-framework', 'AppKit', '-framework', 'ApplicationServices'])
  const output = execFileSync(binary, { encoding: 'utf8' })
  assert.equal(output.split('OWNER\n')[1].split('EXTERNAL\n')[0], '')
  assert.deepEqual(JSON.parse(output.split('EXTERNAL\n')[1].split('END\n')[0]), { type: 'dismiss' })
})
