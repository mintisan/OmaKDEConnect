.pragma library

function trimText(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function normalizeAddress(value) {
  var address = trimText(value)
  if (address.length > 2 && address[0] === "[" && address[address.length - 1] === "]")
    address = address.substring(1, address.length - 1)
  return address
}

function isValidIpv4(value) {
  var parts = String(value).split(".")
  if (parts.length !== 4) return false
  for (var i = 0; i < parts.length; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return false
    var number = parseInt(parts[i], 10)
    if (number < 0 || number > 255) return false
  }
  return true
}

function ipv6PartCount(parts) {
  var count = 0
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "") continue
    if (parts[i].indexOf(".") !== -1) {
      if (i !== parts.length - 1 || !isValidIpv4(parts[i])) return -1
      count += 2
    } else {
      if (!/^[0-9a-fA-F]{1,4}$/.test(parts[i])) return -1
      count++
    }
  }
  return count
}

function isValidIpv6(value) {
  var address = String(value)
  var zone = address.indexOf("%")
  if (zone !== -1) {
    if (zone === address.length - 1 || address.indexOf("%", zone + 1) !== -1) return false
    address = address.substring(0, zone)
  }
  if (address.indexOf(":") === -1) return false

  var compressed = address.indexOf("::")
  if (compressed !== -1 && address.indexOf("::", compressed + 2) !== -1) return false
  var count = ipv6PartCount(address.split(":"))
  if (count < 0) return false
  return compressed === -1 ? count === 8 : count < 8
}

function isValidAddress(value) {
  var address = normalizeAddress(value)
  return isValidIpv4(address) || isValidIpv6(address)
}

function addressError(value) {
  var address = normalizeAddress(value)
  if (address === "") return "Enter an IPv4 or IPv6 address"
  if (!isValidAddress(address)) return "Enter an IP address without a port or URL"
  return ""
}

function uniqueAddresses(values) {
  var result = []
  for (var i = 0; i < (values || []).length; i++) {
    var address = normalizeAddress(values[i])
    if (isValidAddress(address) && result.indexOf(address) === -1) result.push(address)
  }
  return result
}

function withAddress(values, value) {
  var result = uniqueAddresses(values)
  var address = normalizeAddress(value)
  if (isValidAddress(address) && result.indexOf(address) === -1) result.push(address)
  return result
}

function withoutAddress(values, value) {
  var remove = normalizeAddress(value)
  return uniqueAddresses(values).filter(function(address) { return address !== remove })
}

function parseJson(value) {
  try {
    return JSON.parse(String(value || ""))
  } catch (error) {
    return null
  }
}

function callArray(payload) {
  if (!payload || !(payload.data instanceof Array) || payload.data.length === 0) return []
  return payload.data[0] instanceof Array ? payload.data[0] : []
}

function propertyArray(payload) {
  return payload && payload.data instanceof Array ? payload.data : []
}

function parseKdeSnapshot(raw) {
  var lines = String(raw || "").split(/\r?\n/).filter(function(line) { return line.trim() !== "" })
  if (lines.length !== 6) return { ok: false, error: "Incomplete KDE Connect status response" }

  var namesPayload = parseJson(lines[0])
  var allPayload = parseJson(lines[1])
  var reachablePayload = parseJson(lines[2])
  var pairedPayload = parseJson(lines[3])
  var customPayload = parseJson(lines[4])
  var pairingRequestsPayload = parseJson(lines[5])
  if (!namesPayload || !allPayload || !reachablePayload || !pairedPayload || !customPayload || !pairingRequestsPayload)
    return { ok: false, error: "Invalid KDE Connect status response" }

  var names = namesPayload.data instanceof Array && namesPayload.data.length > 0 ? namesPayload.data[0] : {}
  var all = callArray(allPayload)
  var reachable = callArray(reachablePayload)
  var paired = callArray(pairedPayload)
  var pairingRequests = propertyArray(pairingRequestsPayload)
  var devices = []
  for (var i = 0; i < all.length; i++) {
    var id = String(all[i])
    devices.push({
      id: id,
      name: String(names[id] || id),
      reachable: reachable.indexOf(id) !== -1,
      paired: paired.indexOf(id) !== -1,
      pairRequestedByPeer: pairingRequests.indexOf(id) !== -1
    })
  }
  devices.sort(function(a, b) { return a.name.localeCompare(b.name) })

  return {
    ok: true,
    devices: devices,
    customAddresses: uniqueAddresses(propertyArray(customPayload))
  }
}

function devicesByState(devices, paired, reachable) {
  return (devices || []).filter(function(device) {
    return device.paired === paired && device.reachable === reachable
  })
}

function cleanDnsName(value) {
  var name = trimText(value)
  return name.length > 0 && name[name.length - 1] === "." ? name.substring(0, name.length - 1) : name
}

function machineNameFromDnsName(value) {
  var dnsName = cleanDnsName(value)
  var separator = dnsName.indexOf(".")
  return separator === -1 ? dnsName : dnsName.substring(0, separator)
}

function firstIpv4(values) {
  for (var i = 0; i < (values || []).length; i++) {
    if (isValidIpv4(values[i])) return String(values[i])
  }
  return ""
}

function parseTailscaleStatus(raw) {
  var payload = parseJson(raw)
  if (!payload) return { ok: false, running: false, status: "Invalid Tailscale status", selfAddress: "", peers: [] }

  var backendState = trimText(payload.BackendState) || "Unknown"
  var running = backendState === "Running"
  var selfAddress = firstIpv4((payload.Self || {}).TailscaleIPs || [])
  var peers = []
  var source = payload.Peer || {}
  for (var key in source) {
    var peer = source[key] || {}
    var address = firstIpv4(peer.TailscaleIPs || [])
    if (address === "") continue
    var dnsName = cleanDnsName(peer.DNSName)
    var machineName = machineNameFromDnsName(dnsName)
    var hostName = trimText(peer.HostName)
    peers.push({
      id: String(peer.ID || key),
      name: machineName || hostName || address,
      machineName: machineName || hostName || address,
      hostName: hostName,
      dnsName: dnsName,
      address: address,
      online: peer.Online === true,
      os: trimText(peer.OS)
    })
  }
  peers.sort(function(a, b) {
    if (a.online !== b.online) return a.online ? -1 : 1
    return a.name.localeCompare(b.name)
  })

  return {
    ok: true,
    running: running,
    status: running ? "Connected" : (backendState === "NeedsLogin" ? "Needs login" : backendState),
    selfAddress: running ? selfAddress : "",
    peers: running ? peers : []
  }
}

function filterTailscalePeers(peers, value, limit) {
  var query = trimText(value).toLowerCase()
  var maximum = Number(limit)
  if (!isFinite(maximum) || maximum <= 0) maximum = (peers || []).length
  var matches = []
  for (var i = 0; i < (peers || []).length && matches.length < maximum; i++) {
    var peer = peers[i] || {}
    var searchText = [peer.machineName, peer.hostName, peer.dnsName, peer.address, peer.os].join("\n").toLowerCase()
    if (query === "" || searchText.indexOf(query) !== -1) matches.push(peer)
  }
  return matches
}
