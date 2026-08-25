import QtQuick
import qs.Commons

Item {
  id: root

  property color color: Color.foreground
  property color badgeColor: Color.accent
  property bool connected: false
  property int deviceCount: 0

  implicitWidth: Style.bar.iconCanvas
  implicitHeight: Style.bar.iconCanvas

  readonly property real stroke: Math.max(1, Math.round(width * 0.09))

  Rectangle {
    id: phone
    width: Math.round(parent.width * 0.52)
    height: Math.round(parent.height * 0.82)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    radius: Math.max(1, root.stroke * 1.4)
    color: "transparent"
    border.width: root.stroke
    border.color: root.color

    Rectangle {
      width: Math.max(2, parent.width * 0.26)
      height: root.stroke
      radius: height / 2
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.stroke * 1.2
      color: root.color
    }
  }

  Rectangle {
    id: linkTop
    width: Math.round(parent.width * 0.46)
    height: Math.round(parent.height * 0.24)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -height * 0.45
    radius: height / 2
    color: "transparent"
    border.width: root.stroke
    border.color: root.color
    rotation: -24
  }

  Rectangle {
    width: linkTop.width
    height: linkTop.height
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: linkTop.height * 0.55
    radius: height / 2
    color: "transparent"
    border.width: root.stroke
    border.color: root.color
    rotation: -24
  }

  Rectangle {
    visible: root.connected
    width: Math.max(5, parent.width * 0.30)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    color: root.badgeColor
    border.width: Math.max(1, root.stroke * 0.75)
    border.color: Color.background

    Text {
      anchors.centerIn: parent
      visible: root.deviceCount > 1
      text: root.deviceCount > 9 ? "9+" : String(root.deviceCount)
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.62)
      font.bold: true
    }
  }
}
