const fs = require('node:fs')
const vm = require('node:vm')
const test = require('node:test')
const assert = require('node:assert/strict')
const { spawnSync } = require('node:child_process')

const source = fs.readFileSync(new URL('../ProcessLimits.js', `file://${__filename}`), 'utf8')
  .replace(/^\.pragma library\s*/m, '')
const context = {}
vm.createContext(context)
vm.runInContext(`${source}\nthis.ProcessLimits = { boundedCommand, TRUNCATED_EXIT_CODE };`, context)
const ProcessLimits = context.ProcessLimits

function run(command, stdoutBytes, stderrBytes) {
  const bounded = Array.from(ProcessLimits.boundedCommand(command, stdoutBytes, stderrBytes))
  return spawnSync(bounded[0], bounded.slice(1), { encoding: 'utf8' })
}

test('bounded command preserves normal output and exit status', () => {
  const result = run(['bash', '-c', 'printf normal; printf warning >&2; exit 7'], 64, 64)
  assert.equal(result.status, 7)
  assert.equal(result.stdout, 'normal')
  assert.equal(result.stderr, 'warning')
})

test('bounded command passes externally influenced arguments without shell interpolation', () => {
  const argument = '$(printf injected); `printf also-injected`'
  const result = run(['printf', '%s', argument], 128, 64)
  assert.equal(result.status, 0)
  assert.equal(result.stdout, argument)
})

test('bounded command caps stdout before returning it to the collector', () => {
  const result = run(['bash', '-c', 'printf 1234567890'], 5, 64)
  assert.equal(result.status, ProcessLimits.TRUNCATED_EXIT_CODE)
  assert.equal(result.stdout, '12345')
  assert.equal(Buffer.byteLength(result.stdout), 5)
})

test('bounded command caps stderr before returning it to the collector', () => {
  const result = run(['bash', '-c', 'printf abcdefghij >&2'], 64, 4)
  assert.equal(result.status, ProcessLimits.TRUNCATED_EXIT_CODE)
  assert.equal(result.stderr, 'abcd')
  assert.equal(Buffer.byteLength(result.stderr), 4)
})
