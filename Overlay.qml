import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Fullscreen click-through overlay for one monitor. The BarWidget host owns
// all state (cursor pos, settings, click pulse); this surface only paints.
PanelWindow {
  id: root

  required property var host

  screen: {
    var target = host ? String(host.screenName || "") : "";
    var list = Quickshell.screens || [];
    for (var i = 0; i < list.length; i++) {
      if (target !== "" && list[i] && String(list[i].name) === target) return list[i];
    }
    return null;
  }

  // NOTE: visible must never read this overlay's own `screen` property the
  // way the first version did (`screen.name`): mapping/unmapping the window
  // changes its effective screen, which re-triggers the binding — a loop
  // that QML breaks by pinning visible to false. Like the timer's Floating
  // window, visibility is derived from host state only.
  readonly property string targetName: host ? String(host.screenName || "") : ""
  visible: host ? host.haloVisibleOn(root.targetName) : false
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "nickmdrummer-cursor-halo"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors { top: true; bottom: true; left: true; right: true }
  // Empty input region: every click passes through to the app below.
  mask: Region { x: -1; y: -1; width: 0; height: 0 }

  readonly property real localX: host ? host.localX : -10000
  readonly property real localY: host ? host.localY : -10000
  readonly property int diameter: host ? host.diameter : 176
  readonly property color haloColor: host ? host.currentColor : "#00FFC8"
  // Frozen click color for the ripple, so it does not shift to the base color
  // when the 200ms flash ends mid-animation.
  readonly property color rippleColor: host ? host.rippleColor : "#00FFC8"
  readonly property bool showSpotlight: host ? host.spotlightOn : false

  // Spotlight: dim everything except a hole shaped exactly like the halo.
  // A fullscreen rectangle with an enormous border paints the dim; the
  // transparent center is the hole. Inner edge = outer radius minus border,
  // so the hole matches the halo shape with zero repaint cost (it only moves).
  Rectangle {
    id: spotDim
    visible: root.showSpotlight && root.localX > -5000
    x: root.localX - width / 2
    y: root.localY - height / 2
    width: root.diameter + 2 * spotDim.cover
    height: width
    color: "transparent"
    border.color: Qt.rgba(0, 0, 0, 0.45)
    border.width: spotDim.cover
    // Match HaloShape's radii: Circle 1/2, Rounded 0.28, Rhombus 0.22 + 45deg.
    radius: (host && host.shapeName === "Circle") ? width / 2
      : (host && host.shapeName === "Rounded" ? root.diameter * 0.28 + spotDim.cover
        : root.diameter * 0.22 + spotDim.cover)
    rotation: host && host.shapeName === "Rhombus" ? 45 : 0

    // Covers any real monitor (16kpx item, still vector-cheap).
    readonly property int cover: 8000
  }

  // Expanding ripple on click.
  Rectangle {
    id: ripple
    visible: host && host.rippleOn && host.rippleActive
    width: root.diameter * rippleScale
    height: width
    radius: host && host.shapeName === "Circle" ? width / 2 : width * 0.28
    rotation: host && host.shapeName === "Rhombus" ? 45 : 0
    x: root.localX - width / 2
    y: root.localY - height / 2
    color: "transparent"
    border.color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, rippleOpacity)
    border.width: Math.max(2, (host ? host.borderPx : 8) / 2)

    property real rippleScale: 1.0
    property real rippleOpacity: 0.8
  }

  HaloShape {
    id: halo
    shape: host ? host.shapeName : "Circle"
    glowColor: root.haloColor
    diameter: root.diameter
    borderWidth: host ? host.borderPx : 13
    pulse: host ? host.pulse : 0
    x: root.localX - width / 2
    y: root.localY - height / 2
  }

  // Ripple + pulse drivers: retrigger whenever the host's click sequence ticks.
  Connections {
    target: host
    function onClickSeqChanged() {
      if (!host || !host.rippleOn) return;
      rippleAnim.restart();
    }
  }

  SequentialAnimation {
    id: rippleAnim
    PropertyAction { target: ripple; property: "rippleScale"; value: 1.0 }
    PropertyAction { target: ripple; property: "rippleOpacity"; value: 0.8 }
    ParallelAnimation {
      NumberAnimation { target: ripple; property: "rippleScale"; to: 1.9; duration: Style.duration(420); easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "rippleOpacity"; to: 0.0; duration: Style.duration(420); easing.type: Easing.OutCubic }
    }
  }
}
