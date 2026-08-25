import QtQuick
import QtQuick.Controls as QQC2
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "omakdeconnect"
  ipcTarget: "omakdeconnect"
  manageIpc: false

  property int selectedIndex: 0
  property string pendingFileDeviceId: ""
  property string pendingFileDeviceName: ""
  property string manualAddressError: ""
  property string _filePickerOutput: ""
  property string _filePickerError: ""

  readonly property int deviceCount: connection.connectedDevices.length
  readonly property bool connected: deviceCount > 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dimmedForeground: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool manualAddressValid: connection.addressError(addressField.text) === ""
  readonly property var tailscaleMatches: connection.filteredTailscalePeers(addressField.text, 8)
  readonly property var notificationService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null

  function clampSelection() {
    if (deviceCount <= 0) {
      selectedIndex = 0
      return
    }
    selectedIndex = Math.max(0, Math.min(deviceCount - 1, selectedIndex))
  }

  function moveSelection(delta) {
    if (deviceCount <= 0) return
    selectedIndex = Math.max(0, Math.min(deviceCount - 1, selectedIndex + delta))
    scrollSelectedDeviceIntoView()
  }

  function selectedDevice() {
    if (deviceCount <= 0) return null
    return connection.connectedDevices[selectedIndex]
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(6)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollSelectedDeviceIntoView() {
    if (connectedDeviceColumn && selectedIndex >= 0 && selectedIndex < connectedDeviceColumn.children.length)
      scrollItemIntoView(connectedDeviceColumn.children[selectedIndex])
  }

  function sendSelectedClipboard() {
    connection.sendClipboard(selectedDevice())
  }

  function chooseFiles(device) {
    if (!device || filePickerProcess.running) return
    pendingFileDeviceId = device.id
    pendingFileDeviceName = device.name
    _filePickerOutput = ""
    _filePickerError = ""
    close()
    filePickerProcess.command = ["omarchy-file-select", "--title", "Choose files to send", "--multiple"]
    filePickerProcess.running = true
  }

  function sendSelectedFiles() {
    chooseFiles(selectedDevice())
  }

  function commitManualAddress() {
    if (!manualAddressValid) {
      manualAddressError = tailscaleMatches.length > 0
        ? "Choose a matching Tailscale machine below"
        : "No Tailscale machine matches this text; enter a literal IP address instead"
      return
    }
    useTailscaleAddress({ address: addressField.text })
  }

  function useTailscaleAddress(peer) {
    if (!peer || !peer.address) return
    if (connection.addCustomAddress(peer.address)) {
      addressField.text = ""
      keyCatcher.forceActiveFocus()
    }
  }

  function pairingRequestText(device) {
    var service = notificationService
    var model = service ? service.popupModel : null
    if (model) {
      for (var i = 0; i < model.count; i++) {
        var row = model.get(i)
        var app = String((row && row.app) || "").toLowerCase()
        var body = String((row && row.body) || "")
        if (app.indexOf("kde connect") !== -1 && body.toLowerCase().indexOf("pairing request from " + device.name.toLowerCase()) !== -1)
          return body.replace(/\s*\n\s*/g, " · ")
      }
    }
    return "Incoming pairing request · compare the verification key on both devices"
  }

  function openSettings() {
    if (!connection.kdeAppInstalled) return
    close()
    Quickshell.execDetached(["kdeconnect-app", "--replace"])
  }

  function openTailscale() {
    close()
    Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.tailscale", "open"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      connection.refreshAll()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onSelectedIndexChanged: scrollSelectedDeviceIntoView()

  ConnectionService {
    id: connection
    active: root.opened
  }

  Connections {
    target: connection
    function onConnectedDevicesChanged() { root.clampSelection() }
  }

  Process {
    id: filePickerProcess
    running: false
    command: []
    stdout: StdioCollector { id: filePickerStdout; waitForEnd: true; onStreamFinished: root._filePickerOutput = text }
    stderr: StdioCollector { id: filePickerStderr; waitForEnd: true; onStreamFinished: root._filePickerError = text }
    onExited: function(exitCode) {
      var deviceId = root.pendingFileDeviceId
      var deviceName = root.pendingFileDeviceName
      var output = String(filePickerStdout.text || root._filePickerOutput || "")
      var error = String(filePickerStderr.text || root._filePickerError || "")
      root.pendingFileDeviceId = ""
      root.pendingFileDeviceName = ""
      if (exitCode === 0) {
        var paths = output.split(/\r?\n/).filter(function(path) { return path !== "" })
        if (paths.length > 0) connection.shareFiles(deviceId, deviceName, paths)
        else connection.showMessage("The file chooser returned no files", "error", true)
      } else if (exitCode !== 1) {
        connection.showMessage(connection.elideError(error, "Could not open the file chooser"), "error", true)
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { connection.refreshAll(); return "ok" }
    function discover(): string { connection.startDiscovery(""); return "ok" }
    function status(): string {
      if (!connection.kdeInstalled) return "KDE Connect not installed"
      if (!connection.kdeReady) return "KDE Connect daemon unavailable"
      return root.deviceCount + " connected"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.connected
    useActiveColor: false
    tooltipText: !connection.environmentChecked
      ? "KDE Connect — checking environment"
      : !connection.kdeInstalled
        ? "KDE Connect — not installed"
        : !connection.kdeReady
          ? "KDE Connect — daemon unavailable"
          : root.connected
            ? "KDE Connect — " + root.deviceCount + " connected"
            : "KDE Connect — no connected devices"
    iconComponent: Component {
      Item {
        OmaKDEConnectIcon {
          anchors.centerIn: parent
          width: Style.bar.iconCanvas
          height: width
          color: root.connected ? root.barForeground : root.dimmedForeground
          badgeColor: root.urgent
          connected: root.connected
          deviceCount: root.deviceCount
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && connection.kdeReady) connection.startDiscovery("")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: addressField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.sendSelectedClipboard()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "c" || text === "C") root.sendSelectedClipboard()
        else if (text === "f" || text === "F") root.sendSelectedFiles()
        else if (text === "r" || text === "R" || text === "d" || text === "D") connection.startDiscovery("")
        else if (text === "a" || text === "A") addressField.forceActiveFocus()
        else if ((text === "p" || text === "P") && connection.discoveredDevices.length > 0) {
          var device = connection.discoveredDevices[0]
          if (device.pairRequestedByPeer) connection.acceptPairing(device)
          else connection.pairDevice(device)
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        property real wheelTargetY: contentY
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        maximumFlickVelocity: 5000
        flickDeceleration: 1300
        interactive: contentHeight > height
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

        NumberAnimation {
          id: wheelScrollAnimation
          target: panelFlick
          property: "contentY"
          duration: 240
          easing.type: Easing.OutCubic
        }

        WheelHandler {
          target: null
          orientation: Qt.Vertical
          acceptedButtons: Qt.NoButton
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          blocking: true
          onWheel: function(event) {
            if (!panelFlick.interactive) return
            var pixelScroll = event.pixelDelta.y !== 0
            var delta = pixelScroll ? event.pixelDelta.y : event.angleDelta.y * 0.75
            if (delta === 0) return
            var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
            var base = wheelScrollAnimation.running ? panelFlick.wheelTargetY : panelFlick.contentY
            panelFlick.wheelTargetY = Math.max(0, Math.min(maxY, base - delta))
            wheelScrollAnimation.stop()
            wheelScrollAnimation.from = panelFlick.contentY
            wheelScrollAnimation.to = panelFlick.wheelTargetY
            wheelScrollAnimation.duration = pixelScroll ? 90 : 240
            wheelScrollAnimation.start()
          }
        }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(10)

            OmaKDEConnectIcon {
              width: Style.space(36)
              height: width
              anchors.verticalCenter: parent.verticalCenter
              color: root.foreground
              badgeColor: root.urgent
              connected: root.connected
              deviceCount: root.deviceCount
            }

            Column {
              width: Math.max(0, parent.width - Style.space(36) - headerActions.width - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "KDE Connect"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                text: !connection.environmentChecked
                  ? "Checking environment…"
                  : !connection.kdeInstalled
                    ? "KDE Connect is not installed"
                    : !connection.kdeReady
                      ? "KDE Connect daemon unavailable"
                      : root.connected
                        ? root.deviceCount + (root.deviceCount === 1 ? " device connected" : " devices connected")
                        : "Ready to discover devices"
                color: root.connected ? root.foreground : root.dimmedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                iconText: "󰑐"
                iconSpinning: connection.refreshing
                tooltipText: "Refresh environment and devices"
                foreground: root.foreground
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: connection.refreshAll()
              }

              Button {
                iconText: "󰒓"
                tooltipText: connection.kdeAppInstalled ? "Open KDE Connect settings" : "kdeconnect-app is not installed"
                foreground: root.foreground
                enabled: connection.kdeAppInstalled
                opacity: enabled ? 1.0 : 0.4
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.openSettings()
              }
            }
          }

          BorderSurface {
            width: parent.width
            height: environmentContent.implicitHeight + Style.space(14)
            color: Style.normalFillFor(root.foreground)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: environmentContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: "KDE Connect  " + (!connection.environmentChecked ? "Checking…" : connection.kdeInstalled ? (connection.kdeReady ? "Ready" : "Daemon unavailable") : "Not installed")
                color: connection.kdeReady ? root.foreground : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                width: parent.width
                text: "Tailscale  " + (!connection.environmentChecked ? "Checking…" : connection.tailscaleStatus)
                color: connection.tailscaleRunning ? root.foreground : root.dimmedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: "LAN IP  " + (!connection.environmentChecked ? "Checking…" : connection.localLanAddress || "Unavailable")
                color: connection.localLanAddress ? root.foreground : root.dimmedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: "Tailscale IP  " + (!connection.environmentChecked ? "Checking…" : connection.localTailscaleAddress || "Not connected")
                color: connection.localTailscaleAddress ? root.foreground : root.dimmedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          BorderSurface {
            visible: connection.actionMessage !== ""
            width: parent.width
            height: statusText.implicitHeight + Style.space(14)
            color: connection.actionLevel === "error"
              ? Style.normalFillFor(root.urgent)
              : Style.normalFillFor(root.foreground)
            borderSpec: Border.controlSpec("normal", connection.actionLevel === "error" ? root.urgent : root.foreground, Color.accent)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              text: connection.actionMessage
              color: connection.actionLevel === "error" ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelSectionHeader {
            visible: root.connected
            text: "CONNECTED DEVICES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            id: connectedDeviceColumn
            visible: root.connected
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: connection.connectedDevices

              DeviceActionRow {
                required property int index
                required property var modelData
                title: modelData.name
                subtitle: "Connected · pairing remembered"
                selected: root.selectedIndex === index
                iconText: "󰌹"
                foreground: root.foreground
                primaryText: "Clipboard"
                primaryIcon: "󰅇"
                primaryTooltip: "Send current clipboard"
                primaryEnabled: !connection.actionBusy
                secondaryText: "Files"
                secondaryIcon: "󰈔"
                secondaryTooltip: "Choose files to send"
                secondaryEnabled: !connection.actionBusy
                onRowHovered: root.selectedIndex = index
                onPrimaryClicked: connection.sendClipboard(modelData)
                onSecondaryClicked: root.chooseFiles(modelData)
              }
            }
          }

          PanelSectionHeader {
            text: "DISCOVERY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Button {
            width: parent.width
            text: "Discover on local network"
            iconText: "󰑐"
            tooltipText: "Ask KDE Connect to refresh local and saved-address discovery"
            foreground: root.foreground
            enabled: connection.kdeReady && !connection.refreshing
            opacity: enabled ? 1.0 : 0.45
            iconSpinning: connection.watchingAddress === "" && connection.refreshing
            onClicked: connection.startDiscovery("")
          }

          Rectangle {
            id: addressCard
            width: parent.width
            height: addressColumn.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)
            border.color: root.manualAddressError === ""
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              : root.urgent

            Column {
              id: addressColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Enter the other device's LAN, VPN, or Tailscale IP. KDE Connect saves it and searches it again after restart."
                color: root.dimmedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: addressField
                  width: parent.width - addAddressButton.width - parent.spacing
                  placeholderText: "IP address or Tailscale machine name"
                  foreground: root.foreground
                  enabled: connection.kdeReady && !connection.actionBusy
                  onTextChanged: root.manualAddressError = ""
                  onAccepted: root.commitManualAddress()
                  Keys.onEscapePressed: {
                    root.manualAddressError = ""
                    keyCatcher.forceActiveFocus()
                  }
                }

                Button {
                  id: addAddressButton
                  text: root.manualAddressValid ? (connection.isAddressSaved(addressField.text) ? "Discover" : "Add") : "Filter"
                  iconText: root.manualAddressValid ? "󰐕" : "󰍉"
                  foreground: root.foreground
                  enabled: connection.kdeReady && !connection.actionBusy && root.manualAddressValid
                  opacity: enabled ? 1.0 : 0.45
                  onClicked: root.commitManualAddress()
                }
              }

              Column {
                visible: addressField.text.trim() !== "" && connection.tailscaleRunning
                width: parent.width
                spacing: Style.space(6)

                Text {
                  visible: root.tailscaleMatches.length > 0
                  width: parent.width
                  text: "MATCHING TAILSCALE MACHINES"
                  color: root.dimmedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Repeater {
                  model: root.tailscaleMatches

                  Button {
                    required property var modelData
                    width: parent.width
                    text: modelData.machineName + "  ·  " + modelData.address
                    iconText: modelData.online ? "󰌹" : "󰌺"
                    tooltipText: modelData.hostName && modelData.hostName !== modelData.machineName ? "Host: " + modelData.hostName : modelData.dnsName
                    foreground: root.foreground
                    enabled: connection.kdeReady && !connection.actionBusy
                    opacity: modelData.online ? 1.0 : 0.65
                    onClicked: root.useTailscaleAddress(modelData)
                  }
                }

                Text {
                  visible: root.tailscaleMatches.length === 0
                  width: parent.width
                  text: "No matching Tailscale machine"
                  color: root.dimmedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: root.manualAddressError !== ""
                width: parent.width
                text: root.manualAddressError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSectionHeader {
            visible: connection.discoveredDevices.length > 0
            text: "READY TO PAIR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: connection.discoveredDevices.length > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: connection.discoveredDevices

              DeviceActionRow {
                required property var modelData
                title: modelData.name
                readonly property bool incomingRequest: modelData.pairRequestedByPeer === true
                subtitle: incomingRequest
                  ? root.pairingRequestText(modelData)
                  : connection.waitingPairId === modelData.id ? "Waiting for confirmation on the other device…" : "Reachable · not paired"
                iconText: "󰐕"
                foreground: root.foreground
                primaryText: incomingRequest ? "Accept" : connection.waitingPairId === modelData.id ? "Waiting" : "Pair"
                primaryIcon: "󰘅"
                primaryEnabled: !connection.actionBusy && connection.waitingPairId === ""
                primaryBusy: connection.pairingDeviceId === modelData.id || connection.waitingPairId === modelData.id
                secondaryText: incomingRequest ? "Reject" : ""
                secondaryIcon: incomingRequest ? "󰅖" : ""
                secondaryTooltip: "Reject this pairing request"
                secondaryEnabled: !connection.actionBusy
                onPrimaryClicked: {
                  if (incomingRequest) connection.acceptPairing(modelData)
                  else connection.pairDevice(modelData)
                }
                onSecondaryClicked: connection.rejectPairing(modelData)
              }
            }
          }

          PanelSectionHeader {
            visible: connection.tailscaleRunning && connection.tailscalePeers.length > 0 && addressField.text.trim() === ""
            text: "TAILSCALE PEERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: connection.tailscaleRunning && connection.tailscalePeers.length > 0 && addressField.text.trim() === ""
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: connection.tailscalePeers

              DeviceActionRow {
                required property var modelData
                title: modelData.name
                subtitle: modelData.address + (modelData.os ? " · " + modelData.os : "") + (modelData.online ? " · online" : " · offline")
                iconText: modelData.online ? "󰌹" : "󰌺"
                foreground: root.foreground
                opacity: modelData.online ? 1.0 : 0.62
                primaryText: connection.isAddressSaved(modelData.address) ? "Discover" : "Use address"
                primaryIcon: connection.isAddressSaved(modelData.address) ? "󰑐" : "󰐕"
                primaryTooltip: "Save this IP in KDE Connect and start discovery"
                primaryEnabled: connection.kdeReady && !connection.actionBusy
                secondaryIcon: connection.isAddressSaved(modelData.address) ? "󰆴" : ""
                secondaryTooltip: "Forget this address"
                secondaryEnabled: !connection.actionBusy
                onPrimaryClicked: connection.addCustomAddress(modelData.address)
                onSecondaryClicked: connection.removeCustomAddress(modelData.address)
              }
            }
          }

          PanelSectionHeader {
            visible: connection.customAddresses.length > 0
            text: "SAVED ADDRESSES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: connection.customAddresses.length > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: connection.customAddresses

              DeviceActionRow {
                required property string modelData
                title: modelData
                subtitle: "Remembered by KDE Connect"
                iconText: "󰩟"
                foreground: root.foreground
                primaryText: "Discover"
                primaryIcon: "󰑐"
                primaryEnabled: connection.kdeReady && !connection.actionBusy
                secondaryIcon: "󰆴"
                secondaryTooltip: "Forget this address"
                secondaryEnabled: !connection.actionBusy
                onPrimaryClicked: connection.startDiscovery(modelData)
                onSecondaryClicked: connection.removeCustomAddress(modelData)
              }
            }
          }

          PanelSectionHeader {
            visible: connection.rememberedDevices.length > 0
            text: "PAIRED BUT OFFLINE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: connection.rememberedDevices.length > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: connection.rememberedDevices

              DeviceActionRow {
                required property var modelData
                title: modelData.name
                subtitle: "Pairing remembered · currently unreachable"
                iconText: "󰌹"
                foreground: root.foreground
                opacity: 0.65
              }
            }
          }

          Text {
            width: parent.width
            text: "j/k: select connected device  ·  c: clipboard  ·  f: files  ·  d: discover  ·  a: add address  ·  p: pair first device"
            color: root.dimmedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
