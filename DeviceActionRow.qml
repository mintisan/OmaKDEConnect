import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string iconText: "󰌢"
  property bool selected: false

  property string primaryText: ""
  property string primaryIcon: ""
  property string primaryTooltip: ""
  property bool primaryEnabled: true
  property bool primaryBusy: false

  property string secondaryText: ""
  property string secondaryIcon: ""
  property string secondaryTooltip: ""
  property bool secondaryEnabled: true

  signal primaryClicked()
  signal secondaryClicked()
  signal rowClicked()

  width: parent ? parent.width : implicitWidth
  height: rowContent.implicitHeight + Style.space(14)
  hasCursor: rowHover.hovered
  current: selected
  foreground: Color.foreground

  HoverHandler {
    id: rowHover
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
      width: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      width: Math.max(0, parent.width - Style.space(34) - actions.width - parent.spacing * 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      TapHandler {
        onTapped: root.rowClicked()
      }

      Text {
        width: parent.width
        text: (root.selected ? "󰄬  " : "") + root.title
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        visible: root.subtitle !== ""
        width: parent.width
        text: root.subtitle
        color: Qt.darker(root.foreground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: actions
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        visible: root.primaryText !== "" || root.primaryIcon !== ""
        text: root.primaryText
        iconText: root.primaryIcon
        tooltipText: root.primaryTooltip
        foreground: root.foreground
        enabled: root.primaryEnabled && !root.primaryBusy
        opacity: enabled ? 1.0 : 0.45
        iconSpinning: root.primaryBusy
        onClicked: root.primaryClicked()
      }

      Button {
        visible: root.secondaryText !== "" || root.secondaryIcon !== ""
        text: root.secondaryText
        iconText: root.secondaryIcon
        tooltipText: root.secondaryTooltip
        foreground: root.foreground
        enabled: root.secondaryEnabled
        opacity: enabled ? 1.0 : 0.45
        onClicked: root.secondaryClicked()
      }
    }
  }
}
