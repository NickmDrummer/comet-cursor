import QtQuick
import qs.Commons

// One glowing halo shape, centered in its parent.
// size: outer diameter in px. shape: Circle | Rhombus | Rounded.
Item {
  id: root

  property string shape: "Circle"
  property color glowColor: "#00FFC8"
  property int diameter: 176
  property int borderWidth: 13
  // 0..1 pulse progress for the click flash (driven by the Overlay).
  property real pulse: 0

  readonly property color pulseColor: root.glowColor
  // Outer soft glow + crisp inner ring, like Cursor Pro.
  readonly property real pulseScale: 1 + 0.12 * root.pulse

  width: root.diameter
  height: root.diameter

  // Soft outer glow.
  Rectangle {
    id: glow
    anchors.centerIn: parent
    width: parent.width
    height: parent.height
    radius: root.shape === "Circle" ? width / 2 : (root.shape === "Rounded" ? width * 0.28 : width * 0.22)
    rotation: root.shape === "Rhombus" ? 45 : 0
    color: "transparent"
    border.color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.28 + 0.5 * root.pulse)
    border.width: root.borderWidth + 6
    scale: root.pulseScale
    opacity: 0.55 + 0.45 * root.pulse

    Behavior on scale {
      NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    Behavior on opacity {
      NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
    }
  }

  // Crisp main ring.
  Rectangle {
    id: ring
    anchors.centerIn: parent
    width: parent.width - 8
    height: parent.height - 8
    radius: root.shape === "Circle" ? width / 2 : (root.shape === "Rounded" ? width * 0.28 : width * 0.22)
    rotation: root.shape === "Rhombus" ? 45 : 0
    color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.10 + 0.12 * root.pulse)
    border.color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.95)
    border.width: root.borderWidth
    scale: root.pulseScale

    Behavior on scale {
      NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
  }
}
