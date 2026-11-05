import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HaloModel.js" as Halo

// Comet Cursor — Cursor Pro style mouse highlighter.
//   left click  : toggle enabled
//   right click : appearance popup
// Each bar instance paints the halo only on its own monitor.
BarWidget {
  id: root
  moduleName: "nickmdrummer.comet-cursor"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---- settings (persisted to shell.json via updateEntryInline) -----------
  readonly property bool cfgEnabled: root.setting("enabled", false) === true
  readonly property string shapeName: Halo.cleanEnum(root.setting("shape", "Circle"), Halo.SHAPES, "Circle")
  readonly property color baseColor: Halo.cleanColor(root.setting("color", "#00FFC8"), "#00FFC8")
  readonly property string sizeName: Halo.cleanEnum(root.setting("size", "L"), Halo.SIZES, "L")
  readonly property string weightName: Halo.cleanEnum(root.setting("borderWeight", "Bold"), Halo.WEIGHTS, "Bold")
  readonly property color leftColor: Halo.cleanColor(root.setting("leftClickColor", "#FF2D55"), "#FF2D55")
  readonly property color rightColor: Halo.cleanColor(root.setting("rightClickColor", "#3B82F6"), "#3B82F6")
  readonly property string modeName: Halo.cleanEnum(root.setting("mode", "Always"), Halo.MODES, "Always")
  readonly property bool spotlightOn: root.setting("spotlight", false) === true
  readonly property bool rippleOn: root.setting("ripple", true) !== false

  // ---- trails ------------------------------------------------------------
  // Independent of the halo on purpose: a trail can be the only effect on
  // screen ("Off" style = disabled).
  readonly property string trailStyle: Halo.cleanEnum(root.setting("trailStyle", "Off"), Halo.TRAIL_STYLES, "Off")
  readonly property bool trailsOn: root.trailStyle !== "Off"
  readonly property int trailLength: Math.max(200, Math.min(2000, Math.round(Number(root.setting("trailLength", 600)) || 600)))
  readonly property int trailWidth: Math.max(2, Math.min(16, Math.round(Number(root.setting("trailWidth", 6)) || 6)))
  readonly property real trailAlpha: Math.max(0.1, Math.min(1, (Math.round(Number(root.setting("trailOpacity", 80)) || 80)) / 100))
  readonly property string trailColorMode: Halo.cleanEnum(root.setting("trailColorMode", "Halo"), ["Halo", "Custom"], "Halo")
  readonly property color trailColorValue: Halo.trailColorFor(root.trailColorMode, root.setting("trailColor", "#00FFC8"), root.currentColor)

  readonly property int diameter: Halo.diameterForSize(root.sizeName)
  readonly property int borderPx: Halo.borderForWeight(root.weightName)

  function save(patch) {
    var entry = { id: root.moduleName };
    for (var k in root.settings) {
      if (k !== "id") entry[k] = root.settings[k];
    }
    for (var key in patch) entry[key] = patch[key];
    root.settings = entry;
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry);
  }

  // ---- screen identity (which monitor this instance lives on) ------------
  property string screenName: ""
  function updateScreenName() {
    try {
      var w = button && button.QsWindow ? button.QsWindow.window : null;
      root.screenName = (w && w.screen && w.screen.name) ? String(w.screen.name) : "";
    } catch (e) { root.screenName = ""; }
  }
  Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.updateScreenName() }

  // ---- cursor + monitor polling ------------------------------------------
  property real cursorGX: -10000
  property real cursorGY: -10000
  property var monitors: []
  // Date.now() is ~1.8e12, far beyond a 32-bit int: this MUST be double or
  // the On-move comparison overflows and the halo never shows.
  property double lastMoveAt: 0

  // Recent cursor samples for the trail, oldest first: {gx, gy, t}.
  // Trail points live in global coordinates so one overlay per monitor can
  // map them with its own origin.
  property var trailPoints: []
  // Bumped on every sample so trail delegates re-evaluate their age: time
  // alone does not re-run a binding.
  property int trailTick: 0

  readonly property real localX: {
    for (var i = 0; i < root.monitors.length; i++) {
      var m = root.monitors[i];
      if (String(m.name) === root.screenName) return root.cursorGX - m.x;
    }
    return -10000;
  }
  readonly property real localY: {
    for (var j = 0; j < root.monitors.length; j++) {
      var n = root.monitors[j];
      if (String(n.name) === root.screenName) return root.cursorGY - n.y;
    }
    return -10000;
  }
  readonly property bool cursorOnScreen: root.localX > -5000 && root.screenName !== ""

  // Global origin of this instance's monitor, for mapping trail samples.
  readonly property real originX: {
    for (var i = 0; i < root.monitors.length; i++) {
      if (String(root.monitors[i].name) === root.screenName) return root.monitors[i].x;
    }
    return 0;
  }
  readonly property real originY: {
    for (var j = 0; j < root.monitors.length; j++) {
      if (String(root.monitors[j].name) === root.screenName) return root.monitors[j].y;
    }
    return 0;
  }

  function trailsVisibleOn(screen) {
    if (!root.trailsOn) return false;
    if (String(screen || "") !== root.screenName) return false;
    return root.cursorOnScreen && root.trailPoints.length > 0;
  }

  // Appends a sample, interpolating the gap left by a fast move so the
  // Ribbon reads as a continuous band instead of dotted steps.
  function sampleTrail(moved) {
    var now = Date.now();
    var pts = root.trailPoints;
    if (moved && root.trailsOn && root.cursorOnScreen) {
      var next = pts.slice();
      if (next.length > 0) {
        var last = next[next.length - 1];
        var dx = root.cursorGX - last.gx;
        var dy = root.cursorGY - last.gy;
        var dist = Math.sqrt(dx * dx + dy * dy);
        // Strokes are smoothed by the spline in HaloModel, so they must keep
        // the REAL samples as knots: pre-filling the gap with points on the
        // chord would flatten the curve back into facets. Pixels are discrete
        // by design and still benefit from a few filler points.
        var steps = root.trailStyle === "Pixels"
          ? Math.min(4, Math.floor(dist / 14))
          : 0;
        for (var i = 1; i <= steps; i++) {
          next.push({
            gx: last.gx + dx * i / (steps + 1),
            gy: last.gy + dy * i / (steps + 1),
            t: now - 33 * (steps + 1 - i)
          });
        }
      }
      next.push({ gx: root.cursorGX, gy: root.cursorGY, t: now });
      pts = next;
    }
    // Strokes keep more samples (continuity), pixels fewer (perf).
    var cap = root.trailStyle === "Pixels" ? 70 : 180;
    root.trailPoints = Halo.trimTrail(pts, now, root.trailLength, cap);
    root.trailTick = root.trailTick + 1;
  }

  function haloVisibleOn(screen) {
    // Moving OR clicking keeps the halo up in On-move mode, so clicking while
    // stationary still flashes it. Reading hideTick makes time itself
    // re-evaluate this binding, which is what hides it after the delay.
    var tick = root.hideTick;
    return Halo.shouldShow({
      enabled: root.cfgEnabled,
      onScreen: String(screen || "") === root.screenName && root.cursorOnScreen,
      held: root.heldButton !== "",
      mode: root.modeName,
      now: Date.now(),
      lastMoveAt: root.lastMoveAt,
      lastClickAt: root.lastClickShownAt
    });
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = Halo.parseCursorPos(text);
        var moved = false;
        if (p) {
          if (p.x !== root.cursorGX || p.y !== root.cursorGY) {
            root.cursorGX = p.x;
            root.cursorGY = p.y;
            root.lastMoveAt = Date.now();
            moved = true;
          }
        }
        // Runs every tick (not only on movement) so stale trail points keep
        // expiring while the cursor is still.
        if (root.trailsOn) root.sampleTrail(moved);
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = Halo.parseMonitors(text);
        if (list.length > 0) root.monitors = list;
      }
    }
  }

  Timer {
    id: cursorTimer
    interval: 33
    // Trails need samples even with the halo off: they are independent.
    running: root.cfgEnabled || root.trailsOn
    repeat: true
    triggeredOnStart: true
    onTriggered: cursorProc.running = true
  }
  Timer {
    interval: 5000
    running: root.cfgEnabled || root.trailsOn
    repeat: true
    triggeredOnStart: true
    onTriggered: monitorsProc.running = true
  }
  // Drives the On-move auto-hide; idle otherwise.
  Timer {
    interval: 300
    running: root.cfgEnabled && root.modeName === "On move"
    repeat: true
    onTriggered: root.hideTick = root.hideTick + 1
  }

  // ---- click bridge (written by comet-cursor.lua hypr binds) --------------
  readonly property string runDir: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR");
    if (runtime && runtime !== "") return runtime + "/nickmdrummer-comet-cursor";
    return (Quickshell.env("HOME") || "") + "/.cache/nickmdrummer-comet-cursor";
  }
  readonly property string clickPath: root.runDir + "/click.json"

  property int clickSeq: 0
  property string clickButton: ""
  property real pulse: 0
  property bool rippleActive: false
  property color currentColor: root.baseColor
  // Snapshot of the click color: the flash reverts after 200ms, but the
  // ripple keeps expanding in the click color instead of jumping to base.
  property color rippleColor: root.baseColor
  property double lastClickAt: 0
  // Epoch ms of the last click, for the On-move "clicked while still" rule.
  property double lastClickShownAt: 0
  // Button currently held down. While set, the flash color stays until the
  // release arrives, so a long press reads as a color state, not a blink.
  property string heldButton: ""
  // Time does not re-evaluate bindings by itself: in On-move mode a ticker
  // re-checks visibility so the halo hides ~1s after the cursor stops.
  property int hideTick: 0

  FileView {
    id: clickFile
    path: root.clickPath
    watchChanges: true
    printErrors: false
    // Reading text() inside onFileChanged returns the PREVIOUS content (the
    // property has not been refreshed yet), which silently swallowed real
    // clicks while a one-shot write looked fine. The documented pattern is to
    // reload and act on onLoaded, where text() is the new content.
    onFileChanged: reload()
    onLoaded: root.handleClickFile(text())
  }

  function handleClickFile(text) {
    var c = Halo.parseClick(text);
    if (!c) {
      // Empty read = caught the bridge mid-write; retry once after it lands.
      if (String(text || "") === "" && !clickRetry.running) clickRetry.restart();
      return;
    }
    if (c.at === root.lastClickAt) return;
    root.lastClickAt = c.at;
    root.clickButton = c.button;

    if (!c.down) {
      // Release: only the button that was actually held ends the color, so
      // releasing some other button does not clear a still-held highlight.
      if (root.heldButton === c.button) {
        root.heldButton = "";
        root.pulse = 0;
        root.currentColor = root.baseColor;
      }
      return;
    }

    root.heldButton = c.button;
    holdWatchdog.restart();
    root.clickSeq = root.clickSeq + 1;
    root.currentColor = Halo.clickColorFor(c.button, root.leftColor, root.rightColor, root.baseColor);
    root.rippleColor = root.currentColor;
    root.lastClickShownAt = Date.now();
    root.pulse = 1;
    pulseDecay.restart();
    if (root.rippleOn) {
      root.rippleActive = false;
      root.rippleActive = true;
      rippleOff.restart();
    }
  }

  // A release bind can be missed (submap, compositor hiccup). Never leave the
  // halo stuck in a click color forever.
  Timer {
    id: holdWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (root.heldButton !== "") {
      root.heldButton = "";
      root.currentColor = root.baseColor;
    }
  }

  // If the file was caught mid-write (truncate lands before the bytes), the
  // parse above sees "" and ignores it; one delayed re-read closes the race.
  Timer {
    id: clickRetry
    interval: 60
    repeat: false
    onTriggered: root.handleClickFile(clickFile.text())
  }

  // The pulse (scale) always settles to normal; only the COLOR is held while
  // a button stays down past the 200ms flash.
  Timer {
    id: pulseDecay
    interval: 200
    repeat: false
    onTriggered: {
      root.pulse = 0;
      if (root.heldButton === "") root.currentColor = root.baseColor;
    }
  }
  Timer {
    id: rippleOff
    interval: 480
    repeat: false
    onTriggered: root.rippleActive = false
  }

  // ---- bar button + popup -------------------------------------------------
  property bool menuOpen: false
  // appearance | behavior | trails
  property string activeTab: "appearance"
  function close() { root.menuOpen = false; }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : "◎"
    labelVisible: !root.vertical
    active: root.cfgEnabled
    dimmed: !root.cfgEnabled
    tooltipText: root.cfgEnabled ? strings.t("bar.tooltip-on", "Halo on — click to pause, right-click for settings") : strings.t("bar.tooltip-off", "Halo off — click to highlight cursor")

    onPressed: function(b) {
      if (b === Qt.RightButton) root.menuOpen = !root.menuOpen;
      else root.save({ enabled: !root.cfgEnabled });
    }
  }

  // Per-monitor overlay painted by this instance.
  Overlay { host: root }

  PopupCard {
    id: menu
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(320))
    // The card already insets its content by its own padding; the extra space
    // below is ours, and it must be part of the height or the last row ends up
    // squeezed against the bottom edge.
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight + Style.space(14))

    Rectangle {
      anchors.fill: parent
      radius: Math.max(0, Style.cornerRadius - Style.space(2))
      // Transparent: the PopupCard already paints the themed surface + border.
      color: "transparent"

      Column {
        id: menuColumn
        anchors.fill: parent
        // The PopupCard already pads its content; adding margins here double
        // inset it (and used to clip the last row). Only the extra breathing
        // room at the bottom is ours.
        anchors.bottomMargin: Style.space(14)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: strings.t("popup.title", "Comet Cursor")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // Tabs keep the growing settings list readable instead of one long
        // scroll: Appearance (look), Behavior (when/how it shows), Trails.
        ButtonGroup {
          width: parent.width
          fontSize: Style.font.bodySmall
          options: [
            { value: "appearance", label: strings.t("tab.appearance", "Appearance") },
            { value: "behavior", label: strings.t("tab.behavior", "Behavior") },
            { value: "trails", label: strings.t("tab.trails", "Trails") }
          ]
          value: root.activeTab
          foreground: Commons.Color.popups.text
          accent: Commons.Color.accent
          onChanged: function(v) { root.activeTab = v; }
        }

        // ---- Appearance -------------------------------------------------
        Column {
          visible: root.activeTab === "appearance"
          width: parent.width
          spacing: Style.space(8)

          StepperRow {
            title: strings.t("popup.shape", "Shape")
            display: root.shapeName
            onStepped: function(d) { root.save({ shape: Halo.cycleEnum(root.shapeName, Halo.SHAPES, d) }); }
          }

          StepperRow {
            title: strings.t("popup.size", "Size")
            display: root.sizeName
            onStepped: function(d) { root.save({ size: Halo.cycleEnum(root.sizeName, Halo.SIZES, d) }); }
          }

          StepperRow {
            title: strings.t("popup.border", "Border weight")
            display: root.weightName
            onStepped: function(d) { root.save({ borderWeight: Halo.cycleEnum(root.weightName, Halo.WEIGHTS, d) }); }
          }

          Hairline {}

          SwatchRow {
            title: strings.t("popup.color", "Halo color")
            current: Halo.cleanColor(root.setting("color", "#00FFC8"), "#00FFC8")
            onPicked: function(c) { root.save({ color: Halo.cleanColor(c, "#00FFC8") }); }
          }

          SwatchRow {
            title: strings.t("popup.left-click", "Left-click flash")
            current: Halo.cleanColor(root.setting("leftClickColor", "#FF2D55"), "#FF2D55")
            onPicked: function(c) { root.save({ leftClickColor: Halo.cleanColor(c, "#FF2D55") }); }
          }

          SwatchRow {
            title: strings.t("popup.right-click", "Right-click flash")
            current: Halo.cleanColor(root.setting("rightClickColor", "#3B82F6"), "#3B82F6")
            onPicked: function(c) { root.save({ rightClickColor: Halo.cleanColor(c, "#3B82F6") }); }
          }
        }

        // ---- Behavior ---------------------------------------------------
        Column {
          visible: root.activeTab === "behavior"
          width: parent.width
          spacing: Style.space(8)

          Toggle {
            width: parent.width
            label: strings.t("popup.enabled", "Enabled")
            description: strings.t("popup.enabled-hint", "Left-click the bar icon toggles too")
            checked: root.cfgEnabled
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            onClicked: root.save({ enabled: !root.cfgEnabled })
          }

          StepperRow {
            title: strings.t("popup.mode", "Show")
            display: root.modeName === "On move" ? strings.t("mode.on-move", "On move") : strings.t("mode.always", "Always")
            onStepped: function(d) { root.save({ mode: Halo.cycleEnum(root.modeName, Halo.MODES, d) }); }
          }

          Hairline {}

          Toggle {
            width: parent.width
            label: strings.t("popup.spotlight", "Spotlight")
            description: strings.t("popup.spotlight-hint", "Dim everything outside the halo")
            checked: root.spotlightOn
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            onClicked: root.save({ spotlight: !root.spotlightOn })
          }

          Toggle {
            width: parent.width
            label: strings.t("popup.ripple", "Ripple on click")
            description: strings.t("popup.ripple-hint", "Expanding ring when you click")
            checked: root.rippleOn
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            onClicked: root.save({ ripple: !root.rippleOn })
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: strings.t("popup.hold-hint", "Holding a click keeps its color until you release.")
            color: Commons.Color.popups.text
            opacity: 0.65
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- Trails -----------------------------------------------------
        Column {
          visible: root.activeTab === "trails"
          width: parent.width
          spacing: Style.space(8)

          StepperRow {
            title: strings.t("trail.style", "Style")
            display: root.trailStyle === "Off" ? strings.t("trail.off", "Off") : root.trailStyle
            onStepped: function(d) { root.save({ trailStyle: Halo.cycleEnum(root.trailStyle, Halo.TRAIL_STYLES, d) }); }
          }

          StepperRow {
            title: strings.t("trail.length", "Length")
            display: root.trailLength + " ms"
            interactive: root.trailsOn
            onStepped: function(d) {
              root.save({ trailLength: Halo.stepNumber(root.trailLength, { min: 200, max: 2000 }, 100, d) });
            }
          }

          StepperRow {
            title: strings.t("trail.width", "Width")
            display: String(root.trailWidth)
            interactive: root.trailsOn
            onStepped: function(d) {
              root.save({ trailWidth: Halo.stepNumber(root.trailWidth, { min: 2, max: 16 }, 1, d) });
            }
          }

          StepperRow {
            title: strings.t("trail.opacity", "Opacity")
            display: Math.round(root.trailAlpha * 100) + "%"
            interactive: root.trailsOn
            onStepped: function(d) {
              root.save({ trailOpacity: Halo.stepNumber(Math.round(root.trailAlpha * 100), { min: 20, max: 100 }, 10, d) });
            }
          }

          Hairline {}

          StepperRow {
            title: strings.t("trail.color-source", "Color")
            display: root.trailColorMode === "Custom"
              ? strings.t("trail.color-custom", "Custom")
              : strings.t("trail.color-halo", "Follow halo")
            interactive: root.trailsOn
            onStepped: function(d) {
              root.save({ trailColorMode: Halo.cycleEnum(root.trailColorMode, ["Halo", "Custom"], d) });
            }
          }

          SwatchRow {
            visible: root.trailColorMode === "Custom" && root.trailsOn
            title: strings.t("trail.color", "Trail color")
            current: Halo.cleanColor(root.setting("trailColor", "#00FFC8"), "#00FFC8")
            onPicked: function(c) { root.save({ trailColor: Halo.cleanColor(c, "#00FFC8") }); }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: strings.t("trail.hint", "Trails work on their own, even with the halo off.")
            color: Commons.Color.popups.text
            opacity: 0.65
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // One settings line: title on the left, a −/+ stepper on the right.
  // Inline controls replaced the Dropdowns because their popup opened as a
  // nested surface that got clipped by the settings window.
  component StepperRow: Item {
    id: sr
    required property string title
    required property string display
    property bool interactive: true
    signal stepped(int delta)

    width: parent ? parent.width : 0
    implicitHeight: Math.max(Style.spacing.controlHeight, valueText.implicitHeight)
    opacity: sr.interactive ? 1 : 0.45

    Text {
      id: rowLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - controls.width - Style.space(8))
      text: sr.title
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Row {
      id: controls
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        iconText: "−"
        foreground: Commons.Color.popups.text
        onClicked: if (sr.interactive) sr.stepped(-1)
      }

      Text {
        id: valueText
        width: Style.space(84)
        height: Style.spacing.controlHeight
        text: sr.display
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      PanelActionButton {
        iconText: "+"
        foreground: Commons.Color.popups.text
        onClicked: if (sr.interactive) sr.stepped(1)
      }
    }
  }

  // Hairline separator between groups inside a tab.
  component Hairline: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.14)
  }

  // Color swatch row used three times in the popup.
  component SwatchRow: Column {
    id: sw
    required property string title
    required property string current
    signal picked(string color)
    width: parent ? parent.width : 0
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      text: sw.title
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Row {
      spacing: Style.space(6)
      Repeater {
        model: ["#00FFC8", "#FF2D55", "#3B82F6", "#A855F7", "#FFB020", "#FFFFFF"]
        delegate: Rectangle {
          required property string modelData
          width: Style.space(26)
          height: width
          radius: width / 2
          color: modelData
          border.color: sw.current.toUpperCase() === String(modelData).toUpperCase() ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.25)
          border.width: sw.current.toUpperCase() === String(modelData).toUpperCase() ? 3 : 1

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.picked(parent.modelData)
          }
        }
      }
    }
  }
}
