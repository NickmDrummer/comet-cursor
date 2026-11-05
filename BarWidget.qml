import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HaloModel.js" as Halo

// Cursor Halo — Cursor Pro style mouse highlighter.
//   left click  : toggle enabled
//   right click : appearance popup
// Each bar instance paints the halo only on its own monitor.
BarWidget {
  id: root
  moduleName: "nickmdrummer.cursor-halo"

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
        if (p) {
          if (p.x !== root.cursorGX || p.y !== root.cursorGY) {
            root.cursorGX = p.x;
            root.cursorGY = p.y;
            root.lastMoveAt = Date.now();
          }
        }
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
    running: root.cfgEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: cursorProc.running = true
  }
  Timer {
    interval: 5000
    running: root.cfgEnabled
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

  // ---- click bridge (written by cursor-halo.lua hypr binds) --------------
  readonly property string runDir: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR");
    if (runtime && runtime !== "") return runtime + "/nickmdrummer-cursor-halo";
    return (Quickshell.env("HOME") || "") + "/.cache/nickmdrummer-cursor-halo";
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
    contentWidth: menu.fittedContentWidth(Style.space(300))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Rectangle {
      anchors.fill: parent
      radius: Math.max(0, Style.cornerRadius - Style.space(2))
      color: Commons.Color.background

      Column {
        id: menuColumn
        anchors.fill: parent
        anchors.margins: Style.space(14)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: strings.t("popup.title", "Cursor Halo")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Toggle {
          width: parent.width
          label: strings.t("popup.enabled", "Enabled")
          description: strings.t("popup.enabled-hint", "Left-click the bar icon toggles too")
          checked: root.cfgEnabled
          foreground: Commons.Color.foreground
          accent: Commons.Color.accent
          onClicked: root.save({ enabled: !root.cfgEnabled })
        }

        Dropdown {
          width: parent.width
          label: strings.t("popup.shape", "Shape")
          value: root.shapeName
          options: ["Circle", "Rhombus", "Rounded"]
          foreground: Commons.Color.popups.text
          onChanged: function(v) { root.save({ shape: Halo.cleanEnum(v, Halo.SHAPES, "Circle") }); }
        }

        Dropdown {
          width: parent.width
          label: strings.t("popup.size", "Size")
          value: root.sizeName
          options: ["S", "M", "L", "XL"]
          foreground: Commons.Color.popups.text
          onChanged: function(v) { root.save({ size: Halo.cleanEnum(v, Halo.SIZES, "L") }); }
        }

        Dropdown {
          width: parent.width
          label: strings.t("popup.border", "Border weight")
          value: root.weightName
          options: ["Thin", "Regular", "Bold"]
          foreground: Commons.Color.popups.text
          onChanged: function(v) { root.save({ borderWeight: Halo.cleanEnum(v, Halo.WEIGHTS, "Bold") }); }
        }

        Dropdown {
          width: parent.width
          label: strings.t("popup.mode", "Show")
          value: root.modeName
          options: ["Always", "On move"]
          foreground: Commons.Color.popups.text
          onChanged: function(v) { root.save({ mode: Halo.cleanEnum(v, Halo.MODES, "Always") }); }
        }

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
      }
    }
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
