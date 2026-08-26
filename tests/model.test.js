const fs = require('node:fs')
const vm = require('node:vm')
const test = require('node:test')
const assert = require('node:assert/strict')

const source = fs.readFileSync(new URL('../Model.js', `file://${__filename}`), 'utf8')
  .replace(/^\.pragma library\s*/m, '')
const context = {}
vm.createContext(context)
vm.runInContext(`${source}\nthis.Model = { normalizeAddress, isValidAddress, addressError, withAddress, withoutAddress, parseKdeSnapshot, deviceSupports, batteryText, parseTailscaleStatus, filterTailscalePeers, parseFilePickerOutput };`, context)
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
    '{"type":"as","data":["phone"]}',
    '__DEVICE__phone',
    '{"type":"a{sv}","data":[{"name":{"type":"s","data":"Pixel Phone"},"type":{"type":"s","data":"phone"},"isReachable":{"type":"b","data":true},"isPaired":{"type":"b","data":true},"isPairRequestedByPeer":{"type":"b","data":true},"verificationKey":{"type":"s","data":"AB12CD34"}}]}',
    '{"type":"as","data":[["kdeconnect_battery","kdeconnect_clipboard","kdeconnect_share"]]}',
    '{"type":"a{sv}","data":[{"charge":{"type":"i","data":87},"hasBattery":{"type":"b","data":true},"isCharging":{"type":"b","data":true}}]}',
    '__DEVICE__laptop',
    '{"type":"a{sv}","data":[{"name":{"type":"s","data":"Laptop"},"type":{"type":"s","data":"desktop"},"isReachable":{"type":"b","data":false},"isPaired":{"type":"b","data":true},"isPairRequestedByPeer":{"type":"b","data":false},"verificationKey":{"type":"s","data":""}}]}',
    '{"type":"as","data":[["kdeconnect_ping"]]}',
    '{"type":"a{sv}","data":[{}]}'
  ].join('\n')
  const snapshot = Model.parseKdeSnapshot(raw)
  assert.equal(snapshot.ok, true)
  assert.equal(snapshot.devices[0].id, 'laptop')
  assert.equal(snapshot.devices[0].reachable, false)
  assert.equal(snapshot.devices[0].capabilitiesKnown, true)
  assert.equal(Model.deviceSupports(snapshot.devices[0], 'kdeconnect_ping'), true)
  assert.equal(Model.deviceSupports(snapshot.devices[0], 'kdeconnect_share'), false)
  assert.equal(snapshot.devices[1].name, 'Pixel Phone')
  assert.equal(snapshot.devices[1].verificationKey, 'AB12CD34')
  assert.deepEqual(Array.from(snapshot.devices[1].plugins), ['kdeconnect_battery', 'kdeconnect_clipboard', 'kdeconnect_share'])
  assert.equal(Model.batteryText(snapshot.devices[1]), '87% battery · charging')
  assert.deepEqual(Array.from(snapshot.customAddresses), ['100.64.0.2', '192.168.1.8'])
})

test('keeps actions available when an older KDE snapshot has no capability metadata', () => {
  const raw = [
    '{"type":"a{ss}","data":[{"phone":"Pixel"}]}',
    '{"type":"as","data":[["phone"]]}',
    '{"type":"as","data":[["phone"]]}',
    '{"type":"as","data":[["phone"]]}',
    '{"type":"as","data":[]}',
    '{"type":"as","data":[]}'
  ].join('\n')
  const device = Model.parseKdeSnapshot(raw).devices[0]
  assert.equal(device.capabilitiesKnown, false)
  assert.equal(Model.deviceSupports(device, 'kdeconnect_clipboard'), true)
  assert.equal(Model.batteryText(device), '')
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

test('bounds KDE device counts, identifiers, and retained field sizes', () => {
  const names = {}
  const ids = []
  for (let index = 0; index < 300; index++) {
    const id = `device_${index}`
    names[id] = 'N'.repeat(400)
    ids.push(id)
  }
  ids.unshift('../unsafe', 'device_0')
  const snapshot = Model.parseKdeSnapshot([
    JSON.stringify({ data: [names] }),
    JSON.stringify({ data: [ids] }),
    JSON.stringify({ data: [ids] }),
    JSON.stringify({ data: [ids] }),
    JSON.stringify({ data: [] }),
    JSON.stringify({ data: [] })
  ].join('\n'))

  assert.equal(snapshot.ok, true)
  assert.equal(snapshot.devices.length, 256)
  assert.equal(snapshot.devices[0].id, 'device_0')
  assert.equal(snapshot.devices[0].name.length, 256)
  assert.equal(snapshot.devices.some(device => device.id === '../unsafe'), false)
})

test('bounds Tailscale peer counts and retained field sizes', () => {
  const peers = {}
  for (let index = 0; index < 600; index++) {
    peers[`key-${index}`] = {
      ID: `id-${index}-${'I'.repeat(200)}`,
      HostName: `host-${index}-${'H'.repeat(300)}`,
      DNSName: `machine-${index}.${'d'.repeat(300)}.`,
      OS: 'O'.repeat(100),
      Online: true,
      TailscaleIPs: [`100.64.${Math.floor(index / 256)}.${index % 256}`]
    }
  }
  const status = Model.parseTailscaleStatus(JSON.stringify({
    BackendState: 'Running',
    Self: { TailscaleIPs: ['100.64.0.1'] },
    Peer: peers
  }))

  assert.equal(status.peers.length, 512)
  assert.equal(status.peers[0].id.length, 128)
  assert.equal(status.peers[0].hostName.length, 256)
  assert.ok(status.peers[0].dnsName.length <= 253)
  assert.equal(status.peers[0].os.length, 64)
})

test('bounds file-picker paths without retaining an unbounded line array', () => {
  const paths = ['/'.concat('x'.repeat(4096))]
  for (let index = 0; index < 140; index++) paths.push(`/tmp/file-${index}`)
  const selected = Model.parseFilePickerOutput(paths.join('\n'))

  assert.equal(selected.length, 128)
  assert.equal(selected[0], '/tmp/file-0')
  assert.equal(selected[127], '/tmp/file-127')
})
