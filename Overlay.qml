import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "HaloModel.js" as Halo

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
  visible: host ? (host.haloVisibleOn(root.targetName) || host.trailsVisibleOn(root.targetName)) : false
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "nickmdrummer-comet-cursor"
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
  readonly property color trailColor: host ? host.trailColorValue : "#00FFC8"
  readonly property bool trailsShown: host ? host.trailsOn : false
  readonly property string trailStyleName: host ? host.trailStyle : "Off"
  readonly property bool strokeShown: root.trailsShown && (root.trailStyleName === "Feather" || root.trailStyleName === "Ribbon")
  readonly property bool pixelsShown: root.trailsShown && root.trailStyleName === "Pixels"

  // One filled polygon for the whole stroke: continuous at any pointer speed,
  // unlike a chain of circles that came apart when the mouse accelerated.
  readonly property var strokePoints: {
    var tick = host ? host.trailTick : 0;
    if (!host || !root.strokeShown) return [];
    var raw = Halo.strokeOutline(host.trailPoints, Date.now(), host.trailLength,
      host.trailWidth, host.trailStyle, host.originX, host.originY);
    var pts = [];
    for (var i = 0; i < raw.length; i++) pts.push(Qt.point(raw[i][0], raw[i][1]));
    return pts;
  }

  // Trails: strokes for Feather/Ribbon, discrete dots for Pixels. A window is
  // not an Item, so the Repeater gets an explicit Item parent for its
  // delegates.
  Item {
    id: trailLayer
    anchors.fill: parent
    z: 0

    Shape {
      id: strokeShape
      anchors.fill: parent
      visible: root.strokeShown
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeWidth: 0
        fillColor: Qt.rgba(root.trailColor.r, root.trailColor.g, root.trailColor.b,
          host ? host.trailAlpha : 0.8)
        PathPolyline { path: root.strokePoints }
      }
    }

    // Round the leading edge so a brush stroke does not start with a flat cut.
    Rectangle {
      id: strokeTip
      visible: root.strokeShown
      readonly property var head: (host && host.trailPoints.length > 0)
        ? host.trailPoints[host.trailPoints.length - 1] : null
      width: host ? host.trailWidth : 6
      height: width
      radius: width / 2
      z: 1
      x: strokeTip.head ? strokeTip.head.gx - host.originX - width / 2 : -1000
      y: strokeTip.head ? strokeTip.head.gy - host.originY - height / 2 : -1000
      color: Qt.rgba(root.trailColor.r, root.trailColor.g, root.trailColor.b,
        host ? host.trailAlpha : 0.8)
    }

    // Fixed delegate count: the model is a constant, so samples update in
    // place instead of destroying and rebuilding every dot on each tick
    // (that churn was the stutter).
    Repeater {
      model: 70
      delegate: Rectangle {
        id: pixel
        required property int index

        readonly property var pt: (host && pixel.index < host.trailPoints.length)
          ? host.trailPoints[pixel.index] : null
        readonly property real age: {
          var tick = host ? host.trailTick : 0;
          return pixel.pt ? Halo.trailAge(pixel.pt, Date.now(), host.trailLength) : 1;
        }
        // Tiny deterministic scatter so pixels read as dust, not a line.
        readonly property real jitterX: ((pixel.index * 37) % 11 - 5) * 0.7
        readonly property real jitterY: ((pixel.index * 53) % 13 - 6) * 0.7

        visible: root.pixelsShown && pixel.pt !== null
        width: Math.max(2, host ? host.trailWidth * 0.75 : 4)
        height: width
        radius: 0
        x: pixel.pt ? pixel.pt.gx - host.originX - width / 2 + pixel.jitterX : -1000
        y: pixel.pt ? pixel.pt.gy - host.originY - height / 2 + pixel.jitterY : -1000
        color: Qt.rgba(root.trailColor.r, root.trailColor.g, root.trailColor.b,
          0.9 * (1 - pixel.age) * (host ? host.trailAlpha : 0.8))
      }
    }
  }
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
