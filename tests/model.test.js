const fs = require('node:fs')
const vm = require('node:vm')
const test = require('node:test')
const assert = require('node:assert/strict')

const source = fs.readFileSync(new URL('../Model.js', `file://${__filename}`), 'utf8')
  .replace(/^\.pragma library\s*/m, '')
const context = {}
vm.createContext(context)
vm.runInContext(`${source}\nthis.Model = { normalizeAddress, isValidAddress, addressError, withAddress, withoutAddress, parseKdeSnapshot, parseTailscaleStatus, filterTailscalePeers };`, context)
const Model = context.Model

test('validates and normalizes literal IP addresses', () => {
  assert.equal(Model.normalizeAddress(' [fd7a:115c:a1e0::1] '), 'fd7a:115c:a1e0::1')
  assert.equal(Model.isValidAddress('100.64.0.12'), true)
  assert.equal(Model.isValidAddress('fd7a:115c:a1e0::1'), true)
  assert.equal(Model.isValidAddress('192.168.1.300'), false)
  assert.equal(Model.isValidAddress('phone.tailnet.ts.net'), false)
  assert.equal(Model.addressError('https://100.64.0.12:1716'), 'Enter an IP address without a port or URL')
})

test('adds and removes remembered addresses without duplicates', () => {
  assert.deepEqual(Array.from(Model.withAddress(['100.64.0.1'], '100.64.0.1')), ['100.64.0.1'])
  assert.deepEqual(Array.from(Model.withAddress(['100.64.0.1'], '192.168.1.4')), ['100.64.0.1', '192.168.1.4'])
  assert.deepEqual(Array.from(Model.withoutAddress(['100.64.0.1', '192.168.1.4'], '100.64.0.1')), ['192.168.1.4'])
})

test('parses KDE Connect DBus snapshot into connection states', () => {
  const raw = [
    '{"type":"a{ss}","data":[{"phone":"Pixel","laptop":"Laptop"}]}',
    '{"type":"as","data":[["phone","laptop"]]}',
    '{"type":"as","data":[["phone"]]}',
    '{"type":"as","data":[["phone","laptop"]]}',
    '{"type":"as","data":["100.64.0.2","192.168.1.8"]}',
    '{"type":"as","data":["phone"]}'
  ].join('\n')
  const snapshot = Model.parseKdeSnapshot(raw)
  assert.equal(snapshot.ok, true)
  assert.deepEqual(JSON.parse(JSON.stringify(snapshot.devices)), [
    { id: 'laptop', name: 'Laptop', reachable: false, paired: true, pairRequestedByPeer: false },
    { id: 'phone', name: 'Pixel', reachable: true, paired: true, pairRequestedByPeer: true }
  ])
  assert.deepEqual(Array.from(snapshot.customAddresses), ['100.64.0.2', '192.168.1.8'])
})

test('parses and sorts Tailscale peers with usable IPv4 addresses', () => {
  const status = Model.parseTailscaleStatus(JSON.stringify({
    BackendState: 'Running',
    Self: { TailscaleIPs: ['100.64.0.1', 'fd7a::1'] },
    Peer: {
      offline: { ID: '2', HostName: 'old-phone', Online: false, TailscaleIPs: ['100.64.0.9'] },
      online: { ID: '1', HostName: 'Pixel Phone', DNSName: 'my-pixel.example.ts.net.', OS: 'android', Online: true, TailscaleIPs: ['100.64.0.2', 'fd7a::2'] }
    }
  }))
  assert.equal(status.ok, true)
  assert.equal(status.running, true)
  assert.equal(status.selfAddress, '100.64.0.1')
  assert.equal(status.peers.length, 2)
  assert.deepEqual(JSON.parse(JSON.stringify(status.peers[0])), {
    id: '1',
    name: 'my-pixel',
    machineName: 'my-pixel',
    hostName: 'Pixel Phone',
    dnsName: 'my-pixel.example.ts.net',
    address: '100.64.0.2',
    online: true,
    os: 'android'
  })
  assert.deepEqual(
    Array.from(Model.filterTailscalePeers(status.peers, 'pixel phone', 8), peer => peer.address),
    ['100.64.0.2']
  )
  assert.deepEqual(
    Array.from(Model.filterTailscalePeers(status.peers, '100.64.0.9', 8), peer => peer.name),
    ['old-phone']
  )
})
