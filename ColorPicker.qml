import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HaloModel.js" as Halo

// Inline HSV color picker: a saturation/value square, a hue strip and a hex
// field. It previews while dragging but only emits `committed` when the user
// lets go (or confirms the hex), so the config file is not rewritten on every
// pixel of a drag.
Item {
  id: root

  property color value: "#00FFC8"
  property color foreground: Commons.Color.popups.text
  property color accent: Commons.Color.accent

  property real hue: 0
  property real sat: 0
  property real val: 0
  // True while the pointer is down: the incoming `value` must not fight the
  // user's drag by snapping the internal HSV back.
  property bool dragging: false

  signal committed(string hex)

  implicitWidth: parent ? parent.width : 0
  implicitHeight: content.implicitHeight

  readonly property string hex: Halo.hsvToHex(root.hue, root.sat, root.val)

  function loadFromValue() {
    var hex = Halo.colorToHex(root.value);
    if (!hex) return;
    var c = Halo.parseHexColor(hex);
    if (!c) return;
    var hsv = Halo.rgbToHsv(c.r, c.g, c.b);
    root.hue = hsv.h;
    root.sat = hsv.s;
    root.val = hsv.v;
  }

  // Accepts whatever the user typed in the hex field; normalizes it, applies it
  // and persists. Invalid input snaps the field back to the current color.
  function applyHex(raw) {
    var hex = Halo.normalizeHex(raw);
    if (!hex) {
      hexField.text = root.hex;
      return;
    }
    root.dragging = false;
    root.value = hex;
    root.loadFromValue();
    root.committed(hex);
  }

  function commit() {
    root.committed(root.hex);
  }

  // Keep the field in sync with the square/strip without fighting typing: the
  // handler is skipped while the field has focus.
  onHexChanged: if (!hexField.activeFocus && hexField.text !== root.hex) hexField.text = root.hex

  Component.onCompleted: root.loadFromValue()
  onValueChanged: if (!root.dragging) root.loadFromValue()

  // Put the caret in the hex field as soon as the picker appears, so a custom
  // color can be typed without an extra click (the panel is the one that owns
  // keyboard focus, the field only has to hold it).
  onVisibleChanged: if (visible) Qt.callLater(function() { hexField.forceActiveFocus() })

  Column {
    id: content
    width: parent.width
    spacing: Style.space(8)

    // ---- saturation / value square -------------------------------------
    Rectangle {
      id: plane
      width: parent.width
      height: Style.space(104)
      radius: Style.cornerRadius
      clip: true
      border.width: Style.normalBorderWidth
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      // Base: the pure hue.
      color: Halo.hsvToHex(root.hue, 1, 1)

      // White on the left (saturation 0) ...
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#FFFFFFFF" }
          GradientStop { position: 1.0; color: "#00FFFFFF" }
        }
      }

      // ... black at the bottom (value 0).
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "#00000000" }
          GradientStop { position: 1.0; color: "#FF000000" }
        }
      }

      // Marker on the current color.
      Rectangle {
        width: Style.space(12)
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(parent.width - width, root.sat * parent.width - width / 2))
        y: Math.max(0, Math.min(parent.height - height, (1 - root.val) * parent.height - height / 2))
        color: "transparent"
        border.width: 2
        border.color: root.val > 0.55 ? "#CC000000" : "#FFFFFFFF"
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        function apply(mouse) {
          root.sat = Math.max(0, Math.min(1, mouse.x / Math.max(1, plane.width)));
          root.val = 1 - Math.max(0, Math.min(1, mouse.y / Math.max(1, plane.height)));
        }
        onPressed: function(mouse) { root.dragging = true; apply(mouse); }
        onPositionChanged: function(mouse) { if (pressed) apply(mouse); }
        onReleased: function(mouse) { apply(mouse); root.dragging = false; root.commit(); }
      }
    }

    // ---- hue strip ------------------------------------------------------
    Rectangle {
      id: hueBar
      width: parent.width
      height: Style.space(14)
      radius: height / 2
      clip: true
      border.width: Style.normalBorderWidth
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.000; color: "#FF0000" }
        GradientStop { position: 0.167; color: "#FFFF00" }
        GradientStop { position: 0.333; color: "#00FF00" }
        GradientStop { position: 0.500; color: "#00FFFF" }
        GradientStop { position: 0.667; color: "#0000FF" }
        GradientStop { position: 0.833; color: "#FF00FF" }
        GradientStop { position: 1.000; color: "#FF0000" }
      }

      Rectangle {
        width: Style.space(6)
        height: parent.height
        radius: width / 2
        x: Math.max(0, Math.min(parent.width - width, (root.hue / 360) * parent.width - width / 2))
        color: "transparent"
        border.width: 2
        border.color: "#FFFFFFFF"
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        function apply(mouse) {
          root.hue = Math.max(0, Math.min(359.9, (mouse.x / Math.max(1, hueBar.width)) * 360));
        }
        onPressed: function(mouse) { root.dragging = true; apply(mouse); }
        onPositionChanged: function(mouse) { if (pressed) apply(mouse); }
        onReleased: function(mouse) { apply(mouse); root.dragging = false; root.commit(); }
      }
    }

    // ---- hex field ------------------------------------------------------
    Row {
      width: parent.width
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(26)
        height: Style.space(26)
        radius: Style.cornerRadius
        color: root.hex
        border.width: Style.normalBorderWidth
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
        anchors.verticalCenter: parent.verticalCenter
      }

      TextField {
        id: hexField
        width: parent.width - Style.space(26) - parent.spacing
        height: Style.space(26)
        verticalPadding: Style.space(3)
        foreground: root.foreground
        accent: root.accent
        placeholderText: "#RRGGBB"
        text: root.hex
        // No `Binding on text` here: it fights the user's keystrokes. The
        // picker syncs the field through onHexChanged instead, and only while
        // the field is not being edited.
        onAccepted: root.applyHex(text)
        onEditingFinished: root.applyHex(text)
        onActiveFocusChanged: if (!activeFocus) root.applyHex(text)
      }
    }
  }
}
