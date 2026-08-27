import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "ProcessLimits.js" as ProcessLimits

Item {
  id: root

  property bool active: false
  property bool environmentChecked: false
  property bool kdeInstalled: false
  property bool kdeAppInstalled: false
  property bool kdeReady: false
  property bool kdePortsListening: false
  property bool tailscaleInstalled: false
  property bool tailscaleRunning: false
  property string tailscaleStatus: "Checking…"
  property string localLanAddress: ""
  property string localTailscaleAddress: ""
  property var devices: []
  property var customAddresses: []
  property var tailscalePeers: []
  property string actionMessage: ""
  property string actionLevel: "info"
  property string pairingDeviceId: ""
  property string waitingPairId: ""
  property string watchingAddress: ""
  property var discoveryBaseline: []

  property string _actionKind: ""
  property string _actionDeviceId: ""
  property string _actionDeviceName: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property var _pendingAddresses: []
  property string _pendingAddress: ""
  property bool _pendingRemoval: false
  property string _snapshotOutput: ""
  property string _snapshotError: ""
  property string _tailscaleOutput: ""
  property string _tailscaleError: ""
  property int discoveryTicks: 0
  property int pairTicks: 0

  readonly property var connectedDevices: Model.devicesByState(devices, true, true)
  readonly property var discoveredDevices: Model.devicesByState(devices, false, true)
  readonly property var rememberedDevices: Model.devicesByState(devices, true, false)
  readonly property bool refreshing: environmentProcess.running || snapshotProcess.running || tailscaleProcess.running || discoveryProcess.running
  readonly property bool actionBusy: actionProcess.running || customDevicesProcess.running
  readonly property bool eventMonitorRunning: kdeEventMonitor.running

  readonly property string snapshotScript: [
    "set -e",
    "busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon deviceNames bb false false",
    "busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon devices bb false false",
    "busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon devices bb true false",
    "busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon devices bb false true",
    "busctl --user get-property --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon customDevices",
    "busctl --user get-property --json=short org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon pairingRequests",
    "device_count=0",
    "for id in $(kdeconnect-cli --list-devices --id-only 2>/dev/null | head -c 32768 || true); do",
    "  case \"$id\" in ''|*[!A-Za-z0-9_]*) continue ;; esac",
    "  [ \"${#id}\" -le 128 ] || continue",
    "  device_count=$((device_count + 1))",
    "  [ \"$device_count\" -le 256 ] || break",
    "  printf '__DEVICE__%s\\n' \"$id\"",
    "  busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect/devices/$id org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device 2>/dev/null || printf '{}\\n'",
    "  busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect/devices/$id org.kde.kdeconnect.device loadedPlugins 2>/dev/null || printf '{}\\n'",
    "  busctl --user call --json=short org.kde.kdeconnect /modules/kdeconnect/devices/$id/battery org.freedesktop.DBus.Properties GetAll s org.kde.kdeconnect.device.battery 2>/dev/null || printf '{\"type\":\"a{sv}\",\"data\":[{}]}\\n'",
    "done"
  ].join("\n")

  function addressError(value) {
    return Model.addressError(value)
  }

  function isAddressSaved(value) {
    return customAddresses.indexOf(Model.normalizeAddress(value)) !== -1
  }

  function filteredTailscalePeers(value, limit) {
    return Model.filterTailscalePeers(tailscalePeers, value, limit)
  }

  function deviceSupports(device, plugin) {
    return Model.deviceSupports(device, plugin)
  }

  function batteryText(device) {
    return Model.batteryText(device)
  }

  function parseFilePickerOutput(output) {
    return Model.parseFilePickerOutput(output)
  }

  function diagnosticText() {
    var lines = []
    if (!kdeInstalled) lines.push("Install required package: sudo pacman -S kdeconnect")
    else if (!kdeReady) lines.push("KDE Connect is D-Bus activated. Refresh here, or run: kdeconnect-cli --list-devices")
    else lines.push("The KDE Connect daemon is available; the settings window does not need to stay open.")

    if (!tailscaleInstalled) lines.push("Optional cross-network support: sudo pacman -S tailscale")
    else if (!tailscaleRunning) lines.push("For cross-network discovery, check: systemctl status tailscaled; then run: tailscale up")
    else lines.push("Tailscale is connected. Select a peer below to save its stable address in KDE Connect.")

    lines.push(kdePortsListening
      ? "KDE Connect is listening within its TCP/UDP 1714–1764 range."
      : "No KDE Connect listener was detected. Run kdeconnect-cli --refresh, then refresh this panel.")
    lines.push("If discovery still fails, allow TCP and UDP 1714–1764 on the LAN or Tailscale interface. OmaKDEConnect never changes firewall rules or runs sudo.")
    return lines.join("\n\n")
  }

  function deviceName(id) {
    for (var i = 0; i < devices.length; i++) if (devices[i].id === id) return devices[i].name
    return id
  }

  function elideError(value, fallback) {
    var text = String(value || fallback || "Operation failed").replace(/\s+/g, " ").trim()
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function processError(exitCode, value, fallback) {
    if (exitCode === ProcessLimits.TRUNCATED_EXIT_CODE) return fallback + " (output exceeded safe limit)"
    return elideError(value, fallback)
  }

  function showMessage(message, level, notifyUser) {
    actionMessage = String(message || "")
    actionLevel = level || "info"
    messageTimer.restart()
    if (notifyUser === true) notify(actionLevel === "error" ? "KDE Connect error" : "KDE Connect", actionMessage, actionLevel === "error")
  }

  function notify(summary, body, error) {
    var args = ["omarchy-notification-send", "-g", error ? "󰅙" : "󰄬"]
    if (error) args = args.concat(["-u", "critical"])
    args = args.concat([summary, body])
    Quickshell.execDetached(args)
  }

  function refreshAll() {
    checkEnvironment()
  }

  function checkEnvironment() {
    if (environmentProcess.running) return
    environmentProcess.running = true
  }

  function refreshKdeSnapshot() {
    if (!kdeInstalled || snapshotProcess.running) return
    _snapshotOutput = ""
    _snapshotError = ""
    snapshotProcess.command = ProcessLimits.boundedCommand(["bash", "-c", snapshotScript], 262144, 16384)
    snapshotProcess.running = true
    pollWatchdog.restart()
  }

  function refreshTailscale() {
    if (!tailscaleInstalled || tailscaleProcess.running) return
    _tailscaleOutput = ""
    _tailscaleError = ""
    tailscaleProcess.command = ProcessLimits.boundedCommand(["tailscale", "status", "--json"], 1048576, 16384)
    tailscaleProcess.running = true
    pollWatchdog.restart()
  }

  function reachableIds() {
    var ids = []
    for (var i = 0; i < devices.length; i++) if (devices[i].reachable) ids.push(devices[i].id)
    return ids
  }

  function beginDiscoveryWatch(address) {
    watchingAddress = String(address || "")
    discoveryBaseline = reachableIds()
    discoveryTicks = 0
    discoveryWatchTimer.restart()
    delayedSnapshot.restart()
  }

  function detectNewReachableDevice() {
    if (!discoveryWatchTimer.running) return false
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (device.reachable && discoveryBaseline.indexOf(device.id) === -1) {
        discoveryWatchTimer.stop()
        var message = device.paired
          ? device.name + " is connected"
          : device.name + " found — choose Pair below"
        showMessage(message, "success", true)
        watchingAddress = ""
        return true
      }
    }
    return false
  }

  function applyKdeSnapshot(snapshot) {
    devices = snapshot.devices
    customAddresses = snapshot.customAddresses
    kdeReady = true

    if (waitingPairId !== "") {
      for (var i = 0; i < devices.length; i++) {
        if (devices[i].id === waitingPairId && devices[i].paired) {
          var pairedName = devices[i].name
          waitingPairId = ""
          pairWatchTimer.stop()
          showMessage("Paired with " + pairedName, "success", true)
          break
        }
      }
    }
    detectNewReachableDevice()
  }

  function startDiscovery(address) {
    if (!kdeInstalled || discoveryProcess.running) return
    if (!kdeReady) {
      showMessage("KDE Connect daemon is not available", "error", false)
      return
    }
    watchingAddress = String(address || "")
    discoveryProcess.command = ProcessLimits.boundedCommand(["env", "LC_ALL=C", "kdeconnect-cli", "--refresh"], 16384, 16384)
    discoveryProcess.running = true
    showMessage(address ? "Discovering KDE Connect at " + address + "…" : "Discovering KDE Connect devices…", "info", false)
  }

  function addCustomAddress(value) {
    var error = Model.addressError(value)
    if (error !== "") return false
    var address = Model.normalizeAddress(value)
    if (isAddressSaved(address)) {
      startDiscovery(address)
      return true
    }
    writeCustomAddresses(Model.withAddress(customAddresses, address), address, false)
    return true
  }

  function removeCustomAddress(value) {
    var address = Model.normalizeAddress(value)
    if (!isAddressSaved(address)) return
    writeCustomAddresses(Model.withoutAddress(customAddresses, address), address, true)
  }

  function writeCustomAddresses(addresses, address, removal) {
    if (!kdeReady || customDevicesProcess.running) return
    _pendingAddresses = addresses
    _pendingAddress = address
    _pendingRemoval = removal
    var command = [
      "busctl", "--user", "set-property",
      "org.kde.kdeconnect", "/modules/kdeconnect", "org.kde.kdeconnect.daemon",
      "customDevices", "as", String(addresses.length)
    ].concat(addresses)
    customDevicesProcess.command = ProcessLimits.boundedCommand(command, 16384, 16384)
    customDevicesProcess.running = true
    showMessage(removal ? "Removing saved address…" : "Saving address and starting discovery…", "info", false)
  }

  function pairDevice(device) {
    if (!device || actionProcess.running) return
    pairingDeviceId = device.id
    runAction("pair", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", device.id, "--pair"], device)
    showMessage("Sending pair request to " + device.name + "…", "info", false)
  }

  function acceptPairing(device) {
    if (!device || actionProcess.running) return
    pairingDeviceId = device.id
    runAction("accept", [
      "busctl", "--user", "call", "org.kde.kdeconnect",
      "/modules/kdeconnect/devices/" + device.id,
      "org.kde.kdeconnect.device", "acceptPairing"
    ], device)
    showMessage("Accepting pair request from " + device.name + "…", "info", false)
  }

  function rejectPairing(device) {
    if (!device || actionProcess.running) return
    runAction("reject", [
      "busctl", "--user", "call", "org.kde.kdeconnect",
      "/modules/kdeconnect/devices/" + device.id,
      "org.kde.kdeconnect.device", "cancelPairing"
    ], device)
  }

  function sendClipboard(device) {
    if (!device || actionProcess.running) return
    runAction("clipboard", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", device.id, "--send-clipboard"], device)
  }

  function ringDevice(device) {
    if (!device || actionProcess.running) return
    runAction("ring", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", device.id, "--ring"], device)
  }

  function pingDevice(device) {
    if (!device || actionProcess.running) return
    runAction("ping", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", device.id, "--ping"], device)
  }

  function shareText(device, text) {
    var value = String(text || "")
    if (!device || actionProcess.running) return false
    if (value.trim() === "") {
      showMessage("Enter text to share", "warning", false)
      return false
    }
    runAction("text", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", device.id, "--share-text", value], device)
    return true
  }

  function shareFiles(deviceId, deviceNameValue, urls) {
    if (!deviceId || !urls || urls.length === 0 || actionProcess.running) return
    runAction("files", ["env", "LC_ALL=C", "kdeconnect-cli", "--device", deviceId, "--share"].concat(urls), {
      id: deviceId,
      name: deviceNameValue
    })
  }

  function runAction(kind, command, device) {
    _actionKind = kind
    _actionDeviceId = device.id
    _actionDeviceName = device.name
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = ProcessLimits.boundedCommand(["timeout", "45s"].concat(command), 16384, 16384)
    actionProcess.running = true
  }

  Timer {
    interval: root.active ? 60000 : 120000
    repeat: true
    running: true
    onTriggered: root.checkEnvironment()
  }

  Timer {
    id: eventRefreshTimer
    interval: 350
    repeat: false
    onTriggered: root.refreshKdeSnapshot()
  }

  Timer {
    id: eventMonitorRestart
    interval: 3000
    repeat: false
    onTriggered: if (root.kdeInstalled && !kdeEventMonitor.running) kdeEventMonitor.running = true
  }

  Timer {
    id: delayedSnapshot
    interval: 900
    repeat: false
    onTriggered: root.refreshKdeSnapshot()
  }

  Timer {
    id: discoveryWatchTimer
    interval: 2000
    repeat: true
    onTriggered: {
      root.discoveryTicks++
      if (root.discoveryTicks >= 10) {
        stop()
        var suffix = root.watchingAddress ? " at " + root.watchingAddress : ""
        root.showMessage("No new device found" + suffix + ". Check KDE Connect, Tailscale and firewall status.", "warning", false)
        root.watchingAddress = ""
      } else {
        root.refreshKdeSnapshot()
      }
    }
  }

  Timer {
    id: pairWatchTimer
    interval: 2000
    repeat: true
    onTriggered: {
      root.pairTicks++
      if (root.pairTicks >= 15) {
        stop()
        var name = root.deviceName(root.waitingPairId)
        root.waitingPairId = ""
        root.showMessage("Pairing with " + name + " was not confirmed", "warning", true)
      } else {
        root.refreshKdeSnapshot()
      }
    }
  }

  Timer {
    id: messageTimer
    interval: root.actionLevel === "error" ? 12000 : 8000
    repeat: false
    onTriggered: root.actionMessage = ""
  }

  Timer {
    id: pollWatchdog
    interval: 12000
    repeat: false
    onTriggered: {
      if (snapshotProcess.running) {
        snapshotProcess.running = false
        root.kdeReady = false
      }
      if (tailscaleProcess.running) {
        tailscaleProcess.running = false
        root.tailscaleRunning = false
        root.tailscaleStatus = "Status timed out"
        root.localTailscaleAddress = ""
      }
    }
  }

  Process {
    id: environmentProcess
    command: ProcessLimits.boundedCommand(["bash", "-c", [
      "command -v kdeconnect-cli >/dev/null && echo kde=1 || echo kde=0",
      "command -v kdeconnect-app >/dev/null && echo app=1 || echo app=0",
      "command -v tailscale >/dev/null && echo tailscale=1 || echo tailscale=0",
      "lan_dev=$(ip -4 route show default 2>/dev/null | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p' | head -n 1)",
      "lan_ip=$(ip -4 -o addr show dev \"$lan_dev\" scope global 2>/dev/null | awk 'NR == 1 { print $4 }' | cut -d/ -f1)",
      "printf 'lan=%s\\n' \"$lan_ip\"",
      "ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq ':(171[4-9]|17[2-5][0-9]|176[0-4])$' && echo ports=1 || echo ports=0"
    ].join("; ")], 8192, 8192)
    running: false
    stdout: StdioCollector { id: environmentStdout; waitForEnd: true }
    onExited: function() {
      var output = String(environmentStdout.text || "")
      var lanMatch = output.match(/^lan=(.*)$/m)
      var lanAddress = lanMatch ? String(lanMatch[1]).trim() : ""
      root.environmentChecked = true
      root.kdeInstalled = output.indexOf("kde=1") !== -1
      root.kdeAppInstalled = output.indexOf("app=1") !== -1
      root.kdePortsListening = output.indexOf("ports=1") !== -1
      root.tailscaleInstalled = output.indexOf("tailscale=1") !== -1
      root.localLanAddress = Model.isValidIpv4(lanAddress) ? lanAddress : ""
      if (root.kdeInstalled) {
        root.refreshKdeSnapshot()
        if (!kdeEventMonitor.running) kdeEventMonitor.running = true
      }
      else {
        kdeEventMonitor.running = false
        root.kdeReady = false
        root.devices = []
        root.customAddresses = []
      }
      if (root.tailscaleInstalled) root.refreshTailscale()
      else {
        root.tailscaleRunning = false
        root.tailscaleStatus = "Not installed (optional)"
        root.localTailscaleAddress = ""
        root.tailscalePeers = []
      }
    }
  }

  Process {
    id: kdeEventMonitor
    command: ProcessLimits.boundedEventCommand([
      "busctl", "--user", "monitor",
      "--match=type='signal',sender='org.kde.kdeconnect',path_namespace='/modules/kdeconnect'"
    ])
    running: false
    // Raw D-Bus fields are reduced to fixed "event\n" records before QML.
    stdout: SplitParser {
      onRead: function() { eventRefreshTimer.restart() }
    }
    onExited: if (root.kdeInstalled) eventMonitorRestart.restart()
  }

  Process {
    id: snapshotProcess
    running: false
    command: []
    stdout: StdioCollector { id: snapshotStdout; waitForEnd: true; onStreamFinished: root._snapshotOutput = text }
    stderr: StdioCollector { id: snapshotStderr; waitForEnd: true; onStreamFinished: root._snapshotError = text }
    onExited: function(exitCode) {
      var output = String(snapshotStdout.text || root._snapshotOutput || "")
      var error = String(snapshotStderr.text || root._snapshotError || "")
      if (exitCode === 0) {
        var snapshot = Model.parseKdeSnapshot(output)
        if (snapshot.ok) root.applyKdeSnapshot(snapshot)
        else {
          root.kdeReady = false
          root.showMessage(snapshot.error, "error", false)
        }
      } else {
        root.kdeReady = false
        root.showMessage(root.processError(exitCode, error || output, "KDE Connect daemon is unavailable"), "error", false)
      }
    }
  }

  Process {
    id: tailscaleProcess
    running: false
    command: []
    stdout: StdioCollector { id: tailscaleStdout; waitForEnd: true; onStreamFinished: root._tailscaleOutput = text }
    stderr: StdioCollector { id: tailscaleStderr; waitForEnd: true; onStreamFinished: root._tailscaleError = text }
    onExited: function(exitCode) {
      var output = String(tailscaleStdout.text || root._tailscaleOutput || "")
      var error = String(tailscaleStderr.text || root._tailscaleError || "")
      if (exitCode === 0) {
        var status = Model.parseTailscaleStatus(output)
        root.tailscaleRunning = status.ok && status.running
        root.tailscaleStatus = status.status
        root.localTailscaleAddress = status.selfAddress
        root.tailscalePeers = status.peers
      } else {
        root.tailscaleRunning = false
        root.tailscaleStatus = root.processError(exitCode, error || output, "Disconnected")
        root.localTailscaleAddress = ""
        root.tailscalePeers = []
      }
    }
  }

  Process {
    id: discoveryProcess
    running: false
    command: []
    stderr: StdioCollector { id: discoveryStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.beginDiscoveryWatch(root.watchingAddress)
      } else {
        root.showMessage(root.processError(exitCode, discoveryStderr.text, "Device discovery failed"), "error", true)
        root.watchingAddress = ""
      }
    }
  }

  Process {
    id: customDevicesProcess
    running: false
    command: []
    stderr: StdioCollector { id: customDevicesStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.customAddresses = root._pendingAddresses
        if (root._pendingRemoval) {
          root.showMessage("Removed saved address " + root._pendingAddress, "success", false)
          delayedSnapshot.restart()
        } else {
          root.showMessage("Saved " + root._pendingAddress + ". Waiting for KDE Connect…", "success", false)
          root.beginDiscoveryWatch(root._pendingAddress)
        }
      } else {
        root.showMessage(root.processError(exitCode, customDevicesStderr.text, "Could not save the address"), "error", true)
      }
      root._pendingAddresses = []
      root._pendingAddress = ""
      root._pendingRemoval = false
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var output = String(actionStdout.text || root._actionOutput || "")
      var error = String(actionStderr.text || root._actionError || "")
      if (exitCode === 124) {
        root.showMessage(root._actionKind + " timed out for " + root._actionDeviceName, "error", true)
        if (root._actionKind === "pair" || root._actionKind === "accept") root.pairingDeviceId = ""
      } else if (exitCode !== 0) {
        root.showMessage(root.processError(exitCode, error || output, root._actionKind + " failed"), "error", true)
        if (root._actionKind === "pair" || root._actionKind === "accept") root.pairingDeviceId = ""
      } else if (root._actionKind === "pair" || root._actionKind === "accept") {
        root.pairingDeviceId = ""
        root.waitingPairId = root._actionDeviceId
        root.pairTicks = 0
        pairWatchTimer.restart()
        root.showMessage(root._actionKind === "accept"
          ? "Pair request from " + root._actionDeviceName + " accepted. Waiting for completion…"
          : "Pair request sent to " + root._actionDeviceName + ". Confirm it on the other device.", "success", true)
      } else if (root._actionKind === "reject") {
        if (root.waitingPairId === root._actionDeviceId) root.waitingPairId = ""
        root.showMessage("Pair request from " + root._actionDeviceName + " rejected", "success", false)
      } else if (root._actionKind === "clipboard") {
        root.showMessage("Clipboard sent to " + root._actionDeviceName, "success", true)
      } else if (root._actionKind === "files") {
        root.showMessage("Files sent to " + root._actionDeviceName, "success", true)
      } else if (root._actionKind === "ring") {
        root.showMessage("Ringing " + root._actionDeviceName, "success", false)
      } else if (root._actionKind === "ping") {
        root.showMessage("Ping sent to " + root._actionDeviceName, "success", false)
      } else if (root._actionKind === "text") {
        root.showMessage("Text sent to " + root._actionDeviceName, "success", true)
      }
      delayedSnapshot.restart()
      root._actionKind = ""
      root._actionDeviceId = ""
      root._actionDeviceName = ""
    }
  }

  Component.onCompleted: root.checkEnvironment()
}
