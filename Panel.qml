pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import Quickshell
import Quickshell.Io
import org.kde.kdeconnect as KDEConnect
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "omakdeconnect"
  ipcTarget: "omakdeconnect"
  manageIpc: false

  property int selectedIndex: 0
  property var pendingSharePlugin: null

  readonly property int deviceCount: connectedDevices.count
  readonly property bool connected: deviceCount > 0
  readonly property color dimmedForeground: Qt.darker(barForeground, 1.55)

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
    devicesView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectedRow() {
    if (deviceCount <= 0) return null
    return devicesView.itemAtIndex(selectedIndex)
  }

  function sendSelectedClipboard() {
    var row = selectedRow()
    if (row) row.sendClipboard()
  }

  function sendSelectedFiles() {
    var row = selectedRow()
    if (row) row.chooseFiles()
  }

  function chooseFiles(sharePlugin) {
    if (!sharePlugin) return
    pendingSharePlugin = sharePlugin
    close()
    Qt.callLater(function() { fileDialog.open() })
  }

  function openSettings() {
    close()
    Quickshell.execDetached(["kdeconnect-app"])
  }

  function refreshDevices() {
    Quickshell.execDetached(["kdeconnect-cli", "--refresh"])
  }

  KDEConnect.DevicesModel {
    id: connectedDevices
    displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable
    onCountChanged: root.clampSelection()
  }

  Dialogs.FileDialog {
    id: fileDialog
    title: "Choose files to send"
    currentFolder: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    modality: Qt.NonModal
    fileMode: Dialogs.FileDialog.OpenFiles

    onAccepted: {
      if (root.pendingSharePlugin) root.pendingSharePlugin.shareUrls(selectedFiles)
      root.pendingSharePlugin = null
    }
    onRejected: root.pendingSharePlugin = null
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshDevices(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.connected
    useActiveColor: false
    tooltipText: root.connected
      ? "KDE Connect — " + root.deviceCount + " connected"
      : "KDE Connect — no connected devices"
    iconComponent: Component {
      Item {
        OmaKDEConnectIcon {
          anchors.centerIn: parent
          width: Style.bar.iconCanvas
          height: width
          color: root.connected ? root.barForeground : root.dimmedForeground
          badgeColor: root.bar ? root.bar.urgent : Color.accent
          connected: root.connected
          deviceCount: root.deviceCount
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshDevices()
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
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.sendSelectedClipboard()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "c" || text === "C") root.sendSelectedClipboard()
        else if (text === "f" || text === "F") root.sendSelectedFiles()
        else if (text === "r" || text === "R") root.refreshDevices()
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(10)

          OmaKDEConnectIcon {
            width: Style.space(36)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            color: root.bar.foreground
            badgeColor: root.bar.urgent
            connected: root.connected
            deviceCount: root.deviceCount
          }

          Column {
            width: parent.width - Style.space(36) - headerActions.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "KDE Connect"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              text: root.connected
                ? root.deviceCount + (root.deviceCount === 1 ? " device connected" : " devices connected")
                : "No connected devices"
              color: root.connected ? root.bar.foreground : root.dimmedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            id: headerActions
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              iconText: "󰑐"
              tooltipText: "Refresh devices"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.refreshDevices()
            }

            Button {
              iconText: "󰒓"
              tooltipText: "Open KDE Connect settings"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openSettings()
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: root.connected
          text: "CONNECTED DEVICES"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        ListView {
          id: devicesView
          visible: root.connected
          width: parent.width
          height: Math.min(contentHeight, Style.space(380))
          clip: true
          spacing: Style.space(8)
          boundsBehavior: Flickable.StopAtBounds
          model: connectedDevices
          currentIndex: root.selectedIndex

          QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            policy: QQC2.ScrollBar.AsNeeded
          }

          delegate: DeviceRow {
            required property var model
            required property int index
            width: ListView.view.width
            deviceModel: model
            rowIndex: index
          }
        }

        Column {
          visible: !root.connected
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Pair a device in KDE Connect, or add its VPN address manually. It will appear here when reachable."
            color: root.dimmedForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Open KDE Connect"
            iconText: "󰒓"
            foreground: root.bar.foreground
            onClicked: root.openSettings()
          }
        }

        Text {
          visible: root.connected
          width: parent.width
          text: "j/k or arrows: select  ·  c: clipboard  ·  f: files"
          color: root.dimmedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: row

    required property var deviceModel
    required property int rowIndex

    readonly property string deviceId: String(deviceModel.deviceId || "")
    readonly property var device: KDEConnect.DeviceDbusInterfaceFactory.create(deviceId)
    readonly property bool selected: root.selectedIndex === rowIndex
    readonly property string deviceName: String(deviceModel.name || "Device")
    readonly property bool reachable: device ? device.isReachable : true
    property string deviceType: "device"

    property var clipboardPlugin: clipboardChecker.available
      ? KDEConnect.ClipboardDbusInterfaceFactory.create(deviceId)
      : null
    property var sharePlugin: shareChecker.available
      ? KDEConnect.ShareDbusInterfaceFactory.create(deviceId)
      : null

    function sendClipboard() {
      if (clipboardPlugin) clipboardPlugin.sendClipboard()
    }

    function chooseFiles() {
      if (sharePlugin) root.chooseFiles(sharePlugin)
    }

    width: parent ? parent.width : implicitWidth
    height: rowContent.implicitHeight + Style.space(14)
    hasCursor: selected
    foreground: root.bar.foreground
    opacity: reachable ? 1.0 : 0.5

    Component.onCompleted: {
      if (device) deviceType = String(device.type || "device")
    }

    KDEConnect.PluginChecker {
      id: clipboardChecker
      pluginName: "clipboard"
      device: row.device
    }

    KDEConnect.PluginChecker {
      id: shareChecker
      pluginName: "share"
      device: row.device
    }

    HoverHandler {
      onHoveredChanged: if (hovered) root.selectedIndex = row.rowIndex
    }

    Row {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: row.deviceType === "phone" ? "󰏲"
          : row.deviceType === "tablet" ? "󰓶"
          : "󰌢"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.iconLarge
      }

      Column {
        width: parent.width - Style.space(34) - actionButtons.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: row.deviceName
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: row.reachable ? "Connected" : "Unavailable"
          color: row.reachable ? root.bar.foreground : root.dimmedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: actionButtons
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Button {
          text: "Clipboard"
          iconText: "󰅇"
          tooltipText: clipboardChecker.available ? "Send current clipboard" : "Clipboard plugin unavailable"
          foreground: root.bar.foreground
          enabled: row.reachable && clipboardChecker.available
          opacity: enabled ? 1.0 : 0.4
          onClicked: row.sendClipboard()
          onHovered: function(isHovered) { if (isHovered) root.selectedIndex = row.rowIndex }
        }

        Button {
          text: "Files"
          iconText: "󰈔"
          tooltipText: shareChecker.available ? "Choose files to send" : "Share plugin unavailable"
          foreground: root.bar.foreground
          enabled: row.reachable && shareChecker.available
          opacity: enabled ? 1.0 : 0.4
          onClicked: row.chooseFiles()
          onHovered: function(isHovered) { if (isHovered) root.selectedIndex = row.rowIndex }
        }
      }
    }
  }
}
