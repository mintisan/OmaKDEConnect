.pragma library

var MAX_ADDRESS_LENGTH = 128
var MAX_CUSTOM_ADDRESSES = 256
var MAX_DEVICES = 256
var MAX_DEVICE_ID_LENGTH = 128
var MAX_DEVICE_NAME_LENGTH = 256
var MAX_DEVICE_TYPE_LENGTH = 64
var MAX_VERIFICATION_KEY_LENGTH = 128
var MAX_PLUGINS = 128
var MAX_PLUGIN_NAME_LENGTH = 128
var MAX_PEERS = 512
var MAX_PEER_ID_LENGTH = 128
var MAX_DNS_NAME_LENGTH = 253
var MAX_OS_LENGTH = 64
var MAX_FILTER_LENGTH = 256
var MAX_FILES = 128
var MAX_FILE_PATH_LENGTH = 4096

function trimText(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function limitedText(value, maximum) {
  var text = trimText(value)
  return text.length > maximum ? text.substring(0, maximum) : text
}

function normalizeAddress(value) {
  var address = trimText(value)
  if (address.length > MAX_ADDRESS_LENGTH) return ""
  if (address.length > 2 && address[0] === "[" && address[address.length - 1] === "]")
    address = address.substring(1, address.length - 1)
  return address
}

function isValidIpv4(value) {
  var text = String(value)
  if (text.length < 7 || text.length > 15) return false
  var parts = text.split(".")
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
  if (address.length < 2 || address.length > MAX_ADDRESS_LENGTH) return false
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
  if (trimText(value).length > MAX_ADDRESS_LENGTH) return "IP address is too long"
  var address = normalizeAddress(value)
  if (address === "") return "Enter an IPv4 or IPv6 address"
  if (!isValidAddress(address)) return "Enter an IP address without a port or URL"
  return ""
}

function uniqueAddresses(values) {
  var result = []
  var source = values || []
  var inputLimit = Math.min(source.length, MAX_CUSTOM_ADDRESSES * 2)
  for (var i = 0; i < inputLimit && result.length < MAX_CUSTOM_ADDRESSES; i++) {
    if (String(source[i] === undefined || source[i] === null ? "" : source[i]).length > MAX_ADDRESS_LENGTH) continue
    var address = normalizeAddress(source[i])
    if (isValidAddress(address) && result.indexOf(address) === -1) result.push(address)
  }
  return result
}

function withAddress(values, value) {
  var result = uniqueAddresses(values)
  var address = normalizeAddress(value)
  if (result.length < MAX_CUSTOM_ADDRESSES && isValidAddress(address) && result.indexOf(address) === -1) result.push(address)
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

function limitedArray(values, maximum) {
  var source = values instanceof Array ? values : []
  var result = []
  for (var i = 0; i < source.length && result.length < maximum; i++) result.push(source[i])
  return result
}

function callArray(payload, maximum) {
  if (!payload || !(payload.data instanceof Array) || payload.data.length === 0) return []
  return limitedArray(payload.data[0], maximum || MAX_DEVICES)
}

function propertyArray(payload, maximum) {
  return limitedArray(payload && payload.data instanceof Array ? payload.data : [], maximum || MAX_DEVICES)
}

function propertyMap(payload) {
  if (!payload || !(payload.data instanceof Array) || payload.data.length === 0) return null
  var value = payload.data[0]
  return value && typeof value === "object" && !(value instanceof Array) ? value : null
}

function variantValue(properties, name, fallback) {
  var value = properties ? properties[name] : null
  return value && value.data !== undefined ? value.data : fallback
}

function isSafeDeviceId(value) {
  var id = String(value === undefined || value === null ? "" : value)
  return id.length <= MAX_DEVICE_ID_LENGTH && /^[A-Za-z0-9_]+$/.test(id)
}

function snapshotLines(raw) {
  var text = String(raw || "")
  var maximum = 6 + MAX_DEVICES * 4
  var lines = []
  var start = 0
  while (start <= text.length && lines.length < maximum) {
    var end = text.indexOf("\n", start)
    if (end === -1) end = text.length
    var line = text.substring(start, end)
    if (line.length > 0 && line[line.length - 1] === "\r") line = line.substring(0, line.length - 1)
    if (line.trim() !== "") lines.push(line)
    if (end === text.length) break
    start = end + 1
  }
  return lines
}

function deviceMetadata(lines) {
  var result = {}
  var retained = 0
  for (var i = 6; i + 3 < lines.length && retained < MAX_DEVICES; i++) {
    var marker = String(lines[i] || "")
    if (marker.indexOf("__DEVICE__") !== 0) continue
    var id = marker.substring(10)
    if (!isSafeDeviceId(id) || result[id] !== undefined) {
      i += 3
      continue
    }
    var propertiesPayload = parseJson(lines[i + 1])
    var pluginsPayload = parseJson(lines[i + 2])
    var batteryPayload = parseJson(lines[i + 3])
    var properties = propertyMap(propertiesPayload)
    var battery = propertyMap(batteryPayload)
    var rawPlugins = callArray(pluginsPayload, MAX_PLUGINS)
    var plugins = []
    for (var pluginIndex = 0; pluginIndex < rawPlugins.length && plugins.length < MAX_PLUGINS; pluginIndex++) {
      var plugin = String(rawPlugins[pluginIndex] === undefined || rawPlugins[pluginIndex] === null ? "" : rawPlugins[pluginIndex])
      if (plugin.length > 0 && plugin.length <= MAX_PLUGIN_NAME_LENGTH && plugins.indexOf(plugin) === -1) plugins.push(plugin)
    }
    var charge = Number(variantValue(battery, "charge", -1))
    result[id] = {
      properties: properties,
      capabilitiesKnown: properties !== null && pluginsPayload !== null && pluginsPayload.data instanceof Array,
      plugins: plugins,
      batteryAvailable: variantValue(battery, "hasBattery", false) === true && charge >= 0,
      batteryCharge: charge >= 0 ? Math.max(0, Math.min(100, Math.round(charge))) : -1,
      batteryCharging: variantValue(battery, "isCharging", false) === true
    }
    retained++
    i += 3
  }
  return result
}

function parseKdeSnapshot(raw) {
  var lines = snapshotLines(raw)
  if (lines.length < 6) return { ok: false, error: "Incomplete KDE Connect status response" }

  var namesPayload = parseJson(lines[0])
  var allPayload = parseJson(lines[1])
  var reachablePayload = parseJson(lines[2])
  var pairedPayload = parseJson(lines[3])
  var customPayload = parseJson(lines[4])
  var pairingRequestsPayload = parseJson(lines[5])
  if (!namesPayload || !allPayload || !reachablePayload || !pairedPayload || !customPayload || !pairingRequestsPayload)
    return { ok: false, error: "Invalid KDE Connect status response" }

  var names = namesPayload.data instanceof Array && namesPayload.data.length > 0 ? namesPayload.data[0] : {}
  var all = callArray(allPayload, MAX_DEVICES * 2)
  var reachable = callArray(reachablePayload, MAX_DEVICES * 2)
  var paired = callArray(pairedPayload, MAX_DEVICES * 2)
  var pairingRequests = propertyArray(pairingRequestsPayload, MAX_DEVICES * 2)
  var metadata = deviceMetadata(lines)
  var devices = []
  var seen = {}
  for (var i = 0; i < all.length && devices.length < MAX_DEVICES; i++) {
    var id = String(all[i])
    if (!isSafeDeviceId(id) || seen[id] === true) continue
    seen[id] = true
    var details = metadata[id] || {}
    var properties = details.properties || null
    devices.push({
      id: id,
      name: limitedText(variantValue(properties, "name", names[id] || id), MAX_DEVICE_NAME_LENGTH) || id,
      type: limitedText(variantValue(properties, "type", ""), MAX_DEVICE_TYPE_LENGTH),
      reachable: variantValue(properties, "isReachable", reachable.indexOf(id) !== -1) === true,
      paired: variantValue(properties, "isPaired", paired.indexOf(id) !== -1) === true,
      pairRequestedByPeer: variantValue(properties, "isPairRequestedByPeer", pairingRequests.indexOf(id) !== -1) === true,
      verificationKey: limitedText(variantValue(properties, "verificationKey", ""), MAX_VERIFICATION_KEY_LENGTH),
      capabilitiesKnown: details.capabilitiesKnown === true,
      plugins: details.plugins || [],
      batteryAvailable: details.batteryAvailable === true,
      batteryCharge: details.batteryCharge === undefined ? -1 : details.batteryCharge,
      batteryCharging: details.batteryCharging === true
    })
  }
  devices.sort(function(a, b) { return a.name.localeCompare(b.name) })

  return {
    ok: true,
    devices: devices,
    customAddresses: uniqueAddresses(propertyArray(customPayload, MAX_CUSTOM_ADDRESSES * 2))
  }
}

function devicesByState(devices, paired, reachable) {
  return (devices || []).filter(function(device) {
    return device.paired === paired && device.reachable === reachable
  })
}

function deviceSupports(device, plugin) {
  if (!device || device.capabilitiesKnown !== true) return true
  return (device.plugins || []).indexOf(plugin) !== -1
}

function batteryText(device) {
  if (!device || device.batteryAvailable !== true || Number(device.batteryCharge) < 0) return ""
  return String(device.batteryCharge) + "% battery" + (device.batteryCharging === true ? " · charging" : "")
}

function cleanDnsName(value) {
  var name = limitedText(value, MAX_DNS_NAME_LENGTH)
  return name.length > 0 && name[name.length - 1] === "." ? name.substring(0, name.length - 1) : name
}

function machineNameFromDnsName(value) {
  var dnsName = cleanDnsName(value)
  var separator = dnsName.indexOf(".")
  return separator === -1 ? dnsName : dnsName.substring(0, separator)
}

function firstIpv4(values) {
  for (var i = 0; i < (values || []).length && i < 32; i++) {
    if (isValidIpv4(values[i])) return String(values[i])
  }
  return ""
}

function parseTailscaleStatus(raw) {
  var payload = parseJson(raw)
  if (!payload) return { ok: false, running: false, status: "Invalid Tailscale status", selfAddress: "", peers: [] }

  var backendState = limitedText(payload.BackendState, MAX_OS_LENGTH) || "Unknown"
  var running = backendState === "Running"
  var selfAddress = firstIpv4((payload.Self || {}).TailscaleIPs || [])
  var peers = []
  var source = payload.Peer || {}
  var inspected = 0
  for (var key in source) {
    if (inspected >= MAX_PEERS * 2 || peers.length >= MAX_PEERS) break
    inspected++
    var peer = source[key] || {}
    var address = firstIpv4(peer.TailscaleIPs || [])
    if (address === "") continue
    var dnsName = cleanDnsName(peer.DNSName)
    var machineName = limitedText(machineNameFromDnsName(dnsName), MAX_DEVICE_NAME_LENGTH)
    var hostName = limitedText(peer.HostName, MAX_DEVICE_NAME_LENGTH)
    peers.push({
      id: limitedText(peer.ID || key, MAX_PEER_ID_LENGTH),
      name: machineName || hostName || address,
      machineName: machineName || hostName || address,
      hostName: hostName,
      dnsName: dnsName,
      address: address,
      online: peer.Online === true,
      os: limitedText(peer.OS, MAX_OS_LENGTH)
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
  var query = limitedText(value, MAX_FILTER_LENGTH).toLowerCase()
  var maximum = Math.floor(Number(limit))
  if (!isFinite(maximum) || maximum <= 0) maximum = Math.min((peers || []).length, MAX_PEERS)
  else maximum = Math.min(maximum, MAX_PEERS)
  var matches = []
  for (var i = 0; i < (peers || []).length && i < MAX_PEERS && matches.length < maximum; i++) {
    var peer = peers[i] || {}
    var searchText = [
      limitedText(peer.machineName, MAX_DEVICE_NAME_LENGTH),
      limitedText(peer.hostName, MAX_DEVICE_NAME_LENGTH),
      limitedText(peer.dnsName, MAX_DNS_NAME_LENGTH),
      limitedText(peer.address, MAX_ADDRESS_LENGTH),
      limitedText(peer.os, MAX_OS_LENGTH)
    ].join("\n").toLowerCase()
    if (query === "" || searchText.indexOf(query) !== -1) matches.push(peer)
  }
  return matches
}

function parseFilePickerOutput(raw) {
  var text = String(raw || "")
  var paths = []
  var start = 0
  while (start <= text.length && paths.length < MAX_FILES) {
    var end = text.indexOf("\n", start)
    if (end === -1) end = text.length
    var path = text.substring(start, end)
    if (path.length > 0 && path[path.length - 1] === "\r") path = path.substring(0, path.length - 1)
    if (path.length > 0 && path.length <= MAX_FILE_PATH_LENGTH) paths.push(path)
    if (end === text.length) break
    start = end + 1
  }
  return paths
}
